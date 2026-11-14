-- UAA Support · 002 permissions helpers + RLS

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and is_active)
$$;

-- user override wins, otherwise role default
create or replace function has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select is_staff() and coalesce(
    (select granted from user_permissions where user_id = auth.uid() and permission = p),
    exists (select 1 from profiles pr join role_permissions rp on rp.role = pr.role
            where pr.id = auth.uid() and rp.permission = p)
  )
$$;

create or replace function my_permissions() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(key), '{}') from permissions where has_perm(key)
$$;

-- pseudo names only: safe for every staff member to read
create view staff_public with (security_invoker = false) as
  select id, pseudo_name, role, is_active from profiles;

alter table profiles         enable row level security;
alter table permissions      enable row level security;
alter table role_permissions enable row level security;
alter table user_permissions enable row level security;
alter table sites            enable row level security;
alter table site_secrets     enable row level security;
alter table bot_rules        enable row level security;
alter table canned_replies   enable row level security;
alter table tickets          enable row level security;
alter table ticket_messages  enable row level security;
alter table bot_events       enable row level security;

-- profiles: real names only for yourself or users.view_real / users.manage
create policy profiles_read  on profiles for select to authenticated
  using (id = auth.uid() or has_perm('users.view_real') or has_perm('users.manage'));
create policy profiles_write on profiles for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));

create policy perms_read on permissions for select to authenticated using (is_staff());
create policy roleperm_read  on role_permissions for select to authenticated using (is_staff());
create policy roleperm_write on role_permissions for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));
create policy userperm_read  on user_permissions for select to authenticated
  using (user_id = auth.uid() or has_perm('users.manage'));
create policy userperm_write on user_permissions for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));

create policy sites_read  on sites for select to authenticated using (is_staff());
create policy sites_write on sites for all to authenticated
  using (has_perm('sites.manage')) with check (has_perm('sites.manage'));
create policy secrets_all on site_secrets for all to authenticated
  using (has_perm('sites.manage')) with check (has_perm('sites.manage'));

create policy rules_read  on bot_rules for select to authenticated using (is_staff());
create policy rules_write on bot_rules for all to authenticated
  using (has_perm('rules.manage')) with check (has_perm('rules.manage'));
create policy canned_read  on canned_replies for select to authenticated using (is_staff());
create policy canned_write on canned_replies for all to authenticated
  using (has_perm('canned.manage')) with check (has_perm('canned.manage'));

-- tickets: global visibility. Managers/team leads see everything;
-- employees see active tickets + tickets closed in the last 10 days.
create policy tickets_read on tickets for select to authenticated using (
  has_perm('tickets.view_all')
  or (has_perm('tickets.view_recent')
      and (status <> 'closed' or closed_at > now() - interval '10 days'))
);
-- no insert/update/delete policies: every change goes through the RPCs below.
create policy messages_read on ticket_messages for select to authenticated using (
  exists (select 1 from tickets t where t.id = ticket_id)   -- inherits ticket RLS
);
create policy events_read on bot_events for select to authenticated using (has_perm('dashboard.view'));

-- lock down the API surface
grant usage on schema public to anon, authenticated;
revoke all on all tables in schema public from anon;
grant select on staff_public to authenticated;
revoke all on staff_public from anon;
alter default privileges in schema public revoke all on tables from anon;

-- realtime (respects RLS)
alter publication supabase_realtime add table tickets, ticket_messages;
