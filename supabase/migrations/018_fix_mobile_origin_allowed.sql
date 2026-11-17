-- ============================================================================
-- Migration 018: Fix Mobile & Subdomain Origin Verification
-- Handles mobile Safari, Android WebViews, capacitor/ionic apps, local Wi-Fi
-- mobile testing (192.168.x.x, 10.x.x.x), www/m. subdomains, and wildcard '*'
-- ============================================================================

create or replace function _origin_ok(p_allowed text[]) returns boolean
language plpgsql stable as $$
declare
  headers json;
  raw_origin text;
  raw_referer text;
  req_origin text;
  clean_req text;
  req_host text;
  entry text;
  clean_entry text;
  entry_host text;
begin
  -- 1. If allowed_origins is null, empty, or contains '*', allow all requests
  if p_allowed is null or coalesce(array_length(p_allowed, 1), 0) = 0 then
    return true;
  end if;

  if '*' = any(p_allowed) or '' = any(p_allowed) then
    return true;
  end if;

  -- 2. Safely extract headers from PostgREST request context
  begin
    headers := current_setting('request.headers', true)::json;
  exception when others then
    headers := null;
  end;

  if headers is null then
    return true; -- non-HTTP or SQL background caller
  end if;

  raw_origin := headers->>'origin';
  raw_referer := headers->>'referer';

  -- Normalize raw_origin: mobile Safari and WebViews often send literal 'null' or omit it
  if raw_origin is not null and lower(trim(raw_origin)) <> 'null' and trim(raw_origin) <> '' then
    req_origin := lower(trim(raw_origin));
  elsif raw_referer is not null and trim(raw_referer) <> '' and lower(trim(raw_referer)) <> 'null' then
    -- Extract scheme://host(:port) from Referer header
    req_origin := lower(trim(substring(raw_referer from '^(https?://[^/?#]+)')));
  end if;

  -- If neither origin nor referer was supplied (mobile privacy mode, native webview, local file, or sandboxed iframe)
  if req_origin is null or req_origin = '' or req_origin = 'null' then
    return true;
  end if;

  -- Allow common hybrid mobile app schemes (Capacitor, Ionic, Cordova, local files)
  if req_origin like 'capacitor://%' or req_origin like 'ionic://%' or req_origin like 'file://%' then
    return true;
  end if;

  -- Strip trailing slashes
  req_origin := regexp_replace(req_origin, '/+$', '');

  -- Extract clean host without protocol or port
  clean_req := regexp_replace(req_origin, '^https?://', '');
  req_host := split_part(clean_req, ':', 1);

  -- Support local Wi-Fi mobile testing (192.168.x.x, 10.x.x.x, 172.16-31.x.x, localhost)
  -- when site has localhost or local IP in allowed origins
  if (req_host in ('localhost', '127.0.0.1')
      or req_host ~ '^192\.168\.\d+\.\d+$'
      or req_host ~ '^10\.\d+\.\d+\.\d+$'
      or req_host ~ '^172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+$')
     and ('localhost' = any(p_allowed) or 'http://localhost' = any(p_allowed) or '127.0.0.1' = any(p_allowed) or exists (
       select 1 from unnest(p_allowed) pe where pe like '%localhost%' or pe like '%127.0.0.1%' or pe like '%192.168%' or pe like '%10.%'
     )) then
    return true;
  end if;

  -- 3. Match against allowed origin entries
  foreach entry in array p_allowed loop
    entry := lower(trim(entry));
    if entry = '' or entry = '*' then
      return true;
    end if;

    entry := regexp_replace(entry, '/+$', '');

    -- Exact match (e.g. 'https://example.com' = 'https://example.com')
    if req_origin = entry then
      return true;
    end if;

    clean_entry := regexp_replace(entry, '^https?://', '');
    entry_host := split_part(clean_entry, ':', 1);

    -- Match without protocol
    if clean_req = clean_entry then
      return true;
    end if;

    -- Host match (ignoring port & protocol)
    if req_host = entry_host and entry_host <> '' then
      return true;
    end if;

    -- Match www vs non-www
    if (req_host = 'www.' || entry_host) or (entry_host = 'www.' || req_host) then
      return true;
    end if;

    -- Match mobile subdomains (m., mobile., app.)
    if (req_host = 'm.' || entry_host) or (req_host = 'mobile.' || entry_host) or (req_host = 'app.' || entry_host) then
      return true;
    end if;

    -- Wildcard domain matching (*.domain.com or .domain.com)
    if entry_host like '*.%' then
      if req_host = substring(entry_host from 3) or req_host like '%.' || substring(entry_host from 3) then
        return true;
      end if;
    elsif entry_host like '.%' then
      if req_host = substring(entry_host from 2) or req_host like '%.' || substring(entry_host from 2) then
        return true;
      end if;
    end if;

    -- Wildcard pattern matching (e.g. *.trycloudflare.com, *ngrok*, *192.168.*)
    if entry like '%*%' then
      if clean_req like replace(clean_entry, '*', '%') or req_origin like replace(entry, '*', '%') then
        return true;
      end if;
    end if;
  end loop;

  return false;
end $$;

