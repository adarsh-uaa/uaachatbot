-- UAA Support · 001 schema
create extension if not exists pg_net;

create type app_role     as enum ('admin','manager','teamlead','employee');
create type ticket_status as enum ('open','claimed','closed');
create type msg_sender   as enum ('visitor','staff','bot','system');
create type rule_action  as enum ('reply','faq_link','handoff');
create type rule_match   as enum ('contains','exact');

-- Staff. real_name is private; pseudo_name is what everyone sees.
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  real_name   text not null,
  pseudo_name text not null unique,
  role        app_role not null default 'employee',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table permissions (key text primary key, description text not null);
create table role_permissions (
  role app_role not null,
  permission text not null references permissions(key) on delete cascade,
  primary key (role, permission)
);
-- per-user override: granted=true adds, granted=false removes
create table user_permissions (
  user_id uuid not null references profiles(id) on delete cascade,
  permission text not null references permissions(key) on delete cascade,
  granted boolean not null,
  primary key (user_id, permission)
);

create table sites (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  site_key text not null unique default replace(gen_random_uuid()::text,'-',''),
  allowed_origins text[] not null default '{}',
  faq_url text,
  theme jsonb not null default '{"primary":"#12202e","accent":"#f2a900","text":"#12202e","radius":14,"position":"right","icon":"chat","iconUrl":""}',
  texts jsonb not null default '{"title":"Assistance desk","subtitle":"We usually reply within a few minutes","greeting":"Hello! How can we help with your airport assistance?","placeholder":"Type your question…","fallback":"I could not find an answer for that. Would you like to talk to our team?","handoff":"Talk to our team","ticketCreated":"Thanks! Your request is with our team.","closed":"This conversation is closed."}',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
-- secrets are kept apart so only admins can read them
create table site_secrets (
  site_id uuid primary key references sites(id) on delete cascade,
  webhook_url text,       -- Slack / Discord / Google Chat incoming webhook
  dashboard_url text      -- e.g. https://support.example.com
);

create table bot_rules (
  id uuid primary key default gen_random_uuid(),
  site_id uuid references sites(id) on delete cascade,  -- null = applies to every site
  name text not null,
  keywords text[] not null,
  match_type rule_match not null default 'contains',
  action rule_action not null default 'reply',
  response text not null,
  link_url text,
  button_label text,       -- when set, shown as a quick-reply button
  priority int not null default 100,
  is_active boolean not null default true,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index on bot_rules (site_id, is_active, priority);

create table canned_replies (
  id uuid primary key default gen_random_uuid(),
  site_id uuid references sites(id) on delete cascade,
  title text not null,
  body text not null,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_no bigint generated always as identity,
  site_id uuid not null references sites(id),
  visitor_name text not null,
  visitor_email text not null,
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
create index on tickets (status, updated_at desc);
create index on tickets (claimed_by);
create index on tickets (site_id, created_at);
create index on tickets (closed_at);

create table ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references tickets(id) on delete cascade,
  sender msg_sender not null,
  author_id uuid references profiles(id) on delete set null,
  body text not null check (char_length(body) between 1 and 4000),
  is_internal boolean not null default false,
  created_at timestamptz not null default now()
);
create index on ticket_messages (ticket_id, created_at);

-- every question typed into the bot (feeds the "most repeated" dashboard)
create table bot_events (
  id bigint generated always as identity primary key,
  site_id uuid references sites(id) on delete cascade,
  rule_id uuid references bot_rules(id) on delete set null,
  query text not null,
  matched boolean not null,
  created_at timestamptz not null default now()
);
create index on bot_events (site_id, created_at);
