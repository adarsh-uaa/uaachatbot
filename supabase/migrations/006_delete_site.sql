-- UAA Support · 006 delete site with cascading cleanup

-- 1. Ensure foreign key constraint on tickets cascades automatically
alter table tickets
  drop constraint if exists tickets_site_id_fkey,
  add constraint tickets_site_id_fkey
    foreign key (site_id) references sites(id) on delete cascade;

-- 2. Allow delete on tickets for site administrators
drop policy if exists tickets_delete on tickets;
create policy tickets_delete on tickets for delete to authenticated
  using (has_perm('sites.manage'));

-- 3. Stored procedure for deleting a site with permission check
create or replace function delete_site(p_site_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- Check permission
  perform _need('sites.manage');

  if not exists (select 1 from sites where id = p_site_id) then
    raise exception 'Site not found';
  end if;

  -- Delete tickets for this site (which cascades to ticket_messages)
  delete from tickets where site_id = p_site_id;

  -- Delete bot_events
  delete from bot_events where site_id = p_site_id;

  -- Delete bot_rules
  delete from bot_rules where site_id = p_site_id;

  -- Delete canned_replies
  delete from canned_replies where site_id = p_site_id;

  -- Delete site_secrets
  delete from site_secrets where site_id = p_site_id;

  -- Delete site
  delete from sites where id = p_site_id;
end $$;

grant execute on function delete_site(uuid) to authenticated;

