-- Migration 020: Restrict chat and user deletion to Admin and Manager roles only.
-- Employees and Teamleads cannot delete tickets or team members.

-- 1. Helper function to check if caller has management delete permissions (admin or manager)
create or replace function can_delete_tickets() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles pr
    where pr.id = auth.uid()
      and pr.is_active = true
      and pr.role in ('admin', 'manager')
  );
$$;

grant execute on function can_delete_tickets() to authenticated;

-- 2. Restrict single ticket delete RPC to admin and manager
create or replace function delete_ticket(p_ticket uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not can_delete_tickets() then
    raise exception 'Unauthorized: Only managers and admins can delete tickets.' using errcode = '42501';
  end if;
  delete from tickets where id = p_ticket;
  return found;
end $$;

grant execute on function delete_ticket(uuid) to authenticated;

-- 3. Restrict bulk ticket delete RPC to admin and manager
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

grant execute on function delete_tickets(uuid[]) to authenticated;

-- 4. Update tickets_delete RLS policy
drop policy if exists tickets_delete on tickets;
create policy tickets_delete on tickets for delete to authenticated
  using (can_delete_tickets());

-- 5. Restrict admin_delete_user to admin and manager
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

  if p_user_id = caller_id then
    raise exception 'You cannot delete your own account.';
  end if;

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

grant execute on function admin_delete_user(uuid) to authenticated;

