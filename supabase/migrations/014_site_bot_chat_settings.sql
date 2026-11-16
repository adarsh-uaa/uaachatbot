-- UAA Support · 014 Per-Site Bot Chat Toggle, Direct Form Mode, and Form Submission Tracking
-- 1. Adds bot_chat_enabled column to sites table (defaults to false for direct team mode)
-- 2. Adds form_submitted column to tickets table to track whether passenger filled contact form
-- 3. Updates widget_config, widget_create_ticket, widget_update_visitor_info, and widget_bot_chat

-- 1. Add bot_chat_enabled column to sites table (defaults to false)
alter table sites add column if not exists bot_chat_enabled boolean not null default false;

-- 2. Add form_submitted column to tickets table (defaults to false)
alter table tickets add column if not exists form_submitted boolean not null default false;

-- Backfill form_submitted for tickets where real email/phone is present
update tickets set form_submitted = true
where visitor_email is not null
  and visitor_email !~* '@uaa\.chat'
  and visitor_email !~* 'anonymous'
  and visitor_name not like 'Passenger #%';

-- 3. Update widget_config RPC to return bot_chat_enabled
create or replace function widget_config(p_site_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s sites;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  return jsonb_build_object(
    'site_name', s.name,
    'theme', s.theme,
    'texts', s.texts,
    'faq_url', s.faq_url,
    'escalation_alarm_enabled', coalesce(s.escalation_alarm_enabled, (s.theme->>'escalation_alarm_enabled')::boolean, true),
    'bot_chat_enabled', coalesce(s.bot_chat_enabled, (s.theme->>'bot_chat_enabled')::boolean, false),
    'rules', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'name', r.name,
          'keywords', r.keywords,
          'match_type', r.match_type,
          'action', r.action,
          'response', r.response,
          'link_url', r.link_url,
          'button_label', r.button_label
        ) order by r.priority asc, r.created_at asc
      ), '[]'::jsonb)
      from bot_rules r
      where (r.site_id = s.id or r.site_id is null) and r.is_active
    )
  );
end $$;

grant execute on function widget_config(text) to anon, authenticated;

-- 4. Update widget_create_ticket to mark form_submitted = true
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

  p_name := trim(coalesce(p_name,'Passenger'));
  p_email := lower(trim(coalesce(p_email,'')));
  p_phone := trim(coalesce(p_phone,''));
  p_message := trim(coalesce(p_message,''));

  if char_length(p_name) not between 1 and 80 then raise exception 'Please enter your name'; end if;
  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(p_email) > 160 then raise exception 'Please enter a valid email'; end if;
  if char_length(p_message) not between 1 and 4000 then raise exception 'Please enter a message'; end if;

  if (select count(*) from tickets where site_id = s.id and visitor_email = p_email and created_at > now() - interval '1 hour') >= 15 then
    raise exception 'Too many requests, please try again later';
  end if;

  insert into tickets(site_id, visitor_name, visitor_email, visitor_phone, subject, status, form_submitted)
    values (s.id, p_name, p_email, nullif(p_phone, ''), left(p_message, 100), 'open', true)
    returning * into t;

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', p_message);
  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

grant execute on function widget_create_ticket(text,text,text,text,text) to anon, authenticated;

-- 5. Update widget_update_visitor_info to mark form_submitted = true
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
    form_submitted = true,
    status = case when status = 'bot' then 'open'::ticket_status else status end,
    updated_at = now()
  where id = t.id;

  if char_length(p_message) > 0 then
    insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', p_message);
  end if;

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

grant execute on function widget_update_visitor_info(uuid,text,text,text,text) to anon, authenticated;

-- 6. Update widget_bot_chat to respect bot_chat_enabled
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
  is_bot_on boolean;
  final_status ticket_status := 'open';
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;
  if char_length(clean_q) not between 1 and 4000 then raise exception 'Message too long or empty'; end if;

  is_bot_on := coalesce(s.bot_chat_enabled, (s.theme->>'bot_chat_enabled')::boolean, false);

  if p_token is not null then
    select * into t from tickets where visitor_token = p_token;
  end if;

  if t.id is null then
    final_status := case when is_bot_on then 'bot'::ticket_status else 'open'::ticket_status end;
    insert into tickets(site_id, visitor_name, visitor_email, subject, status, form_submitted)
      values (s.id, 'Passenger #' || substring(gen_random_uuid()::text, 1, 4), null, left(clean_q, 80), final_status, false)
      returning * into t;
  end if;

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', clean_q);
  update tickets set updated_at = now(), unread_by_staff = true where id = t.id;

  if t.status = 'claimed' and t.claimed_by is not null then
    select pseudo_name into agent_pseudo from profiles where id = t.claimed_by;
    return jsonb_build_object(
      'token', t.visitor_token,
      'ticket_no', t.ticket_no,
      'claimed', true,
      'agent', agent_pseudo,
      'status', 'claimed'
    );
  end if;

  -- If bot chat is disabled for this site, team takes the ticket directly! No automated bot reply.
  if not is_bot_on then
    update tickets set status = 'open', updated_at = now(), unread_by_staff = true where id = t.id;
    return jsonb_build_object(
      'token', t.visitor_token,
      'ticket_no', t.ticket_no,
      'claimed', false,
      'reply', null,
      'link_url', null,
      'button_label', null,
      'handoff', false,
      'status', 'open'
    );
  end if;

  -- Bot chat is enabled: match keyword rules
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

-- 7. Reload PostgREST schema cache
notify pgrst, 'reload schema';
