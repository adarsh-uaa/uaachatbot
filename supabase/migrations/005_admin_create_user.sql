-- UAA Support · 005 direct user creation (email verified) + teams section
create extension if not exists pgcrypto;

-- ---------- teams ----------
create table if not exists teams (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  color text not null default '#0f7c86',
  lead_id uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- add team_id to profiles if not already added
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'profiles' and column_name = 'team_id'
  ) then
    alter table profiles add column team_id uuid references teams(id) on delete set null;
  end if;
end $$;

-- update staff_public view so it includes team_id and created_at
create or replace view staff_public with (security_invoker = false) as
  select id, pseudo_name, role, is_active, team_id, created_at from profiles;

-- RLS on teams
alter table teams enable row level security;

drop policy if exists teams_read on teams;
create policy teams_read on teams for select to authenticated using (is_staff());

drop policy if exists teams_write on teams;
create policy teams_write on teams for all to authenticated
  using (has_perm('users.manage')) with check (has_perm('users.manage'));

grant select on teams to authenticated;
revoke all on teams from anon;

-- Seed default airport support teams if empty
insert into teams (name, description, color) values
  ('Passenger Assistance (PRM)', 'Wheelchair, mobility and dedicated passenger assistance services', '#0f7c86'),
  ('Customer Care & Enquiries', 'General airport enquiries, flight info, check-in, and lost property', '#1f7a4d'),
  ('Operations & Dispatch', 'Airside coordination, terminal dispatch, and escalation handling', '#b45309')
on conflict (name) do nothing;

-- ---------- direct user creation (email verified) ----------
create or replace function admin_create_user(
  p_email text,
  p_password text,
  p_real_name text,
  p_pseudo_name text,
  p_role app_role default 'employee',
  p_team_id uuid default null,
  p_email_confirm boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  new_uid uuid := gen_random_uuid();
  encrypted_pw text;
  clean_email text := lower(trim(coalesce(p_email, '')));
  clean_real_name text := trim(coalesce(p_real_name, ''));
  clean_pseudo_name text := trim(coalesce(p_pseudo_name, ''));
  target_team uuid := p_team_id;
begin
  -- 1. Check caller permission
  perform _need('users.manage');

  -- 2. Validate input
  if clean_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(clean_email) > 160 then
    raise exception 'Please enter a valid email address';
  end if;
  if char_length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if char_length(clean_real_name) < 1 then
    raise exception 'Real name is required';
  end if;
  if char_length(clean_pseudo_name) < 1 then
    raise exception 'Pseudo name is required';
  end if;

  -- Verify team exists if passed
  if target_team is not null and not exists (select 1 from teams where id = target_team) then
    target_team := null;
  end if;

  -- 3. Check duplicate email or pseudo name
  if exists (select 1 from auth.users where email = clean_email) then
    raise exception 'A user with email "%" already exists', clean_email;
  end if;
  if exists (select 1 from profiles where pseudo_name = clean_pseudo_name) then
    raise exception 'Pseudo name "%" is already taken. Please choose another.', clean_pseudo_name;
  end if;

  -- 4. Encrypt password with bcrypt Blowfish
  encrypted_pw := crypt(p_password, gen_salt('bf', 10));

  -- 5. Insert directly into auth.users (email_confirmed_at is set to now() -> EMAIL VERIFIED!)
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    new_uid,
    'authenticated',
    'authenticated',
    clean_email,
    encrypted_pw,
    case when coalesce(p_email_confirm, true) then now() else null end,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('name', clean_real_name),
    false,
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  -- 6. Insert into auth.identities so Supabase GoTrue recognizes the password login
  begin
    insert into auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    ) values (
      new_uid::text,
      new_uid,
      jsonb_build_object('sub', new_uid::text, 'email', clean_email),
      'email',
      clean_email,
      null,
      now(),
      now()
    );
  exception when others then
    -- Fallback for Supabase versions where provider_id is new_uid::text
    begin
      insert into auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        provider_id,
        last_sign_in_at,
        created_at,
        updated_at
      ) values (
        new_uid::text,
        new_uid,
        jsonb_build_object('sub', new_uid::text, 'email', clean_email),
        'email',
        new_uid::text,
        null,
        now(),
        now()
      );
    exception when others then
      null;
    end;
  end;

  -- 7. Upsert profile with real_name, pseudo_name, role, and team_id
  insert into profiles (id, real_name, pseudo_name, role, team_id, is_active)
  values (new_uid, clean_real_name, clean_pseudo_name, coalesce(p_role, 'employee'), target_team, true)
  on conflict (id) do update set
    real_name = excluded.real_name,
    pseudo_name = excluded.pseudo_name,
    role = excluded.role,
    team_id = excluded.team_id,
    is_active = true;

  return jsonb_build_object(
    'id', new_uid,
    'email', clean_email,
    'real_name', clean_real_name,
    'pseudo_name', clean_pseudo_name,
    'role', coalesce(p_role, 'employee'),
    'team_id', target_team,
    'email_confirmed', coalesce(p_email_confirm, true)
  );
end $$;

grant execute on function admin_create_user(text, text, text, text, app_role, uuid, boolean) to authenticated;

