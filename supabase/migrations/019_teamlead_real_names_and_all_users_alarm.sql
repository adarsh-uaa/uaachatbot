-- ============================================================================
-- Migration 019: Realtime Alarms for All Users & Real Name Visibility for Teamlead & Management
-- 1. Grants 'users.view_real' permission to 'teamlead' and 'manager' roles.
-- 2. Updates profiles_read RLS so teamlead, manager, and admin can always view real names.
-- 3. Updates tickets_read and messages_read RLS so all active staff members receive
--    realtime broadcast events when tickets are created/escalated and visitor messages arrive.
-- 4. Adds tickets_update RLS policy so staff can update tickets (e.g. unread_by_staff).
-- 5. Updates claim_ticket RPC to set unread_by_staff = false and first_response_at so
--    the escalation alarm stops immediately for all logged-in users when one responds!
-- 6. Adds mark_ticket_read RPC.
-- 7. Ensures tickets and ticket_messages have FULL replica identity for Realtime change payloads.
-- ============================================================================

-- 1. Grant 'users.view_real' permission to 'teamlead' and 'manager'
insert into role_permissions (role, permission)
values 
  ('teamlead', 'users.view_real'),
  ('manager', 'users.view_real')
on conflict (role, permission) do nothing;

-- 2. Update profiles_read RLS policy
drop policy if exists profiles_read on profiles;
create policy profiles_read on profiles for select to authenticated
  using (
    id = auth.uid()
    or has_perm('users.view_real')
    or has_perm('users.manage')
    or (select role from profiles where id = auth.uid()) in ('admin', 'manager', 'teamlead')
  );

-- 3. Update tickets_read RLS so all active staff members receive Realtime events
drop policy if exists tickets_read on tickets;
create policy tickets_read on tickets for select to authenticated using (
  is_staff()
);

-- 4. Update messages_read RLS so all active staff members receive message Realtime events
drop policy if exists messages_read on ticket_messages;
create policy messages_read on ticket_messages for select to authenticated using (
  is_staff()
);

-- 5. Allow active staff to update tickets (e.g. mark read, claim, status)
drop policy if exists tickets_update on tickets;
create policy tickets_update on tickets for update to authenticated
  using (is_staff())
  with check (is_staff());

-- 6. Update claim_ticket RPC:
--    Setting unread_by_staff = false, claimed_by = auth.uid(), status = 'claimed'
--    immediately silences the escalation alarm for ALL logged-in staff members!
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

-- 7. Add mark_ticket_read RPC
create or replace function mark_ticket_read(p_ticket uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'forbidden' using errcode = '42501'; end if;
  update tickets set unread_by_staff = false, updated_at = now()
   where id = p_ticket and unread_by_staff = true;
end $$;

-- 8. Ensure tickets and ticket_messages have FULL replica identity for Realtime change payloads
alter table tickets replica identity full;
alter table ticket_messages replica identity full;

-- 9. Ensure both tables are in supabase_realtime publication
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'tickets'
  ) then
    alter publication supabase_realtime add table tickets;
  end if;
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ticket_messages'
  ) then
    alter publication supabase_realtime add table ticket_messages;
  end if;
end $$;

-- 10. Reload PostgREST schema cache
notify pgrst, 'reload schema';

