-- UAA Support · 010 Real-time Ongoing Chats, Quick Replies, and Staff Takeover

create extension if not exists pgcrypto;

-- 1. Ensure 'bot' status exists in ticket_status enum
do $$
begin
  if not exists (
    select 1 from pg_enum 
    where enumtypid = 'ticket_status'::regtype and enumlabel = 'bot'
  ) then
    alter type ticket_status add value 'bot' before 'open';
  end if;
end $$;

-- 2. Allow anonymous visitors to start ongoing quick-reply chats without requiring an email upfront
alter table tickets add column if not exists visitor_phone text;
alter table tickets alter column visitor_name set default 'Passenger';
alter table tickets alter column visitor_email drop not null;

-- 3. Ensure cascading delete constraint on site_id
alter table tickets drop constraint if exists tickets_site_id_fkey;
alter table tickets add constraint tickets_site_id_fkey foreign key (site_id) references sites(id) on delete cascade;

-- 4. Clean function overloads for widget_create_ticket
drop function if exists widget_create_ticket(text, text, text, text);
drop function if exists widget_create_ticket(text, text, text, text, text);

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

  insert into tickets(site_id, visitor_name, visitor_email, visitor_phone, subject, status)
    values (s.id, p_name, p_email, nullif(p_phone, ''), left(p_message, 100), 'open')
    returning * into t;

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', p_message);
  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

grant execute on function widget_create_ticket(text,text,text,text,text) to anon, authenticated;

-- 5. RPC to update visitor info when form is submitted after bot / quick-reply chat
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

-- 6. Core RPC for tracking ongoing quick replies, bot chats, and live agent takeover
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

  -- 1. Find or create ongoing conversation session for this visitor
  if p_token is not null then
    select * into t from tickets where visitor_token = p_token;
  end if;

  if t.id is null then
    -- Create new ongoing chat session visible to staff immediately
    insert into tickets(site_id, visitor_name, visitor_email, subject, status)
      values (s.id, 'Passenger #' || substring(gen_random_uuid()::text, 1, 4), null, left(clean_q, 80), 'bot')
      returning * into t;
  end if;

  -- 2. Record visitor question / quick-reply in thread
  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', clean_q);
  update tickets set updated_at = now(), unread_by_staff = true where id = t.id;

  -- 3. Check if staff has CLAIMED or taken over this chat live
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

  -- 4. Not claimed: Process keyword rules
  select * into matched_rule from bot_rules r
  where r.is_active and (r.site_id = s.id or r.site_id is null)
    and exists (
      select 1 from unnest(r.keywords) kw
      where (r.match_type = 'exact' and norm_q = _norm(kw))
         or (r.match_type = 'contains' and norm_q like '%' || _norm(kw) || '%')
    )
  order by r.priority asc, r.created_at asc
  limit 1;

  -- Log query event
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
    bot_resp := coalesce(s.texts->>'fallback', 'I could not find an automated answer for that. Would you like to connect with our support team? Please share your details below.');
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

-- 7. Claim ticket RPC: Taking over a bot conversation notifies the thread and pauses bots
create or replace function claim_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me profiles;
  t tickets;
  was_bot boolean;
begin
  perform _need('tickets.claim');
  select * into me from profiles where id = auth.uid();
  select * into t from tickets where id = p_ticket and status <> 'closed';
  if not found then raise exception 'ticket not found or closed'; end if;

  was_bot := (t.status = 'bot');

  update tickets set
    claimed_by = auth.uid(),
    claimed_at = now(),
    status = 'claimed',
    updated_at = now(),
    unread_by_staff = false
  where id = p_ticket;

  if was_bot then
    insert into ticket_messages(ticket_id, sender, body)
      values (p_ticket, 'system', me.pseudo_name || ' has taken over the conversation. Automated replies are paused.');
  end if;
end $$;

grant execute on function claim_ticket(uuid) to authenticated;

-- 8. Seed comprehensive default airport keyword mappings (global for all sites)
insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active)
select null, 'Greetings & Welcome', array['hello', 'hi', 'hey', 'good morning', 'good afternoon', 'good evening', 'start', 'greetings', 'help', 'howdy', 'welcome', 'hola'], 'contains', 'reply', 'Hello! Welcome to our airport assistance desk. How can we help you today? You can ask about wheelchair assistance, baggage, flight details, or connect directly with our team.', null, 'Hello', 10, true
where not exists (select 1 from bot_rules where name = 'Greetings & Welcome' and site_id is null);

insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active)
select null, 'Wheelchair & Mobility (PRM)', array['wheelchair', 'mobility', 'prm', 'disabled', 'disability', 'handicap', 'walking', 'elderly', 'senior', 'stretcher', 'ramp', 'special assistance', 'escort', 'buggy', 'electric cart', 'accessible', 'blind', 'deaf', 'assistance'], 'contains', 'reply', 'We provide dedicated assistance for passengers with reduced mobility (PRM) free of charge. Our team can meet you at terminal entry, assist through check-in, security, and boarding. Please book at least 48 hours in advance for priority scheduling.', null, 'Wheelchair assistance', 20, true
where not exists (select 1 from bot_rules where name = 'Wheelchair & Mobility (PRM)' and site_id is null);

insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active)
select null, 'Baggage & Lost Items', array['baggage', 'luggage', 'bags', 'bag', 'suitcase', 'lost bag', 'lost luggage', 'delayed baggage', 'damaged bag', 'carousel', 'lost property', 'lost and found', 'lost item', 'lost my', 'left behind', 'left luggage'], 'contains', 'reply', 'For baggage retrieval, delayed luggage, or items left inside the terminal, our Lost Property & Baggage desk is located in the Arrivals Hall near Carousel 3. Would you like to connect with our team to report a lost item?', null, 'Lost baggage & items', 30, true
where not exists (select 1 from bot_rules where name = 'Baggage & Lost Items' and site_id is null);

insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active)
select null, 'Flight & Gate Info', array['flight', 'gate', 'terminal', 'boarding', 'check in', 'checkin', 'check-in', 'delay', 'departure', 'arrival', 'boarding pass', 'counter', 'security', 'fast track', 'customs', 'passport', 'status', 'schedule'], 'contains', 'reply', 'Check-in desks open 3 hours prior to international flights and 2 hours for domestic flights. Live gate assignments and flight schedules are displayed on terminal screens throughout the airport.', null, 'Flight & Gate info', 40, true
where not exists (select 1 from bot_rules where name = 'Flight & Gate Info' and site_id is null);

insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active)
select null, 'Terminal Amenities & Wi-Fi', array['wifi', 'wi-fi', 'internet', 'restroom', 'restrooms', 'toilet', 'toilets', 'bathroom', 'washroom', 'food', 'restaurant', 'cafe', 'coffee', 'lounge', 'lounges', 'atm', 'cash', 'money', 'charging', 'charger', 'parking', 'taxi', 'cab', 'bus', 'train', 'water', 'smoking', 'prayer'], 'contains', 'reply', 'Free high-speed airport Wi-Fi is available across all terminals. Restrooms, charging stations, prayer rooms, dining, and airline lounges are located along the central concourses.', null, 'Terminal amenities', 50, true
where not exists (select 1 from bot_rules where name = 'Terminal Amenities & Wi-Fi' and site_id is null);

insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active)
select null, 'Talk to Support Team', array['human', 'agent', 'person', 'staff', 'representative', 'talk to someone', 'speak to someone', 'talk to team', 'connect', 'live agent', 'operator', 'call me', 'urgent', 'real person', 'help me', 'team', 'support'], 'contains', 'handoff', 'I would be happy to connect you with our assistance team. Please fill in your details below so an agent can assist you right away:', null, 'Talk to our team', 5, true
where not exists (select 1 from bot_rules where name = 'Talk to Support Team' and site_id is null);

-- 9. Refresh PostgREST schema cache immediately
notify pgrst, 'reload schema';
