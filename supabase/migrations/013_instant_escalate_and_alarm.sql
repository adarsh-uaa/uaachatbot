-- UAA Support · 013 Instant Escalation to Team & Alarm Trigger
-- Immediately triggers 'open' ticket status and dashboard alarm as soon as visitor clicks "Talk to our team" or asks for human support.

-- 1. Ensure escalation_alarm_enabled column exists on sites
alter table sites add column if not exists escalation_alarm_enabled boolean not null default true;

-- 2. Dedicated RPC: Instantly escalate conversation to human team when "Talk to our team" is clicked
create or replace function widget_escalate_to_team(
  p_site_key text,
  p_token uuid default null,
  p_reason text default 'Passenger requested to talk to support team'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
  clean_reason text := left(trim(coalesce(p_reason, 'Passenger requested to talk to support team')), 500);
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;

  if p_token is not null then
    select * into t from tickets where visitor_token = p_token;
  end if;

  if t.id is null then
    -- Create new open ticket waiting for human response
    insert into tickets(site_id, visitor_name, visitor_email, subject, status)
      values (s.id, 'Passenger #' || substring(gen_random_uuid()::text, 1, 4), null, clean_reason, 'open')
      returning * into t;
  else
    -- Escalate existing bot conversation immediately to 'open'
    update tickets set
      status = 'open',
      updated_at = now(),
      unread_by_staff = true
    where id = t.id;
  end if;

  -- Record escalation event in conversation history
  insert into ticket_messages(ticket_id, sender, body)
    values (t.id, 'visitor', clean_reason);

  return jsonb_build_object(
    'token', t.visitor_token,
    'ticket_no', t.ticket_no,
    'status', 'open',
    'escalated', true
  );
end $$;

grant execute on function widget_escalate_to_team(text,uuid,text) to anon, authenticated;

-- 3. Update widget_bot_chat so handoff keyword queries also transition status to 'open' immediately
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
  final_status ticket_status := 'bot';
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;
  if char_length(clean_q) not between 1 and 4000 then raise exception 'Message too long or empty'; end if;

  -- Find or create conversation session
  if p_token is not null then
    select * into t from tickets where visitor_token = p_token;
  end if;

  if t.id is null then
    insert into tickets(site_id, visitor_name, visitor_email, subject, status)
      values (s.id, 'Passenger #' || substring(gen_random_uuid()::text, 1, 4), null, left(clean_q, 80), 'bot')
      returning * into t;
  end if;

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', clean_q);
  update tickets set updated_at = now(), unread_by_staff = true where id = t.id;

  -- Check if claimed by live staff
  if t.status = 'claimed' and t.claimed_by is not null then
    select pseudo_name into agent_pseudo from profiles where id = t.claimed_by;
    return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no, 'claimed', true, 'agent', agent_pseudo, 'status', 'claimed');
  end if;

  -- Match keyword rules
  select * into matched_rule from bot_rules r
  where r.is_active and (r.site_id = s.id or r.site_id is null)
    and exists (
      select 1 from unnest(r.keywords) kw
      where (r.match_type = 'exact' and norm_q = _norm(kw))
         or (r.match_type = 'contains' and norm_q like '%' || _norm(kw) || '%')
    )
  order by r.priority asc, r.created_at asc
  limit 1;

  if matched_rule.id is not null then
    bot_resp := matched_rule.response;
    btn_label := matched_rule.button_label;
    if matched_rule.action = 'handoff' then
      is_handoff := true;
      final_status := 'open';
    elsif matched_rule.action = 'faq_link' then
      link_url := coalesce(matched_rule.link_url, s.faq_url);
    elsif matched_rule.link_url is not null then
      link_url := matched_rule.link_url;
    end if;
  else
    bot_resp := coalesce(s.texts->>'fallback', 'I could not find an automated answer for that. Please connect with our assistance team below and we will be happy to help:');
    is_handoff := true;
    final_status := 'open';
  end if;

  -- If handoff triggered, immediately elevate status to 'open' to sound the dashboard alarm!
  if is_handoff then
    update tickets set status = 'open', updated_at = now(), unread_by_staff = true where id = t.id;
  end if;

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'bot', bot_resp);

  return jsonb_build_object(
    'token', t.visitor_token,
    'ticket_no', t.ticket_no,
    'claimed', false,
    'reply', bot_resp,
    'link_url', link_url,
    'button_label', btn_label,
    'handoff', is_handoff,
    'status', final_status
  );
end $$;

grant execute on function widget_bot_chat(text,uuid,text) to anon, authenticated;

-- 4. Reload PostgREST schema cache
notify pgrst, 'reload schema';

