-- UAA Support · 009 Fix widget_create_ticket schema cache & add visitor_phone support

-- 1. Ensure visitor_phone column exists on tickets table
alter table tickets add column if not exists visitor_phone text;

-- 2. Drop previous overloads to prevent PostgREST signature conflicts / cache ambiguity
drop function if exists widget_create_ticket(text, text, text, text);
drop function if exists widget_create_ticket(text, text, text, text, text);

-- 3. Create clean widget_create_ticket with phone number support
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

-- 4. RPC to update visitor info when form is submitted after bot chat
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

-- 5. Force PostgREST to reload its schema cache immediately
notify pgrst, 'reload schema';

