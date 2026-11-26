-- Migration 026: Save full previous bot conversation history to tickets
-- Ensures staff can see everything the passenger previously asked and what the bot replied

-- Drop existing function signatures to avoid PostgreSQL parameter default mismatch (ERROR: 42P13)
drop function if exists widget_create_ticket(text, text, text, text, text, jsonb);
drop function if exists widget_create_ticket(text, text, text, text, text);
drop function if exists widget_create_ticket(text, text, text, text);

drop function if exists widget_update_visitor_info(uuid, text, text, text, text, jsonb);
drop function if exists widget_update_visitor_info(uuid, text, text, text, text);

drop function if exists widget_escalate_to_team(text, text, text, jsonb);
drop function if exists widget_escalate_to_team(text, text, text);

-- 1. Create primary widget_create_ticket function with p_history
create or replace function widget_create_ticket(
  p_site_key text,
  p_name text,
  p_email text,
  p_message text,
  p_phone text default null,
  p_history jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
  item jsonb;
  item_sender text;
  item_body text;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;

  p_name := trim(coalesce(p_name, ''));
  p_email := lower(trim(coalesce(p_email, '')));
  p_phone := trim(coalesce(p_phone, ''));
  p_message := trim(coalesce(p_message, ''));

  if char_length(p_name) not between 1 and 80 then raise exception 'Please enter your name'; end if;
  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(p_email) > 160 then raise exception 'Please enter a valid email'; end if;
  if char_length(p_message) not between 1 and 4000 then raise exception 'Please enter a message'; end if;

  if (select count(*) from tickets where site_id = s.id and visitor_email = p_email and created_at > now() - interval '1 hour') >= 15 then
    raise exception 'Too many requests, please try again later';
  end if;

  insert into tickets(site_id, visitor_name, visitor_email, visitor_phone, subject, status, form_submitted, unread_by_staff)
    values (s.id, p_name, p_email, nullif(p_phone, ''), left(p_message, 100), 'open', true, true)
    returning * into t;

  -- Insert previous conversation history with bot in chronological order
  if p_history is not null and jsonb_typeof(p_history) = 'array' and jsonb_array_length(p_history) > 0 then
    for item in select * from jsonb_array_elements(p_history)
    loop
      item_sender := lower(trim(coalesce(item->>'sender', item->>'from', '')));
      item_body := trim(coalesce(item->>'body', item->>'text', ''));
      if item_sender = 'me' then item_sender := 'visitor'; end if;
      if item_sender in ('visitor', 'bot') and char_length(item_body) between 1 and 4000 then
        if not exists (
          select 1 from ticket_messages
          where ticket_id = t.id and sender = item_sender::msg_sender and body = item_body
        ) then
          insert into ticket_messages(ticket_id, sender, body, created_at)
          values (t.id, item_sender::msg_sender, item_body, clock_timestamp());
        end if;
      end if;
    end loop;
  end if;

  -- Insert current visitor message if not already present in history
  if char_length(p_message) > 0 and not exists (
    select 1 from ticket_messages
    where ticket_id = t.id and sender = 'visitor' and body = p_message
  ) then
    insert into ticket_messages(ticket_id, sender, body, created_at)
    values (t.id, 'visitor', p_message, clock_timestamp());
  end if;

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

-- Overload for 4-argument compatibility
create or replace function widget_create_ticket(
  p_site_key text,
  p_name text,
  p_email text,
  p_message text
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return widget_create_ticket(p_site_key, p_name, p_email, p_message, null, '[]'::jsonb);
end $$;

grant execute on function widget_create_ticket(text, text, text, text, text, jsonb) to anon, authenticated;
grant execute on function widget_create_ticket(text, text, text, text) to anon, authenticated;

-- 2. Create primary widget_update_visitor_info function with p_history
create or replace function widget_update_visitor_info(
  p_token uuid,
  p_name text default null,
  p_email text default null,
  p_phone text default null,
  p_message text default null,
  p_history jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t tickets;
  clean_msg text;
  item jsonb;
  item_sender text;
  item_body text;
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
    unread_by_staff = true,
    updated_at = now()
  where id = t.id;

  -- Insert previous conversation history with bot if not already present
  if p_history is not null and jsonb_typeof(p_history) = 'array' and jsonb_array_length(p_history) > 0 then
    for item in select * from jsonb_array_elements(p_history)
    loop
      item_sender := lower(trim(coalesce(item->>'sender', item->>'from', '')));
      item_body := trim(coalesce(item->>'body', item->>'text', ''));
      if item_sender = 'me' then item_sender := 'visitor'; end if;
      if item_sender in ('visitor', 'bot') and char_length(item_body) between 1 and 4000 then
        if not exists (
          select 1 from ticket_messages
          where ticket_id = t.id and sender = item_sender::msg_sender and body = item_body
        ) then
          insert into ticket_messages(ticket_id, sender, body, created_at)
          values (t.id, item_sender::msg_sender, item_body, clock_timestamp());
        end if;
      end if;
    end loop;
  end if;

  -- Insert message if not empty and not duplicate
  if char_length(clean_msg) > 0 and not exists (
    select 1 from ticket_messages
    where ticket_id = t.id and sender = 'visitor' and body = clean_msg
  ) then
    insert into ticket_messages(ticket_id, sender, body, created_at)
    values (t.id, 'visitor', clean_msg, clock_timestamp());
  end if;

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

grant execute on function widget_update_visitor_info(uuid, text, text, text, text, jsonb) to anon, authenticated;

-- 3. Create primary widget_escalate_to_team function with p_history
create or replace function widget_escalate_to_team(
  p_site_key text,
  p_token text default null,
  p_reason text default null,
  p_history jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
  clean_r text := trim(coalesce(p_reason, 'Passenger requested live assistance'));
  item jsonb;
  item_sender text;
  item_body text;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;

  if p_token is not null and p_token ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into t from tickets where visitor_token = p_token::uuid;
  end if;

  if t.id is null then
    insert into tickets(site_id, visitor_name, visitor_email, subject, status, form_submitted, unread_by_staff)
      values (s.id, 'Passenger #' || substring(gen_random_uuid()::text, 1, 4), null, left(clean_r, 80), 'open', false, true)
      returning * into t;
  else
    update tickets set status = 'open', updated_at = now(), unread_by_staff = true where id = t.id;
  end if;

  -- Insert previous conversation history with bot
  if p_history is not null and jsonb_typeof(p_history) = 'array' and jsonb_array_length(p_history) > 0 then
    for item in select * from jsonb_array_elements(p_history)
    loop
      item_sender := lower(trim(coalesce(item->>'sender', item->>'from', '')));
      item_body := trim(coalesce(item->>'body', item->>'text', ''));
      if item_sender = 'me' then item_sender := 'visitor'; end if;
      if item_sender in ('visitor', 'bot') and char_length(item_body) between 1 and 4000 then
        if not exists (
          select 1 from ticket_messages
          where ticket_id = t.id and sender = item_sender::msg_sender and body = item_body
        ) then
          insert into ticket_messages(ticket_id, sender, body, created_at)
          values (t.id, item_sender::msg_sender, item_body, clock_timestamp());
        end if;
      end if;
    end loop;
  end if;

  insert into ticket_messages(ticket_id, sender, body, is_internal, created_at)
    values (t.id, 'system', 'Visitor requested live agent: ' || clean_r, true, clock_timestamp());

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no, 'status', 'open');
end $$;

grant execute on function widget_escalate_to_team(text, text, text, jsonb) to anon, authenticated;
