-- UAA Support · 011 Escalation Alarm Settings & Controls
-- Adds per-site and global controls for continuous escalation alarm when tickets transition from bot to team.

-- 1. Add escalation_alarm_enabled to sites table (defaults to true)
alter table sites add column if not exists escalation_alarm_enabled boolean not null default true;

-- 2. Update widget_config RPC to include escalation_alarm_enabled if needed
create or replace function widget_config(p_site_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s sites;
begin
  select * into s from sites where site_key = p_site_key and is_active;
  if not found then raise exception 'unknown site'; end if;
  return jsonb_build_object(
    'site_name', s.name,
    'theme', s.theme,
    'texts', s.texts,
    'faq_url', s.faq_url,
    'escalation_alarm_enabled', coalesce(s.escalation_alarm_enabled, true),
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

grant execute on function widget_config(text) to anon, authenticated;

-- 3. Function to update all sites escalation alarm setting simultaneously (all sites together)
create or replace function set_all_sites_alarm(p_enabled boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _need('sites.manage');
  update sites set escalation_alarm_enabled = p_enabled;
end $$;

grant execute on function set_all_sites_alarm(boolean) to authenticated;

-- 4. Reload PostgREST schema cache
notify pgrst, 'reload schema';

