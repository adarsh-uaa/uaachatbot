-- Migration 021: Prevent duplicate visitor messages on form submission and avoid premature ticket creation when bot is disabled.

-- 1. Update widget_update_visitor_info to avoid inserting duplicate message if already recorded
create or replace function widget_update_visitor_info(
  p_token uuid,
  p_name text default null,
  p_email text default null,
  p_phone text default null,
  p_message text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t tickets;
  clean_msg text;
  last_visitor_body text;
begin
  select * into t from tickets where visitor_token = p_token;
  if not found then raise exception 'conversation not found'; end if;

  p_name := trim(coalesce(p_name, t.visitor_name));
  p_email := lower(trim(coalesce(p_email, '')));
  p_phone := trim(coalesce(p_phone, ''));
  clean_msg := trim(coalesce(p_message, ''));

  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please enter a valid email';
  end if;

  update tickets set
    visitor_name = p_name,
    visitor_email = p_email,
    visitor_phone = nullif(p_phone, ''),
    form_submitted = true,
    status = case when status = 'bot' then 'open'::ticket_status else status end,
    subject = case
      when clean_msg <> '' and (t.subject is null or t.subject like 'Passenger #%') then left(clean_msg, 80)
      else t.subject
    end,
    updated_at = now()
  where id = t.id;

  -- Only insert message if not empty AND not identical to the most recent visitor message on this ticket
  if char_length(clean_msg) > 0 then
    select body into last_visitor_body
    from ticket_messages
    where ticket_id = t.id and sender = 'visitor'
    order by created_at desc
    limit 1;

    if last_visitor_body is null or trim(last_visitor_body) <> clean_msg then
      insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', clean_msg);
    end if;
  end if;

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

grant execute on function widget_update_visitor_info(uuid, text, text, text, text) to anon, authenticated;

-- 2. Update widget_bot_chat to avoid premature ticket creation if bot is disabled and no ticket exists
create or replace function widget_bot_chat(
  p_site_key text,
  p_token text default null,
  p_query text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
  clean_q text := trim(coalesce(p_query, ''));
  norm_q text := _norm(clean_q);
  matched_rule bot_rules;
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
    select * into t from tickets where visitor_token = p_token::uuid;
  end if;

  -- If bot chat is disabled and no existing ticket exists, immediately hand off to form without creating premature tickets
  if not is_bot_on and t.id is null then
    return jsonb_build_object(
      'token', null,
      'ticket_no', null,
      'claimed', false,
      'reply', null,
      'link_url', null,
      'button_label', null,
      'handoff', true,
      'status', 'open'
    );
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

  -- Match rule by button_label, name, or keywords
  select * into matched_rule from bot_rules r
  where r.is_active and (r.site_id = s.id or r.site_id is null)
    and (
      (r.button_label is not null and (
        (r.match_type = 'exact' and norm_q = _norm(r.button_label))
        or (r.match_type = 'contains' and norm_q like '%' || _norm(r.button_label) || '%')
      ))
      or (r.name is not null and (
        (r.match_type = 'exact' and norm_q = _norm(r.name))
        or (r.match_type = 'contains' and norm_q like '%' || _norm(r.name) || '%')
      ))
      or exists (
        select 1 from unnest(r.keywords) kw
        where (r.match_type = 'exact' and norm_q = _norm(kw))
           or (r.match_type = 'contains' and norm_q like '%' || _norm(kw) || '%')
      )
    )
  order by r.priority asc, r.created_at asc
  limit 1;

  if matched_rule.id is not null then
    bot_resp := matched_rule.response;
    btn_label := matched_rule.button_label;
    link_url := matched_rule.link_url;
    if matched_rule.action = 'faq_link' and link_url is null then link_url := s.faq_url; end if;
    if matched_rule.action = 'handoff' then is_handoff := true; end if;

    insert into bot_events(site_id, rule_id, visitor_token, query, matched)
    values (s.id, matched_rule.id, t.visitor_token, clean_q, true);

    if bot_resp is not null and length(trim(bot_resp)) > 0 then
      insert into ticket_messages(ticket_id, sender, body) values (t.id, 'bot', bot_resp);
    end if;

    return jsonb_build_object(
      'token', t.visitor_token,
      'ticket_no', t.ticket_no,
      'claimed', false,
      'reply', bot_resp,
      'link_url', link_url,
      'button_label', btn_label,
      'handoff', is_handoff,
      'status', t.status
    );
  end if;

  -- Log unmatched query for dashboard analytics
  insert into bot_events(site_id, rule_id, visitor_token, query, matched)
  values (s.id, null, t.visitor_token, clean_q, false);

  return jsonb_build_object(
    'token', t.visitor_token,
    'ticket_no', t.ticket_no,
    'claimed', false,
    'reply', null,
    'link_url', null,
    'button_label', null,
    'handoff', true,
    'status', t.status
  );
end $$;

grant execute on function widget_bot_chat(text, text, text) to anon, authenticated;

