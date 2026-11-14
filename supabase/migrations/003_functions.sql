-- UAA Support · 003 RPCs (widget + staff), notifications

-- ---------- helpers ----------
create or replace function _origin_ok(p_allowed text[]) returns boolean
language plpgsql stable as $$
declare o text;
begin
  if p_allowed is null or coalesce(array_length(p_allowed,1),0) = 0 then return true; end if;
  begin o := (current_setting('request.headers', true)::json)->>'origin';
  exception when others then o := null; end;
  if o is null then return true; end if;           -- non-browser caller
  return o = any(p_allowed);
end $$;

create or replace function _norm(t text) returns text language sql immutable as $$
  select left(trim(regexp_replace(lower(coalesce(t,'')), '[^a-z0-9 ]+', ' ', 'g')), 200)
$$;

-- ---------- widget (anonymous) ----------
create or replace function widget_config(p_site_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s sites;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;
  return jsonb_build_object(
    'name', s.name, 'theme', s.theme, 'texts', s.texts, 'faq_url', s.faq_url,
    'rules', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'keywords', r.keywords, 'match_type', r.match_type, 'action', r.action,
        'response', r.response, 'link_url', r.link_url, 'button_label', r.button_label) order by r.priority, r.created_at)
      from bot_rules r where r.is_active and (r.site_id = s.id or r.site_id is null)), '[]'::jsonb));
end $$;

create or replace function widget_log_query(p_site_key text, p_query text, p_rule uuid, p_matched boolean)
returns void language plpgsql security definer set search_path = public as $$
declare sid uuid; q text := _norm(p_query);
begin
  select id into sid from sites where site_key = p_site_key and is_active;
  if sid is null or q = '' then return; end if;
  if p_rule is not null and not exists (select 1 from bot_rules where id = p_rule) then p_rule := null; end if;
  insert into bot_events(site_id, rule_id, query, matched) values (sid, p_rule, q, coalesce(p_matched,false));
end $$;

create or replace function widget_create_ticket(p_site_key text, p_name text, p_email text, p_message text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sites; t tickets;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;
  p_name := trim(coalesce(p_name,'')); p_email := lower(trim(coalesce(p_email,''))); p_message := trim(coalesce(p_message,''));
  if char_length(p_name) not between 1 and 80 then raise exception 'Please enter your name'; end if;
  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(p_email) > 160 then raise exception 'Please enter a valid email'; end if;
  if char_length(p_message) not between 1 and 4000 then raise exception 'Please enter a message'; end if;
  if (select count(*) from tickets where site_id = s.id and visitor_email = p_email and created_at > now() - interval '1 hour') >= 5
    then raise exception 'Too many requests, please try again later'; end if;
  insert into tickets(site_id, visitor_name, visitor_email, subject)
    values (s.id, p_name, p_email, left(p_message, 100)) returning * into t;
  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', p_message);
  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

create or replace function widget_send(p_token uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets; b text := trim(coalesce(p_body,''));
begin
  select * into t from tickets where visitor_token = p_token;
  if not found then raise exception 'unknown conversation'; end if;
  if t.status = 'closed' then raise exception 'closed'; end if;
  if char_length(b) not between 1 and 4000 then raise exception 'Message too long or empty'; end if;
  if (select count(*) from ticket_messages where ticket_id = t.id and sender = 'visitor' and created_at > now() - interval '1 minute') >= 10
    then raise exception 'Slow down a little'; end if;
  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', b);
  update tickets set updated_at = now(), unread_by_staff = true where id = t.id;
end $$;

create or replace function widget_messages(p_token uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t tickets;
begin
  select * into t from tickets where visitor_token = p_token;
  if not found then raise exception 'unknown conversation'; end if;
  return jsonb_build_object(
    'status', t.status, 'ticket_no', t.ticket_no,
    'agent', (select pseudo_name from profiles where id = t.claimed_by),   -- visitors only ever see the pseudo name
    'messages', coalesce((select jsonb_agg(jsonb_build_object('from', m.sender, 'text', m.body, 'at', m.created_at) order by m.created_at)
       from ticket_messages m where m.ticket_id = t.id and not m.is_internal), '[]'::jsonb));
end $$;

grant execute on function widget_config(text), widget_log_query(text,text,uuid,boolean),
  widget_create_ticket(text,text,text,text), widget_send(uuid,text), widget_messages(uuid) to anon, authenticated;

-- ---------- staff ----------
create or replace function _need(p text) returns void language plpgsql as $$
begin if not has_perm(p) then raise exception 'You do not have permission (%)', p using errcode = '42501'; end if; end $$;

create or replace function claim_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me profiles; n int;
begin
  perform _need('tickets.claim');
  select * into me from profiles where id = auth.uid();
  update tickets set claimed_by = auth.uid(), claimed_at = now(), status = 'claimed', updated_at = now()
   where id = p_ticket and claimed_by is null and status <> 'closed';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Ticket is already claimed or closed'; end if;
  insert into ticket_messages(ticket_id, sender, author_id, body) values (p_ticket, 'system', auth.uid(), me.pseudo_name || ' joined the conversation');
end $$;

create or replace function release_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets; me profiles;
begin
  perform _need('tickets.claim');
  select * into t from tickets where id = p_ticket;
  if not found or t.status = 'closed' then raise exception 'Ticket not available'; end if;
  if t.claimed_by is distinct from auth.uid() and not has_perm('tickets.reassign') then raise exception 'Only the owner or a lead can release this ticket'; end if;
  select * into me from profiles where id = auth.uid();
  update tickets set claimed_by = null, claimed_at = null, status = 'open', updated_at = now() where id = p_ticket;
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal) values (p_ticket, 'system', auth.uid(), me.pseudo_name || ' released the ticket', true);
end $$;

create or replace function assign_ticket(p_ticket uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare tgt profiles; me profiles;
begin
  perform _need('tickets.reassign');
  select * into tgt from profiles where id = p_user and is_active;
  if not found then raise exception 'User not found'; end if;
  select * into me from profiles where id = auth.uid();
  update tickets set claimed_by = p_user, claimed_at = now(), status = 'claimed', updated_at = now() where id = p_ticket and status <> 'closed';
  if not found then raise exception 'Ticket not available'; end if;
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal)
    values (p_ticket, 'system', auth.uid(), me.pseudo_name || ' assigned the ticket to ' || tgt.pseudo_name, true);
  insert into ticket_messages(ticket_id, sender, author_id, body) values (p_ticket, 'system', p_user, tgt.pseudo_name || ' joined the conversation');
end $$;

create or replace function staff_reply(p_ticket uuid, p_body text, p_internal boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets; b text := trim(coalesce(p_body,''));
begin
  perform _need('tickets.reply');
  if char_length(b) not between 1 and 4000 then raise exception 'Message is empty or too long'; end if;
  select * into t from tickets where id = p_ticket;
  if not found then raise exception 'Ticket not found'; end if;
  if not (has_perm('tickets.view_all') or has_perm('tickets.view_recent')) then raise exception 'forbidden' using errcode='42501'; end if;
  if t.status = 'closed' then raise exception 'Ticket is closed. Reopen it first'; end if;
  if not p_internal and t.claimed_by is distinct from auth.uid() and not has_perm('tickets.reassign') then
    raise exception 'Claim this ticket before replying'; end if;
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal) values (p_ticket, 'staff', auth.uid(), b, coalesce(p_internal,false));
  update tickets set updated_at = now(),
    unread_by_staff = case when p_internal then unread_by_staff else false end,
    first_response_at = case when p_internal then first_response_at else coalesce(first_response_at, now()) end
   where id = p_ticket;
end $$;

create or replace function close_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets;
begin
  perform _need('tickets.close');
  select * into t from tickets where id = p_ticket;
  if not found then raise exception 'Ticket not found'; end if;
  if t.claimed_by is distinct from auth.uid() and not has_perm('tickets.reassign') then raise exception 'Only the owner or a lead can close this ticket'; end if;
  update tickets set status = 'closed', closed_at = now(), closed_by = auth.uid(), updated_at = now() where id = p_ticket;
  insert into ticket_messages(ticket_id, sender, author_id, body) values (p_ticket, 'system', auth.uid(), 'This conversation was closed');
end $$;

create or replace function reopen_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets;
begin
  perform _need('tickets.reply');
  select * into t from tickets where id = p_ticket and status = 'closed';
  if not found then raise exception 'Ticket is not closed'; end if;
  if not (has_perm('tickets.view_all') or t.closed_at > now() - interval '10 days') then raise exception 'forbidden' using errcode='42501'; end if;
  update tickets set status = 'open', claimed_by = null, claimed_at = null, closed_at = null, closed_by = null, updated_at = now() where id = p_ticket;
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal) values (p_ticket, 'system', auth.uid(), 'Ticket reopened', true);
end $$;

create or replace function clone_rules(p_from uuid, p_to uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform _need('rules.manage');
  insert into bot_rules(site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active, created_by)
    select p_to, name, keywords, match_type, action, response, link_url, button_label, priority, is_active, auth.uid()
    from bot_rules where site_id is not distinct from p_from;
  get diagnostics n = row_count; return n;
end $$;

create or replace function dashboard_stats(p_days int default 30, p_site uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare since timestamptz := now() - make_interval(days => greatest(coalesce(p_days,30),1)); result jsonb;
begin
  perform _need('dashboard.view');
  select jsonb_build_object(
    'open',    (select count(*) from tickets where status='open'    and (p_site is null or site_id=p_site)),
    'claimed', (select count(*) from tickets where status='claimed' and (p_site is null or site_id=p_site)),
    'closed',  (select count(*) from tickets where status='closed' and closed_at>=since and (p_site is null or site_id=p_site)),
    'created', (select count(*) from tickets where created_at>=since and (p_site is null or site_id=p_site)),
    'avg_first_response_min', (select round(avg(extract(epoch from first_response_at-created_at))/60) from tickets
        where first_response_at is not null and created_at>=since and (p_site is null or site_id=p_site)),
    'top_rules', (select coalesce(jsonb_agg(x),'[]') from (select br.name, count(*) hits from bot_events e join bot_rules br on br.id=e.rule_id
        where e.created_at>=since and (p_site is null or e.site_id=p_site) group by br.name order by hits desc limit 10) x),
    'unmatched', (select coalesce(jsonb_agg(x),'[]') from (select query, count(*) hits from bot_events
        where not matched and created_at>=since and (p_site is null or site_id=p_site) group by query order by hits desc limit 10) x),
    'by_site', (select coalesce(jsonb_agg(x),'[]') from (select s.name, count(t.id) tickets from sites s
        left join tickets t on t.site_id=s.id and t.created_at>=since group by s.name order by tickets desc) x),
    'per_day', (select coalesce(jsonb_agg(x),'[]') from (select created_at::date d, count(*) n from tickets
        where created_at>=since and (p_site is null or site_id=p_site) group by 1 order by 1) x)
  ) into result;
  return result;
end $$;

-- ---------- new user + notifications ----------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, real_name, pseudo_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
          'staff-' || substr(replace(new.id::text,'-',''),1,8),
          (case when exists (select 1 from profiles) then 'employee' else 'admin' end)::app_role);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create or replace function notify_new_ticket() returns trigger
language plpgsql security definer set search_path = public as $$
declare w text; d text; sname text; msg text;
begin
  select webhook_url, dashboard_url into w, d from site_secrets where site_id = new.site_id;
  if coalesce(w,'') = '' then return new; end if;
  select name into sname from sites where id = new.site_id;
  msg := format('New ticket UAA-%s on %s from %s: %s%s', new.ticket_no, sname, new.visitor_name, left(new.subject,120),
                case when coalesce(d,'') <> '' then E'\n' || d || '/tickets' else '' end);
  begin
    perform net.http_post(url := w, body := jsonb_build_object('text', msg, 'content', msg), headers := '{"Content-Type":"application/json"}'::jsonb);
  exception when others then null; end;   -- never block a visitor because a webhook failed
  return new;
end $$;
create trigger tickets_notify after insert on tickets for each row execute function notify_new_ticket();
