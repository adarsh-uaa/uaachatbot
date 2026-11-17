-- ============================================================================
-- Migration 017: Comprehensive Bot Rule Matching & Airport Suggestions
-- Ensures quick reply pills (such as "Terminal amenities") and rule names
-- match reliably in widget_bot_chat, and enriches keyword mappings.
-- ============================================================================

-- 1. Enrich keywords for built-in airport rules so exact or contains queries match
update bot_rules
set keywords = array['terminal', 'terminals', 'amenity', 'amenities', 'wifi', 'wi-fi', 'internet', 'restroom', 'restrooms', 'toilet', 'toilets', 'bathroom', 'washroom', 'food', 'restaurant', 'cafe', 'coffee', 'lounge', 'lounges', 'atm', 'cash', 'money', 'charging', 'charger', 'parking', 'taxi', 'cab', 'bus', 'train', 'water', 'smoking', 'prayer']
where name = 'Terminal Amenities & Wi-Fi' or button_label = 'Terminal amenities';

update bot_rules
set keywords = array['wheelchair', 'mobility', 'prm', 'disabled', 'disability', 'handicap', 'walking', 'elderly', 'senior', 'stretcher', 'ramp', 'special assistance', 'escort', 'buggy', 'electric cart', 'accessible', 'assistance']
where name = 'Wheelchair & Mobility (PRM)' or button_label = 'Wheelchair assistance';

update bot_rules
set keywords = array['baggage', 'luggage', 'bags', 'bag', 'suitcase', 'lost bag', 'lost luggage', 'delayed baggage', 'damaged bag', 'carousel', 'lost property', 'lost and found', 'lost item', 'lost my', 'left behind', 'left luggage', 'items']
where name = 'Baggage & Lost Items' or button_label = 'Lost baggage & items';

update bot_rules
set keywords = array['flight', 'gate', 'terminal', 'boarding', 'check in', 'checkin', 'check-in', 'delay', 'departure', 'arrival', 'boarding pass', 'counter', 'security', 'fast track', 'customs', 'passport', 'status', 'schedule', 'info']
where name = 'Flight & Gate Info' or button_label = 'Flight & Gate info';

update bot_rules
set keywords = array['human', 'agent', 'person', 'staff', 'representative', 'talk to someone', 'speak to someone', 'talk to team', 'connect', 'live agent', 'operator', 'call me', 'urgent', 'real person', 'help me', 'team', 'support', 'talk to our team']
where name = 'Talk to Support Team' or button_label = 'Talk to our team';

-- 2. Update widget_bot_chat to match button_label and name in addition to keywords
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

  -- If bot chat is disabled for this site, team takes the ticket directly
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

grant execute on function widget_bot_chat(text,text,text) to anon, authenticated;

