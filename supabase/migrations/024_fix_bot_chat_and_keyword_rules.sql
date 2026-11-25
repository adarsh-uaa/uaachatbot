-- Migration 024: Fix bot chat keyword rules & prevent false ticket creation
-- 1. Automated bot replies (reply, faq_link) should NOT create tickets or alarms on the staff dashboard.
-- 2. Improved keyword matching (two-way containment, plurals, normalized tokens).
-- 3. Tickets are only created when human handoff is requested or when visitor submits the contact form.

-- Ensure bot_chat_enabled column exists on sites
alter table sites add column if not exists bot_chat_enabled boolean not null default false;

-- 1. Update widget_config to reliably return bot_chat_enabled and all active rules
create or replace function widget_config(p_site_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s sites;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;

  return jsonb_build_object(
    'site_name', s.name,
    'theme', s.theme,
    'texts', s.texts,
    'faq_url', s.faq_url,
    'escalation_alarm_enabled', coalesce(s.escalation_alarm_enabled, (s.theme->>'escalation_alarm_enabled')::boolean, true),
    'bot_chat_enabled', case
      when s.bot_chat_enabled = true or (s.theme->>'bot_chat_enabled')::boolean = true then true
      when s.bot_chat_enabled = false and (s.theme->>'bot_chat_enabled')::boolean = false then false
      else exists (select 1 from bot_rules br where (br.site_id = s.id or br.site_id is null) and br.is_active and br.action = 'reply')
    end,
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

-- 2. Update widget_bot_chat:
-- - Solves Issue 1: Enhanced multi-tier keyword matching
-- - Solves Issue 2: Zero tickets created in database when bot answers successfully
-- - Solves Issue 3: Clean handoff handling without unexpected form hijacking
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
  clean_tok text;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;
  if char_length(clean_q) not between 1 and 4000 then raise exception 'Message too long or empty'; end if;

  is_bot_on := case
    when s.bot_chat_enabled = true or (s.theme->>'bot_chat_enabled')::boolean = true then true
    when s.bot_chat_enabled = false and (s.theme->>'bot_chat_enabled')::boolean = false then false
    else exists (select 1 from bot_rules br where (br.site_id = s.id or br.site_id is null) and br.is_active and br.action = 'reply')
  end;

  -- Check if visitor already has an active claimed live agent session
  if p_token is not null and p_token ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into t from tickets where visitor_token = p_token::uuid;
    if t.id is not null and t.status = 'claimed' and t.claimed_by is not null then
      select pseudo_name into agent_pseudo from profiles where id = t.claimed_by;
      insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', clean_q);
      update tickets set updated_at = now(), unread_by_staff = true where id = t.id;
      return jsonb_build_object(
        'token', t.visitor_token,
        'ticket_no', t.ticket_no,
        'claimed', true,
        'agent', agent_pseudo,
        'status', 'claimed'
      );
    end if;
  end if;

  -- If bot is disabled: return handoff without automated responses
  if not is_bot_on then
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

  -- Robust Rule Matching:
  -- 1. Exact match with button_label, name, or keywords
  -- 2. Two-way containment (query contains keyword, or keyword contains query)
  -- 3. Plural handling ('s')
  select * into matched_rule from bot_rules r
  where r.is_active and (r.site_id = s.id or r.site_id is null)
    and (
      -- Match button label
      (r.button_label is not null and (
        norm_q = _norm(r.button_label)
        or (r.match_type = 'contains' and (
          norm_q like '%' || _norm(r.button_label) || '%'
          or _norm(r.button_label) like '%' || norm_q || '%'
        ))
      ))
      -- Match rule name
      or (r.name is not null and (
        norm_q = _norm(r.name)
        or (r.match_type = 'contains' and (
          norm_q like '%' || _norm(r.name) || '%'
          or _norm(r.name) like '%' || norm_q || '%'
        ))
      ))
      -- Match keywords array
      or exists (
        select 1 from unnest(r.keywords) kw
        where (
          r.match_type = 'exact' and (
            norm_q = _norm(kw)
            or norm_q = _norm(kw || 's')
            or norm_q = _norm(kw || 'es')
          )
        ) or (
          r.match_type = 'contains' and (
            norm_q like '%' || _norm(kw) || '%'
            or norm_q like '%' || _norm(kw || 's') || '%'
            or norm_q like '%' || _norm(kw || 'es') || '%'
            or (length(trim(clean_q)) >= 3 and _norm(kw) like '%' || norm_q || '%')
          )
        )
      )
    )
  order by r.priority asc, r.created_at asc
  limit 1;

  -- If a keyword rule matched
  if matched_rule.id is not null then
    bot_resp := matched_rule.response;
    btn_label := matched_rule.button_label;
    link_url := matched_rule.link_url;
    if matched_rule.action = 'faq_link' and link_url is null then
      link_url := s.faq_url;
    end if;

    -- Record search hit in analytics
    insert into bot_events(site_id, rule_id, visitor_token, query, matched)
    values (s.id, matched_rule.id, coalesce(t.visitor_token, null), clean_q, true);

    -- If the rule is an explicit human handoff action ("Talk to our team")
    if matched_rule.action = 'handoff' then
      if t.id is null then
        insert into tickets(site_id, visitor_name, visitor_email, subject, status, form_submitted)
        values (s.id, 'Passenger #' || substring(gen_random_uuid()::text, 1, 4), null, left(clean_q, 80), 'open', false)
        returning * into t;
      else
        update tickets set status = 'open', updated_at = now(), unread_by_staff = true where id = t.id;
      end if;

      insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', clean_q);
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
        'handoff', true,
        'status', 'open'
      );
    end if;

    -- Automated Answer (reply or faq_link):
    -- Do NOT create a ticket or spam the staff dashboard queue!
    return jsonb_build_object(
      'token', null,
      'ticket_no', null,
      'claimed', false,
      'reply', bot_resp,
      'link_url', link_url,
      'button_label', btn_label,
      'handoff', false,
      'status', 'bot'
    );
  end if;

  -- No rule matched (unanswered query)
  insert into bot_events(site_id, rule_id, visitor_token, query, matched)
  values (s.id, null, coalesce(t.visitor_token, null), clean_q, false);

  return jsonb_build_object(
    'token', null,
    'ticket_no', null,
    'claimed', false,
    'reply', coalesce(s.texts->>'fallback', 'I could not find an automated answer for that. Please connect with our assistance team below:'),
    'link_url', null,
    'button_label', null,
    'handoff', true,
    'status', 'bot'
  );
end $$;

grant execute on function widget_bot_chat(text, text, text) to anon, authenticated;

