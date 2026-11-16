-- UAA Support · 012 Bulk and Single Ticket Deletion RPC & Policy

-- 1. Function to delete single ticket
create or replace function delete_ticket(p_ticket uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  delete from tickets where id = p_ticket;
  return found;
end $$;

grant execute on function delete_ticket(uuid) to authenticated;

-- 2. Function to delete multiple selected tickets in bulk
create or replace function delete_tickets(p_tickets uuid[]) returns integer
language plpgsql security definer set search_path = public as $$
declare
  deleted_count integer;
begin
  if not is_staff() then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  delete from tickets where id = any(p_tickets);
  get diagnostics deleted_count = row_count;
  return deleted_count;
end $$;

grant execute on function delete_tickets(uuid[]) to authenticated;

-- 3. Add explicit RLS policy so direct client delete calls also work
drop policy if exists tickets_delete on tickets;
create policy tickets_delete on tickets for delete to authenticated using (is_staff());

-- 4. Reload PostgREST schema cache
notify pgrst, 'reload schema';

