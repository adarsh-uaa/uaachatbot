-- UAA Support · 007 Bot chats tracking, human takeover, phone numbers, and teams
create extension if not exists pgcrypto;

-- 1. Ensure teams table exists and profiles has team_id
create table if not exists teams (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  color text not null default '#0f7c86',
  lead_id uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'profiles' and column_name = 'team_id'
  ) then
    alter table profiles add column team_id uuid references teams(id) on delete set null;
  end if;
end $$;

-- update staff_public view so it includes team_id and created_at
create or replace view staff_public with (security_invoker = false) as
  select id, pseudo_name, role, is_active, team_id, created_at from profiles;

-- RLS on teams
alter table teams enable row level security;

drop policy if exists teams_read on teams;
create policy teams_read on teams for select to authenticated using (is_staff());

drop policy if exists teams_write on teams;
create policy teams_write on teams for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));

grant select on teams to authenticated;
revoke all on teams from anon;

-- Seed default teams if empty
insert into teams (name, description, color) values
  ('Passenger Assistance (PRM)', 'Wheelchair, mobility and dedicated passenger assistance services', '#0f7c86'),
  ('Customer Care & Enquiries', 'General airport enquiries, flight info, check-in, and lost property', '#1f7a4d'),
  ('Operations & Dispatch', 'Airside coordination, terminal dispatch, and escalation handling', '#b45309'),
  ('Baggage & Lost Property', 'Luggage retrieval, delayed baggage, and items lost in terminal', '#6366f1')
on conflict (name) do nothing;

-- 2. Add 'bot' status to ticket_status enum if not present
do $$
begin
  if not exists (
    select 1 from pg_enum 
    where enumtypid = 'ticket_status'::regtype and enumlabel = 'bot'
  ) then
    alter type ticket_status add value 'bot' before 'open';
  end if;
end $$;

-- 3. Add visitor_phone to tickets table and relax constraints for bot sessions
alter table tickets add column if not exists visitor_phone text;
alter table tickets alter column visitor_name set default 'Visitor';
alter table tickets alter column visitor_email drop not null;

-- 4. Overload/Update widget_create_ticket to accept visitor_phone
create or replace function widget_create_ticket(
  p_site_key text,
  p_name text,
  p_email text,
  p_message text,
  p_phone text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;

  p_name := trim(coalesce(p_name,''));
  p_email := lower(trim(coalesce(p_email,'')));
  p_phone := trim(coalesce(p_phone,''));
  p_message := trim(coalesce(p_message,''));

  if char_length(p_name) not between 1 and 80 then raise exception 'Please enter your name'; end if;
  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(p_email) > 160 then raise exception 'Please enter a valid email'; end if;
  if char_length(p_message) not between 1 and 4000 then raise exception 'Please enter a message'; end if;

  if (select count(*) from tickets where site_id = s.id and visitor_email = p_email and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Too many requests, please try again later';
  end if;

  insert into tickets(site_id, visitor_name, visitor_email, visitor_phone, subject, status)
    values (s.id, p_name, p_email, nullif(p_phone, ''), left(p_message, 100), 'open')
    returning * into t;

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', p_message);
  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

grant execute on function widget_create_ticket(text,text,text,text,text) to anon, authenticated;

-- 5. RPC to update visitor info when form is submitted after bot chat
create or replace function widget_update_visitor_info(
  p_token uuid,
  p_name text,
  p_email text,
  p_phone text default null,
  p_message text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t tickets;
begin
  select * into t from tickets where visitor_token = p_token;
  if not found then raise exception 'conversation not found'; end if;

  p_name := trim(coalesce(p_name, t.visitor_name));
  p_email := lower(trim(coalesce(p_email, '')));
  p_phone := trim(coalesce(p_phone, ''));
  p_message := trim(coalesce(p_message, ''));

  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please enter a valid email';
  end if;

  update tickets set
    visitor_name = p_name,
    visitor_email = p_email,
    visitor_phone = nullif(p_phone, ''),
    status = case when status = 'bot' then 'open'::ticket_status else status end,
    updated_at = now()
  where id = t.id;

  if char_length(p_message) > 0 then
    insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', p_message);
  end if;

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

grant execute on function widget_update_visitor_info(uuid,text,text,text,text) to anon, authenticated;

-- 6. RPC for live bot chats and human takeover check
create or replace function widget_bot_chat(
  p_site_key text,
  p_token uuid,
  p_query text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
  clean_q text := trim(coalesce(p_query, ''));
  norm_q text := _norm(clean_q);
  matched_rule bot_rules%rowtype;
  bot_resp text;
  link_url text;
  btn_label text;
  is_handoff boolean := false;
  agent_pseudo text;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;
  if char_length(clean_q) not between 1 and 4000 then raise exception 'Message too long or empty'; end if;

  -- 1. Find or create ticket for this visitor session
  if p_token is not null then
    select * into t from tickets where visitor_token = p_token;
  end if;

  if t.id is null then
    -- Create new bot chat ticket
    insert into tickets(site_id, visitor_name, visitor_email, subject, status)
      values (s.id, 'Visitor #' || substring(gen_random_uuid()::text, 1, 4), null, left(clean_q, 80), 'bot')
      returning * into t;
  end if;

  -- 2. Record visitor message
  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', clean_q);
  update tickets set updated_at = now(), unread_by_staff = true where id = t.id;

  -- 3. Check if staff has CLAIMED or taken over this chat!
  if t.status = 'claimed' and t.claimed_by is not null then
    select pseudo_name into agent_pseudo from profiles where id = t.claimed_by;
    -- AUTOMATED BOT REPLIES ARE DISABLED! Staff is assisting live.
    return jsonb_build_object(
      'token', t.visitor_token,
      'ticket_no', t.ticket_no,
      'claimed', true,
      'agent', agent_pseudo,
      'status', 'claimed'
    );
  end if;

  -- 4. Not claimed: Process bot keyword rules
  select * into matched_rule from bot_rules r
  where r.is_active and (r.site_id = s.id or r.site_id is null)
    and exists (
      select 1 from unnest(r.keywords) kw
      where (r.match_type = 'exact' and norm_q = _norm(kw))
         or (r.match_type = 'contains' and norm_q like '%' || _norm(kw) || '%')
    )
  order by r.priority asc, r.created_at asc
  limit 1;

  -- Log query to bot_events
  insert into bot_events(site_id, rule_id, query, matched)
    values (s.id, matched_rule.id, norm_q, (matched_rule.id is not null));

  if matched_rule.id is not null then
    bot_resp := matched_rule.response;
    btn_label := matched_rule.button_label;
    if matched_rule.action = 'handoff' then
      is_handoff := true;
    elsif matched_rule.action = 'faq_link' then
      link_url := coalesce(matched_rule.link_url, s.faq_url);
    elsif matched_rule.link_url is not null then
      link_url := matched_rule.link_url;
    end if;
  else
    bot_resp := coalesce(s.texts->>'fallback', 'I could not find an answer for that. Would you like to talk to our team?');
    is_handoff := true;
  end if;

  -- Record bot reply in ticket_messages
  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'bot', bot_resp);

  return jsonb_build_object(
    'token', t.visitor_token,
    'ticket_no', t.ticket_no,
    'claimed', false,
    'reply', bot_resp,
    'link_url', link_url,
    'button_label', btn_label,
    'handoff', is_handoff,
    'status', 'bot'
  );
end $$;

grant execute on function widget_bot_chat(text,uuid,text) to anon, authenticated;

-- 7. Update claim_ticket so taking over a bot chat halts automated replies with a system notification
create or replace function claim_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me profiles;
  t tickets;
  was_bot boolean;
begin
  perform _need('tickets.claim');
  select * into me from profiles where id = auth.uid();
  if not me.is_active then raise exception 'inactive account'; end if;

  select * into t from tickets where id = p_ticket;
  if not found then raise exception 'ticket not found'; end if;
  if t.status = 'closed' then raise exception 'ticket is closed'; end if;
  if t.claimed_by is not null and t.claimed_by <> me.id then
    raise exception 'already claimed by %', (select pseudo_name from profiles where id = t.claimed_by);
  end if;

  was_bot := (t.status = 'bot');

  update tickets
  set
    status = 'claimed',
    claimed_by = me.id,
    claimed_at = coalesce(claimed_at, now()),
    updated_at = now()
  where id = p_ticket;

  -- Add system message
  if was_bot then
    insert into ticket_messages(ticket_id, sender, body, is_internal)
      values (p_ticket, 'system', me.pseudo_name || ' joined the chat. Automated bot replies are now disabled.', false);
  else
    insert into ticket_messages(ticket_id, sender, body, is_internal)
      values (p_ticket, 'system', me.pseudo_name || ' claimed this ticket', true);
  end if;
end $$;

grant execute on function claim_ticket(uuid) to authenticated;

