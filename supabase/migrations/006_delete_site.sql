-- UAA Support · 006 delete site with cascading cleanup
create or replace function delete_site(p_site_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- 1. Check permission
  perform _need('sites.manage');

  if not exists (select 1 from sites where id = p_site_id) then
    raise exception 'Site not found';
  end if;

  -- 2. Delete tickets for this site (which cascades to ticket_messages)
  delete from tickets where site_id = p_site_id;

  -- 3. Delete bot_events
  delete from bot_events where site_id = p_site_id;

  -- 4. Delete bot_rules
  delete from bot_rules where site_id = p_site_id;

  -- 5. Delete canned_replies
  delete from canned_replies where site_id = p_site_id;

  -- 6. Delete site_secrets
  delete from site_secrets where site_id = p_site_id;

  -- 7. Delete site
  delete from sites where id = p_site_id;
end $$;

grant execute on function delete_site(uuid) to authenticated;

