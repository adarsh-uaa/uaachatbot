-- ============================================================================
-- UAA Support Platform · Complete Unified Database Schema & Migrations
-- Single Consolidated Script for Fresh Supabase Database Setup
-- Compatible with PostgreSQL 15+ & Supabase
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EXTENSIONS
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;
create extension if not exists pg_net;

-- ----------------------------------------------------------------------------
-- 2. CUSTOM TYPES / ENUMS
-- ----------------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type app_role as enum ('admin', 'manager', 'teamlead', 'employee');
  end if;
  if not exists (select 1 from pg_type where typname = 'ticket_status') then
    create type ticket_status as enum ('bot', 'open', 'claimed', 'closed');
  end if;
  if not exists (select 1 from pg_type where typname = 'msg_sender') then
    create type msg_sender as enum ('visitor', 'staff', 'bot', 'system');
  end if;
  if not exists (select 1 from pg_type where typname = 'rule_action') then
    create type rule_action as enum ('reply', 'faq_link', 'handoff');
  end if;
  if not exists (select 1 from pg_type where typname = 'rule_match') then
    create type rule_match as enum ('contains', 'exact');
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 3. CORE TABLES
-- ----------------------------------------------------------------------------

-- Teams
create table if not exists teams (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  color text not null default '#0f7c86',
  lead_id uuid, -- foreign key added after profiles table creation
  created_at timestamptz not null default now()
);

-- Staff Profiles (real_name is private; pseudo_name is public to visitors)
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  real_name text not null,
  pseudo_name text not null unique,
  role app_role not null default 'employee',
  team_id uuid references teams(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Link teams.lead_id to profiles
do $$ begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'teams_lead_id_fkey'
  ) then
    alter table teams add constraint teams_lead_id_fkey
      foreign key (lead_id) references profiles(id) on delete set null;
  end if;
end $$;

-- Granular Permissions Definitions
create table if not exists permissions (
  key text primary key,
  description text not null
);

-- Role Default Permissions
create table if not exists role_permissions (
  role app_role not null,
  permission text not null references permissions(key) on delete cascade,
  primary key (role, permission)
);

-- Per-User Permission Overrides (granted=true grants, granted=false revokes)
create table if not exists user_permissions (
  user_id uuid not null references profiles(id) on delete cascade,
  permission text not null references permissions(key) on delete cascade,
  granted boolean not null,
  primary key (user_id, permission)
);

-- Sites (each website / airport property where widget is embedded)
create table if not exists sites (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  site_key text not null unique default replace(gen_random_uuid()::text, '-', ''),
  allowed_origins text[] not null default '{}',
  faq_url text,
  theme jsonb not null default '{"primary":"#12202e","accent":"#f2a900","text":"#12202e","radius":14,"position":"right","icon":"chat","iconUrl":"","escalation_alarm_enabled":true,"bot_chat_enabled":false}',
  texts jsonb not null default '{"title":"Assistance desk","subtitle":"We usually reply within a few minutes","greeting":"Hello! How can we help with your airport assistance?","placeholder":"Type your question…","fallback":"I could not find an automated answer for that. Please connect with our assistance team below:","handoff":"Talk to our team","ticketCreated":"Thanks! Your request is with our team.","closed":"This conversation is closed."}',
  bot_chat_enabled boolean not null default false,
  escalation_alarm_enabled boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Site Secrets (kept isolated for security)
create table if not exists site_secrets (
  site_id uuid primary key references sites(id) on delete cascade,
  webhook_url text,
  dashboard_url text
);

-- Bot Rules & Quick Reply Buttons
create table if not exists bot_rules (
  id uuid primary key default gen_random_uuid(),
  site_id uuid references sites(id) on delete cascade, -- null = global rule for all sites
  name text not null,
  keywords text[] not null,
  match_type rule_match not null default 'contains',
  action rule_action not null default 'reply',
  response text not null,
  link_url text,
  button_label text, -- when present, displayed as a quick reply suggestion chip
  priority int not null default 100,
  is_active boolean not null default true,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Canned / Saved Replies
create table if not exists canned_replies (
  id uuid primary key default gen_random_uuid(),
  site_id uuid references sites(id) on delete cascade,
  title text not null,
  body text not null,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Support Tickets
create table if not exists tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_no bigint generated always as identity,
  site_id uuid not null references sites(id) on delete cascade,
  visitor_name text not null default 'Visitor',
  visitor_email text,
  visitor_phone text,
  form_submitted boolean not null default false,
  visitor_token uuid not null unique default gen_random_uuid(),
  subject text not null,
  status ticket_status not null default 'open',
  claimed_by uuid references profiles(id) on delete set null,
  claimed_at timestamptz,
  closed_at timestamptz,
  closed_by uuid references profiles(id) on delete set null,
  first_response_at timestamptz,
  unread_by_staff boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Conversation Messages
create table if not exists ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references tickets(id) on delete cascade,
  sender msg_sender not null,
  author_id uuid references profiles(id) on delete set null,
  body text not null check (char_length(body) between 1 and 4000),
  is_internal boolean not null default false,
  created_at timestamptz not null default now()
);

-- Bot Search Analytics & Unanswered Queries
create table if not exists bot_events (
  id bigint generated always as identity primary key,
  site_id uuid references sites(id) on delete cascade,
  rule_id uuid references bot_rules(id) on delete set null,
  query text not null,
  matched boolean not null,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 4. PERFORMANCE INDEXES
-- ----------------------------------------------------------------------------
create index if not exists idx_tickets_status_updated on tickets(status, updated_at desc);
create index if not exists idx_tickets_claimed_by on tickets(claimed_by);
create index if not exists idx_tickets_site_created on tickets(site_id, created_at desc);
create index if not exists idx_tickets_unread_staff on tickets(status, unread_by_staff) where unread_by_staff = true;
create index if not exists idx_tickets_visitor_token on tickets(visitor_token);
create index if not exists idx_ticket_messages_ticket_created on ticket_messages(ticket_id, created_at asc);
create index if not exists idx_ticket_messages_sender on ticket_messages(ticket_id, sender);
create index if not exists idx_bot_rules_lookup on bot_rules(site_id, is_active, priority asc);
create index if not exists idx_bot_events_site_date on bot_events(site_id, created_at desc);
create index if not exists idx_user_perms_lookup on user_permissions(user_id, permission);
create index if not exists idx_role_perms_lookup on role_permissions(role, permission);
create index if not exists idx_sites_site_key on sites(site_key) where is_active = true;

-- ----------------------------------------------------------------------------
-- 5. HELPER FUNCTIONS & VIEWS
-- ----------------------------------------------------------------------------

-- Check if authenticated user is an active staff member
create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and is_active);
$$;

-- Check granular permission: user override wins, fallback to role permissions
create or replace function has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select is_staff() and coalesce(
    (select granted from user_permissions where user_id = auth.uid() and permission = p),
    exists (
      select 1 from profiles pr
      join role_permissions rp on rp.role = pr.role
      where pr.id = auth.uid() and rp.permission = p
    )
  );
$$;

-- Enforce permission check or throw 42501 error
create or replace function can_view_real() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles pr
    where pr.id = auth.uid()
      and (
        pr.role in ('admin', 'manager', 'teamlead')
        or exists (
          select 1 from role_permissions rp
          where rp.role = pr.role and rp.permission in ('users.view_real', 'users.manage')
        )
        or exists (
          select 1 from user_permissions up
          where up.user_id = pr.id and up.permission in ('users.view_real', 'users.manage') and up.granted = true
        )
      )
  );
$$;

-- Check if user can delete tickets/chats (Admin and Manager only)
create or replace function can_delete_tickets() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles pr
    where pr.id = auth.uid()
      and pr.is_active = true
      and pr.role in ('admin', 'manager')
  );
$$;

create or replace function _need(p text) returns void
language plpgsql as $$
begin
  if not has_perm(p) then
    raise exception 'You do not have permission (%)', p using errcode = '42501';
  end if;
end $$;

-- Get array of active permissions for the calling user
create or replace function my_permissions() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(key), '{}') from permissions where has_perm(key);
$$;

-- Normalize text for search / keyword matching
create or replace function _norm(t text) returns text
language sql immutable as $$
  select ' ' || left(trim(regexp_replace(lower(coalesce(t, '')), '[^a-z0-9 ]+', ' ', 'g')), 200) || ' ';
$$;

-- Robust Origin Checker for Web, Mobile Safari, WebViews, and LAN testing
create or replace function _origin_ok(p_allowed text[]) returns boolean
language plpgsql stable as $$
declare
  headers json;
  raw_origin text;
  raw_referer text;
  req_origin text;
  clean_req text;
  req_host text;
  entry text;
  clean_entry text;
  entry_host text;
begin
  -- 1. If allowed_origins is null, empty, or contains '*', allow all
  if p_allowed is null or coalesce(array_length(p_allowed, 1), 0) = 0 then
    return true;
  end if;
  if '*' = any(p_allowed) or '' = any(p_allowed) then
    return true;
  end if;

  -- 2. Extract request headers safely
  begin
    headers := current_setting('request.headers', true)::json;
  exception when others then
    headers := null;
  end;
  if headers is null then
    return true;
  end if;

  raw_origin := headers->>'origin';
  raw_referer := headers->>'referer';

  -- Mobile Safari & WebViews send 'null' or omit origin; fallback to referer
  if raw_origin is not null and lower(trim(raw_origin)) <> 'null' and trim(raw_origin) <> '' then
    req_origin := lower(trim(raw_origin));
  elsif raw_referer is not null and trim(raw_referer) <> '' and lower(trim(raw_referer)) <> 'null' then
    req_origin := lower(trim(substring(raw_referer from '^(https?://[^/?#]+)')));
  end if;

  if req_origin is null or req_origin = '' or req_origin = 'null' then
    return true;
  end if;

  -- Mobile hybrid app schemes (Capacitor, Ionic, Cordova, local files)
  if req_origin like 'capacitor://%' or req_origin like 'ionic://%' or req_origin like 'file://%' then
    return true;
  end if;

  req_origin := regexp_replace(req_origin, '/+$', '');
  clean_req := regexp_replace(req_origin, '^https?://', '');
  req_host := split_part(clean_req, ':', 1);

  -- Local Wi-Fi testing (192.168.x.x, 10.x.x.x, localhost)
  if (req_host in ('localhost', '127.0.0.1')
      or req_host ~ '^192\.168\.\d+\.\d+$'
      or req_host ~ '^10\.\d+\.\d+\.\d+$'
      or req_host ~ '^172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+$')
     and ('localhost' = any(p_allowed) or 'http://localhost' = any(p_allowed) or '127.0.0.1' = any(p_allowed) or exists (
       select 1 from unnest(p_allowed) pe where pe like '%localhost%' or pe like '%127.0.0.1%' or pe like '%192.168%' or pe like '%10.%'
     )) then
    return true;
  end if;

  -- 3. Match against allowed entries
  foreach entry in array p_allowed loop
    entry := lower(trim(entry));
    if entry = '' or entry = '*' then
      return true;
    end if;

    entry := regexp_replace(entry, '/+$', '');
    if req_origin = entry then return true; end if;

    clean_entry := regexp_replace(entry, '^https?://', '');
    entry_host := split_part(clean_entry, ':', 1);

    if clean_req = clean_entry then return true; end if;
    if req_host = entry_host and entry_host <> '' then return true; end if;

    -- Subdomain & www matching
    if (req_host = 'www.' || entry_host) or (entry_host = 'www.' || req_host) then return true; end if;
    if (req_host = 'm.' || entry_host) or (req_host = 'mobile.' || entry_host) or (req_host = 'app.' || entry_host) then return true; end if;

    -- Wildcards
    if entry_host like '*.%' then
      if req_host = substring(entry_host from 3) or req_host like '%.' || substring(entry_host from 3) then return true; end if;
    elsif entry_host like '.%' then
      if req_host = substring(entry_host from 2) or req_host like '%.' || substring(entry_host from 2) then return true; end if;
    end if;

    if entry like '%*%' then
      if clean_req like replace(clean_entry, '*', '%') or req_origin like replace(entry, '*', '%') then return true; end if;
    end if;
  end loop;

  return false;
end $$;

-- Public staff view (exposes only pseudo_name for privacy)
create or replace view staff_public with (security_invoker = false) as
  select id, pseudo_name, role, is_active, team_id, created_at from profiles;

-- ----------------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
alter table profiles enable row level security;
alter table teams enable row level security;
alter table permissions enable row level security;
alter table role_permissions enable row level security;
alter table user_permissions enable row level security;
alter table sites enable row level security;
alter table site_secrets enable row level security;
alter table bot_rules enable row level security;
alter table canned_replies enable row level security;
alter table tickets enable row level security;
alter table ticket_messages enable row level security;
alter table bot_events enable row level security;

-- Profiles: real names visible to self, users with users.view_real / users.manage, or roles admin, manager, teamlead
create policy profiles_read on profiles for select to authenticated
  using (
    id = auth.uid()
    or can_view_real()
  );
create policy profiles_write on profiles for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));

-- Teams
create policy teams_read on teams for select to authenticated using (is_staff());
create policy teams_write on teams for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));

-- Permissions & Overrides
create policy perms_read on permissions for select to authenticated using (is_staff());
create policy roleperm_read on role_permissions for select to authenticated using (is_staff());
create policy roleperm_write on role_permissions for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));
create policy userperm_read on user_permissions for select to authenticated
  using (user_id = auth.uid() or has_perm('users.manage'));
create policy userperm_write on user_permissions for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));

-- Sites & Secrets
create policy sites_read on sites for select to authenticated using (is_staff());
create policy sites_write on sites for all to authenticated
  using (has_perm('sites.manage')) with check (has_perm('sites.manage'));
create policy secrets_all on site_secrets for all to authenticated
  using (has_perm('sites.manage')) with check (has_perm('sites.manage'));

-- Bot Rules & Canned Replies
create policy rules_read on bot_rules for select to authenticated using (is_staff());
create policy rules_write on bot_rules for all to authenticated
  using (has_perm('rules.manage')) with check (has_perm('rules.manage'));
create policy canned_read on canned_replies for select to authenticated using (is_staff());
create policy canned_write on canned_replies for all to authenticated
  using (has_perm('canned.manage')) with check (has_perm('canned.manage'));

-- Tickets: all active staff can view tickets and receive Realtime broadcast events
create policy tickets_read on tickets for select to authenticated using (is_staff());
create policy tickets_update on tickets for update to authenticated using (is_staff()) with check (is_staff());
create policy tickets_delete on tickets for delete to authenticated
  using (can_delete_tickets());

-- Messages: all active staff can view messages and receive Realtime message events
create policy messages_read on ticket_messages for select to authenticated using (is_staff());
create policy events_read on bot_events for select to authenticated using (has_perm('dashboard.view'));

-- Replica Identity FULL for complete Realtime change payloads on all staff connections
alter table tickets replica identity full;
alter table ticket_messages replica identity full;

-- ----------------------------------------------------------------------------
-- 7. ANONYMOUS WIDGET APIS (RPCs)
-- ----------------------------------------------------------------------------

-- 1. Widget Configuration
create or replace function widget_config(p_site_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s sites;
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

-- 2. Widget Create Ticket
create or replace function widget_create_ticket(
  p_site_key text,
  p_name text,
  p_email text,
  p_message text,
  p_phone text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
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

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', p_message);

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no);
end $$;

-- Compatibility 4-argument overload for cached PostgREST signatures
create or replace function widget_create_ticket(
  p_site_key text,
  p_name text,
  p_email text,
  p_message text
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return widget_create_ticket(p_site_key, p_name, p_email, p_message, null);
end $$;

-- 3. Widget Update Visitor Info
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
    unread_by_staff = true,
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

-- 4. Widget Escalate to Team (rings alarm immediately)
create or replace function widget_escalate_to_team(
  p_site_key text,
  p_token text default null,
  p_reason text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s sites;
  t tickets;
  clean_r text := trim(coalesce(p_reason, 'Passenger requested live assistance'));
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  if not _origin_ok(s.allowed_origins) then raise exception 'origin not allowed'; end if;

  if p_token is not null then
    select * into t from tickets where visitor_token = p_token::uuid;
  end if;

  if t.id is null then
    insert into tickets(site_id, visitor_name, visitor_email, subject, status, form_submitted)
      values (s.id, 'Passenger #' || substring(gen_random_uuid()::text, 1, 4), null, left(clean_r, 80), 'open', false)
      returning * into t;
  else
    update tickets set status = 'open', updated_at = now(), unread_by_staff = true where id = t.id;
  end if;

  insert into ticket_messages(ticket_id, sender, body, is_internal)
    values (t.id, 'system', 'Visitor requested live agent: ' || clean_r, true);

  return jsonb_build_object('token', t.visitor_token, 'ticket_no', t.ticket_no, 'status', 'open');
end $$;

-- 5. Widget Bot Chat (Matches keywords, button labels, and rule names)
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
    if matched_rule.action = 'handoff' then
      is_handoff := true;
      final_status := 'open';
    elsif matched_rule.action = 'faq_link' then
      link_url := coalesce(matched_rule.link_url, s.faq_url);
    elsif matched_rule.link_url is not null then
      link_url := matched_rule.link_url;
    end if;
  else
    bot_resp := coalesce(s.texts->>'fallback', 'I could not find an automated answer for that. Please connect with our assistance team below:');
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

-- 6. Widget Send Message
create or replace function widget_send(p_token uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets; b text := trim(coalesce(p_body, ''));
begin
  select * into t from tickets where visitor_token = p_token;
  if not found then raise exception 'unknown conversation'; end if;
  if t.status = 'closed' then raise exception 'closed'; end if;
  if char_length(b) not between 1 and 4000 then raise exception 'Message too long or empty'; end if;

  if (select count(*) from ticket_messages where ticket_id = t.id and sender = 'visitor' and created_at > now() - interval '1 minute') >= 15 then
    raise exception 'Slow down a little';
  end if;

  insert into ticket_messages(ticket_id, sender, body) values (t.id, 'visitor', b);
  update tickets set updated_at = now(), unread_by_staff = true where id = t.id;
end $$;

-- 7. Widget Fetch Messages
create or replace function widget_messages(p_token uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t tickets;
begin
  select * into t from tickets where visitor_token = p_token;
  if not found then raise exception 'unknown conversation'; end if;

  return jsonb_build_object(
    'status', t.status,
    'ticket_no', t.ticket_no,
    'agent', (select pseudo_name from profiles where id = t.claimed_by),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object('from', m.sender, 'text', m.body, 'at', m.created_at) order by m.created_at)
      from ticket_messages m where m.ticket_id = t.id and not m.is_internal
    ), '[]'::jsonb)
  );
end $$;

-- 8. Widget Log Unanswered / Search Query
create or replace function widget_log_query(p_site_key text, p_query text, p_rule uuid, p_matched boolean)
returns void language plpgsql security definer set search_path = public as $$
declare sid uuid; q text := _norm(p_query);
begin
  select id into sid from sites where site_key = p_site_key and is_active;
  if sid is null or q = '' then return; end if;
  if p_rule is not null and not exists (select 1 from bot_rules where id = p_rule) then p_rule := null; end if;
  insert into bot_events(site_id, rule_id, query, matched) values (sid, p_rule, q, coalesce(p_matched, false));
end $$;

-- Grant execution to anon and authenticated
grant usage on schema public to anon, authenticated;
grant execute on function widget_config(text) to anon, authenticated;
grant execute on function widget_create_ticket(text, text, text, text, text) to anon, authenticated;
grant execute on function widget_create_ticket(text, text, text, text) to anon, authenticated;
grant execute on function widget_update_visitor_info(uuid, text, text, text, text) to anon, authenticated;
grant execute on function widget_escalate_to_team(text, text, text) to anon, authenticated;
grant execute on function widget_bot_chat(text, text, text) to anon, authenticated;
grant execute on function widget_send(uuid, text) to anon, authenticated;
grant execute on function widget_messages(uuid) to anon, authenticated;
grant execute on function widget_log_query(text, text, uuid, boolean) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 8. STAFF & ADMIN APIS (RPCs)
-- ----------------------------------------------------------------------------

-- Claim ticket
create or replace function claim_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me profiles; n int;
begin
  perform _need('tickets.claim');
  select * into me from profiles where id = auth.uid();
  update tickets 
     set claimed_by = auth.uid(), 
         claimed_at = now(), 
         status = 'claimed', 
         unread_by_staff = false, 
         first_response_at = coalesce(first_response_at, now()),
         updated_at = now()
   where id = p_ticket and claimed_by is null and status <> 'closed';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Ticket is already claimed or closed'; end if;
  insert into ticket_messages(ticket_id, sender, author_id, body)
    values (p_ticket, 'system', auth.uid(), me.pseudo_name || ' joined the conversation');
end $$;

-- Mark ticket read
create or replace function mark_ticket_read(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'forbidden' using errcode = '42501'; end if;
  update tickets set unread_by_staff = false, updated_at = now()
   where id = p_ticket and unread_by_staff = true;
end $$;

-- Release ticket
create or replace function release_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets; me profiles;
begin
  perform _need('tickets.claim');
  select * into t from tickets where id = p_ticket;
  if not found or t.status = 'closed' then raise exception 'Ticket not available'; end if;
  if t.claimed_by is distinct from auth.uid() and not has_perm('tickets.reassign') then
    raise exception 'Only the owner or a lead can release this ticket';
  end if;
  select * into me from profiles where id = auth.uid();
  update tickets set claimed_by = null, claimed_at = null, status = 'open', updated_at = now() where id = p_ticket;
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal)
    values (p_ticket, 'system', auth.uid(), me.pseudo_name || ' released the ticket', true);
end $$;

-- Assign ticket
create or replace function assign_ticket(p_ticket uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare tgt profiles; me profiles;
begin
  perform _need('tickets.reassign');
  select * into tgt from profiles where id = p_user and is_active;
  if not found then raise exception 'User not found'; end if;
  select * into me from profiles where id = auth.uid();
  update tickets set claimed_by = p_user, claimed_at = now(), status = 'claimed', updated_at = now()
    where id = p_ticket and status <> 'closed';
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal)
    values (p_ticket, 'system', auth.uid(), me.pseudo_name || ' assigned the ticket to ' || tgt.pseudo_name, true);
  insert into ticket_messages(ticket_id, sender, author_id, body)
    values (p_ticket, 'system', p_user, tgt.pseudo_name || ' joined the conversation');
end $$;

-- Staff reply
create or replace function staff_reply(p_ticket uuid, p_body text, p_internal boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets; b text := trim(coalesce(p_body, ''));
begin
  perform _need('tickets.reply');
  if char_length(b) not between 1 and 4000 then raise exception 'Message is empty or too long'; end if;
  select * into t from tickets where id = p_ticket;
  if not found then raise exception 'Ticket not found'; end if;
  if not (has_perm('tickets.view_all') or has_perm('tickets.view_recent')) then raise exception 'forbidden' using errcode='42501'; end if;
  if t.status = 'closed' then raise exception 'Ticket is closed. Reopen it first'; end if;
  if not p_internal and t.claimed_by is distinct from auth.uid() and not has_perm('tickets.reassign') then
    raise exception 'Claim this ticket before replying';
  end if;
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal)
    values (p_ticket, 'staff', auth.uid(), b, coalesce(p_internal, false));
  update tickets set updated_at = now(),
    unread_by_staff = case when p_internal then unread_by_staff else false end,
    first_response_at = case when p_internal then first_response_at else coalesce(first_response_at, now()) end
   where id = p_ticket;
end $$;

-- Close ticket
create or replace function close_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets;
begin
  perform _need('tickets.close');
  select * into t from tickets where id = p_ticket;
  if not found then raise exception 'Ticket not found'; end if;
  if t.claimed_by is distinct from auth.uid() and not has_perm('tickets.reassign') then
    raise exception 'Only the owner or a lead can close this ticket';
  end if;
  update tickets set status = 'closed', closed_at = now(), closed_by = auth.uid(), updated_at = now() where id = p_ticket;
  insert into ticket_messages(ticket_id, sender, author_id, body)
    values (p_ticket, 'system', auth.uid(), 'This conversation was closed');
end $$;

-- Reopen ticket
create or replace function reopen_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t tickets;
begin
  perform _need('tickets.reply');
  select * into t from tickets where id = p_ticket and status = 'closed';
  if not found then raise exception 'Ticket is not closed'; end if;
  if not (has_perm('tickets.view_all') or t.closed_at > now() - interval '10 days') then raise exception 'forbidden' using errcode='42501'; end if;
  update tickets set status = 'open', claimed_by = null, claimed_at = null, closed_at = null, closed_by = null, updated_at = now() where id = p_ticket;
  insert into ticket_messages(ticket_id, sender, author_id, body, is_internal)
    values (p_ticket, 'system', auth.uid(), 'Ticket reopened', true);
end $$;

-- Delete ticket (single)
create or replace function delete_ticket(p_ticket uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not can_delete_tickets() then
    raise exception 'Unauthorized: Only managers and admins can delete tickets.' using errcode = '42501';
  end if;
  delete from tickets where id = p_ticket;
  return found;
end $$;

-- Delete tickets (bulk)
create or replace function delete_tickets(p_tickets uuid[]) returns integer
language plpgsql security definer set search_path = public as $$
declare deleted_count integer;
begin
  if not can_delete_tickets() then
    raise exception 'Unauthorized: Only managers and admins can delete tickets.' using errcode = '42501';
  end if;
  delete from tickets where id = any(p_tickets);
  get diagnostics deleted_count = row_count;
  return deleted_count;
end $$;

-- Delete site (cascades cleanly)
create or replace function delete_site(p_site_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _need('sites.manage');
  if not exists (select 1 from sites where id = p_site_id) then raise exception 'Site not found'; end if;
  delete from tickets where site_id = p_site_id;
  delete from bot_events where site_id = p_site_id;
  delete from bot_rules where site_id = p_site_id;
  delete from canned_replies where site_id = p_site_id;
  delete from site_secrets where site_id = p_site_id;
  delete from sites where id = p_site_id;
end $$;

-- Admin Create User (Email Verified)
create or replace function admin_create_user(
  p_email text,
  p_password text,
  p_real_name text,
  p_pseudo_name text,
  p_role app_role default 'employee',
  p_team_id uuid default null,
  p_email_confirm boolean default true
) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  new_id uuid := gen_random_uuid();
  encrypted_pw text;
begin
  perform _need('users.manage');

  p_email := lower(trim(coalesce(p_email, '')));
  p_real_name := trim(coalesce(p_real_name, ''));
  p_pseudo_name := trim(coalesce(p_pseudo_name, ''));

  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Invalid email address.'; end if;
  if char_length(p_real_name) < 2 then raise exception 'Real name must be at least 2 characters.'; end if;
  if char_length(p_pseudo_name) < 2 then raise exception 'Pseudo name must be at least 2 characters.'; end if;
  if char_length(coalesce(p_password, '')) < 6 then raise exception 'Password must be at least 6 characters.'; end if;

  if exists (select 1 from auth.users where email = p_email) then raise exception 'A user with this email already exists.'; end if;
  if exists (select 1 from profiles where pseudo_name = p_pseudo_name) then raise exception 'This pseudo name is already in use.'; end if;

  encrypted_pw := crypt(p_password, gen_salt('bf'));

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, recovery_sent_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated', p_email, encrypted_pw,
    case when p_email_confirm then now() else null end, null, null,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('name', p_real_name, 'pseudo_name', p_pseudo_name),
    false, now(), now(), '', '', '', ''
  );

  insert into profiles (id, real_name, pseudo_name, role, team_id, is_active)
  values (new_id, p_real_name, p_pseudo_name, p_role, p_team_id, true)
  on conflict (id) do update set
    real_name = excluded.real_name, pseudo_name = excluded.pseudo_name,
    role = excluded.role, team_id = excluded.team_id, is_active = true;

  return jsonb_build_object('id', new_id, 'email', p_email, 'pseudo_name', p_pseudo_name, 'email_confirmed', p_email_confirm);
end $$;

-- Admin Delete User (Permanently removes auth, profile, and unclaims tickets)
create or replace function admin_delete_user(p_user_id uuid) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  target_user auth.users%rowtype;
begin
  select role::text into caller_role from profiles where id = caller_id;
  if caller_role not in ('admin', 'manager') then
    raise exception 'Unauthorized: Only managers and admins can delete users.' using errcode = '42501';
  end if;

  if p_user_id = caller_id then raise exception 'You cannot delete your own account.'; end if;

  select * into target_user from auth.users where id = p_user_id;

  -- Unclaim active tickets so they return to open queue
  update tickets set claimed_by = null, claimed_at = null, status = 'open', updated_at = now()
  where claimed_by = p_user_id and status <> 'closed';

  delete from user_permissions where user_id = p_user_id;
  update teams set lead_id = null where lead_id = p_user_id;
  delete from profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('success', true);
end $$;

-- Dashboard Statistics
create or replace function dashboard_stats(p_days int default 30, p_site uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare since timestamptz := now() - make_interval(days => greatest(coalesce(p_days, 30), 1)); result jsonb;
begin
  perform _need('dashboard.view');
  select jsonb_build_object(
    'open', (select count(*) from tickets where status = 'open' and (p_site is null or site_id = p_site)),
    'claimed', (select count(*) from tickets where status = 'claimed' and (p_site is null or site_id = p_site)),
    'closed', (select count(*) from tickets where status = 'closed' and closed_at >= since and (p_site is null or site_id = p_site)),
    'created', (select count(*) from tickets where created_at >= since and (p_site is null or site_id = p_site)),
    'avg_first_response_min', (
      select round(avg(extract(epoch from first_response_at - created_at)) / 60)
      from tickets where first_response_at is not null and created_at >= since and (p_site is null or site_id = p_site)
    ),
    'top_rules', (
      select coalesce(jsonb_agg(x), '[]') from (
        select br.name, count(*) hits from bot_events e
        join bot_rules br on br.id = e.rule_id
        where e.created_at >= since and (p_site is null or e.site_id = p_site)
        group by br.name order by hits desc limit 10
      ) x
    ),
    'unmatched', (
      select coalesce(jsonb_agg(x), '[]') from (
        select query, count(*) hits from bot_events
        where not matched and created_at >= since and (p_site is null or site_id = p_site)
        group by query order by hits desc limit 10
      ) x
    ),
    'by_site', (
      select coalesce(jsonb_agg(x), '[]') from (
        select s.name, count(t.id) tickets from sites s
        left join tickets t on t.site_id = s.id and t.created_at >= since
        group by s.name order by tickets desc
      ) x
    ),
    'per_day', (
      select coalesce(jsonb_agg(x), '[]') from (
        select created_at::date d, count(*) n from tickets
        where created_at >= since and (p_site is null or site_id = p_site)
        group by 1 order by 1
      ) x
    )
  ) into result;
  return result;
end $$;

grant execute on function claim_ticket(uuid) to authenticated;
grant execute on function release_ticket(uuid) to authenticated;
grant execute on function assign_ticket(uuid, uuid) to authenticated;
grant execute on function staff_reply(uuid, text, boolean) to authenticated;
grant execute on function close_ticket(uuid) to authenticated;
grant execute on function reopen_ticket(uuid) to authenticated;
grant execute on function can_delete_tickets() to authenticated;
grant execute on function delete_ticket(uuid) to authenticated;
grant execute on function delete_tickets(uuid[]) to authenticated;
grant execute on function delete_site(uuid) to authenticated;
grant execute on function admin_create_user(text, text, text, text, app_role, uuid, boolean) to authenticated;
grant execute on function admin_delete_user(uuid) to authenticated;
grant execute on function dashboard_stats(int, uuid) to authenticated;
grant select on staff_public to authenticated;

-- ----------------------------------------------------------------------------
-- 9. TRIGGERS & NOTIFICATIONS
-- ----------------------------------------------------------------------------

-- Automatic Profile Creation on Supabase Auth Signup
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, real_name, pseudo_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'pseudo_name', 'staff-' || substr(replace(new.id::text, '-', ''), 1, 8)),
    (case when exists (select 1 from profiles) then 'employee' else 'admin' end)::app_role
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Webhook Notification on New Ticket Creation
create or replace function notify_new_ticket() returns trigger
language plpgsql security definer set search_path = public as $$
declare w text; d text; sname text; msg text;
begin
  select webhook_url, dashboard_url into w, d from site_secrets where site_id = new.site_id;
  if coalesce(w, '') = '' then return new; end if;
  select name into sname from sites where id = new.site_id;
  msg := format('New ticket UAA-%s on %s from %s: %s%s', new.ticket_no, sname, new.visitor_name, left(new.subject, 120),
                case when coalesce(d, '') <> '' then E'\n' || d || '/tickets' else '' end);
  begin
    perform net.http_post(
      url := w,
      body := jsonb_build_object('text', msg, 'content', msg),
      headers := '{"Content-Type":"application/json"}'::jsonb
    );
  exception when others then null; end;
  return new;
end $$;

drop trigger if exists tickets_notify on tickets;
create trigger tickets_notify after insert on tickets
  for each row execute function notify_new_ticket();

-- Enable Supabase Realtime for live chat & ticket lists
do $$ begin
  alter publication supabase_realtime add table tickets, ticket_messages;
exception when others then null; end $$;

-- ----------------------------------------------------------------------------
-- 10. SEED DATA & INITIAL CONFIGURATION
-- ----------------------------------------------------------------------------

-- Permissions
insert into permissions(key, description) values
  ('tickets.view_all', 'See every ticket, including all closed ones'),
  ('tickets.view_recent', 'See active tickets and tickets closed in the last 10 days'),
  ('tickets.claim', 'Claim and release tickets'),
  ('tickets.reply', 'Reply to visitors and write internal notes'),
  ('tickets.close', 'Close tickets they own'),
  ('tickets.reassign', 'Assign, release, close or reply on any ticket'),
  ('dashboard.view', 'View the operations dashboard'),
  ('rules.manage', 'Manage keyword rules and suggestion chips'),
  ('canned.manage', 'Manage saved canned replies'),
  ('sites.manage', 'Manage sites, themes, texts, and webhooks'),
  ('users.manage', 'Manage users, roles, and granular permissions'),
  ('users.view_real', 'See private real names behind staff pseudo names')
on conflict (key) do nothing;

-- Role Default Permissions
insert into role_permissions(role, permission)
  select 'admin', key from permissions
on conflict do nothing;

insert into role_permissions(role, permission)
  select 'manager', unnest(array[
    'tickets.view_all', 'tickets.claim', 'tickets.reply', 'tickets.close',
    'tickets.reassign', 'dashboard.view', 'rules.manage', 'canned.manage', 'users.view_real'
  ])
on conflict do nothing;

insert into role_permissions(role, permission)
  select 'teamlead', unnest(array[
    'tickets.view_all', 'tickets.claim', 'tickets.reply', 'tickets.close',
    'tickets.reassign', 'dashboard.view', 'rules.manage', 'canned.manage', 'users.view_real'
  ])
on conflict do nothing;

insert into role_permissions(role, permission)
  select 'employee', unnest(array[
    'tickets.view_recent', 'tickets.claim', 'tickets.reply', 'tickets.close', 'dashboard.view'
  ])
on conflict do nothing;

-- Default Airport Support Teams
insert into teams (name, description, color) values
  ('Passenger Assistance (PRM)', 'Wheelchair, mobility and dedicated passenger assistance services', '#0f7c86'),
  ('Customer Care & Enquiries', 'General airport enquiries, flight info, check-in, and lost property', '#1f7a4d'),
  ('Operations & Dispatch', 'Airside coordination, terminal dispatch, and escalation handling', '#b45309'),
  ('Baggage & Lost Property', 'Luggage retrieval, delayed baggage, and items lost in terminal', '#6366f1')
on conflict (name) do nothing;

-- Built-in Airport Bot Rules & Quick Reply Suggestion Chips
insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active) values
  (
    null,
    'Greetings & Welcome',
    array['hello', 'hi', 'hey', 'good morning', 'good afternoon', 'good evening', 'start', 'greetings', 'help', 'howdy'],
    'contains',
    'reply',
    'Hello! Welcome to our airport assistance desk. How can we help you today? You can ask about wheelchair assistance, baggage, flight details, or connect directly with our team.',
    null,
    null,
    10,
    true
  ),
  (
    null,
    'Wheelchair & Mobility (PRM)',
    array['wheelchair', 'mobility', 'prm', 'disabled', 'disability', 'handicap', 'walking', 'elderly', 'senior', 'stretcher', 'ramp', 'special assistance', 'escort', 'buggy', 'electric cart', 'accessible', 'assistance'],
    'contains',
    'reply',
    'We provide dedicated assistance for passengers with reduced mobility (PRM) free of charge. Our team can meet you at terminal entry, assist through check-in, security, and boarding. Please book at least 48 hours in advance for priority scheduling.',
    null,
    'Wheelchair assistance',
    20,
    true
  ),
  (
    null,
    'Baggage & Lost Items',
    array['baggage', 'luggage', 'bags', 'bag', 'suitcase', 'lost bag', 'lost luggage', 'delayed baggage', 'damaged bag', 'carousel', 'lost property', 'lost and found', 'lost item', 'lost my', 'left behind', 'left luggage', 'items'],
    'contains',
    'reply',
    'For baggage retrieval, delayed luggage, or items left inside the terminal, our Lost Property & Baggage desk is located in the Arrivals Hall near Carousel 3. Would you like to connect with our team to report a lost item?',
    null,
    'Lost baggage & items',
    30,
    true
  ),
  (
    null,
    'Flight & Gate Info',
    array['flight', 'gate', 'terminal', 'boarding', 'check in', 'checkin', 'check-in', 'delay', 'departure', 'arrival', 'boarding pass', 'counter', 'security', 'fast track', 'customs', 'passport', 'status', 'schedule', 'info'],
    'contains',
    'reply',
    'Check-in desks open 3 hours prior to international flights and 2 hours for domestic flights. Live gate assignments and flight schedules are displayed on terminal screens throughout the airport.',
    null,
    'Flight & Gate info',
    40,
    true
  ),
  (
    null,
    'Terminal Amenities & Wi-Fi',
    array['terminal', 'terminals', 'amenity', 'amenities', 'wifi', 'wi-fi', 'internet', 'restroom', 'restrooms', 'toilet', 'toilets', 'bathroom', 'washroom', 'food', 'restaurant', 'cafe', 'coffee', 'lounge', 'lounges', 'atm', 'cash', 'money', 'charging', 'charger', 'parking', 'taxi', 'cab', 'bus', 'train', 'water', 'smoking', 'prayer'],
    'contains',
    'reply',
    'Free high-speed airport Wi-Fi is available across all terminals. Restrooms, charging stations, prayer rooms, dining, and airline lounges are located along the central concourses.',
    null,
    'Terminal amenities',
    50,
    true
  ),
  (
    null,
    'Talk to Support Team',
    array['human', 'agent', 'person', 'staff', 'representative', 'talk to someone', 'speak to someone', 'talk to team', 'connect', 'live agent', 'operator', 'call me', 'urgent', 'real person', 'help me', 'team', 'support', 'talk to our team'],
    'contains',
    'handoff',
    'I would be happy to connect you with our assistance team. Please fill in your details below so an agent can assist you right away:',
    null,
    'Talk to our team',
    5,
    true
  )
on conflict do nothing;

-- Default Canned Replies
insert into canned_replies (site_id, title, body) values
  (null, 'Thanks and checking', 'Thank you for contacting our airport support desk. I am looking into this for you and will update you shortly.'),
  (null, 'Need booking ref', 'Could you please share your flight number, booking reference, and terminal location so we can assist you right away?')
on conflict do nothing;

-- Default Demo Site (Ready to test out of the box)
insert into sites (name, site_key, allowed_origins, faq_url, bot_chat_enabled, escalation_alarm_enabled)
values (
  'Airport Support Demo',
  'demo-site-key',
  '{}',
  'https://example.com/faq',
  false,
  true
)
on conflict (site_key) do nothing;

-- Reload PostgREST schema cache
notify pgrst, 'reload schema';

