-- UAA Support · 016 Admin Delete User RPC
-- Allows authorized staff with 'users.manage' to permanently delete team member accounts,
-- unclaim active tickets, clean up permissions, and delete auth credentials.

create or replace function admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  caller_id uuid;
  target_user auth.users%rowtype;
  target_pseudo text;
begin
  -- 1. Check caller permission
  perform _need('users.manage');
  caller_id := auth.uid();

  -- 2. Prevent self-deletion
  if p_user_id = caller_id then
    raise exception 'You cannot delete your own account.';
  end if;

  -- 3. Get user details
  select * into target_user from auth.users where id = p_user_id;
  select pseudo_name into target_pseudo from profiles where id = p_user_id;

  if target_user.id is null and target_pseudo is null then
    raise exception 'User not found.';
  end if;

  -- 4. Safely unclaim any active tickets currently claimed by this user
  update tickets 
  set claimed_by = null, 
      claimed_at = null, 
      status = 'open',
      updated_at = now()
  where claimed_by = p_user_id and status <> 'closed';

  -- 5. Delete specific user permissions overrides
  delete from user_permissions where user_id = p_user_id;

  -- 6. Unassign from team leadership
  update teams set lead_id = null where lead_id = p_user_id;

  -- 7. Delete profile record
  delete from profiles where id = p_user_id;

  -- 8. Delete auth user record so credentials are removed and email is freed
  if target_user.id is not null then
    delete from auth.users where id = p_user_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'pseudo_name', target_pseudo
  );
end $$;

grant execute on function admin_delete_user(uuid) to authenticated;

