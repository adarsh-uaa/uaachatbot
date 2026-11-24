-- Migration 023: Rename admin to developer in profiles, permissions, and functions
-- Prerequisite: Migration 022 must have been run and committed first.

-- 1. Update existing profile names from 'admin' to 'developer'
UPDATE profiles SET pseudo_name = 'developer' WHERE lower(pseudo_name) = 'admin';
UPDATE profiles SET real_name = 'developer' WHERE lower(real_name) = 'admin';

-- 2. Update existing admin profiles to role 'developer'
UPDATE profiles SET role = 'developer' WHERE role::text = 'admin';

-- 3. Copy permissions from admin to developer in role_permissions
INSERT INTO role_permissions (role, permission)
SELECT 'developer'::app_role, key FROM permissions
ON CONFLICT DO NOTHING;

-- 4. Update can_view_real to include developer (used by profiles_read RLS policy)
CREATE OR REPLACE FUNCTION can_view_real() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles pr
    WHERE pr.id = auth.uid()
      AND (
        pr.role::text IN ('admin', 'developer', 'manager', 'teamlead')
        OR EXISTS (
          SELECT 1 FROM role_permissions rp
          WHERE rp.role = pr.role AND rp.permission IN ('users.view_real', 'users.manage')
        )
        OR EXISTS (
          SELECT 1 FROM user_permissions up
          WHERE up.user_id = pr.id AND up.permission IN ('users.view_real', 'users.manage') AND up.granted = true
        )
      )
  );
$$;

GRANT EXECUTE ON FUNCTION can_view_real() TO authenticated;

-- Also provide can_view_real_names() as an alias
CREATE OR REPLACE FUNCTION can_view_real_names() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT can_view_real();
$$;

GRANT EXECUTE ON FUNCTION can_view_real_names() TO authenticated;

-- 5. Update can_delete_tickets to include developer
CREATE OR REPLACE FUNCTION can_delete_tickets() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles pr
    WHERE pr.id = auth.uid()
      AND pr.is_active = true
      AND pr.role::text IN ('admin', 'developer', 'manager')
  );
$$;

GRANT EXECUTE ON FUNCTION can_delete_tickets() TO authenticated;

-- 6. Update single ticket delete RPC
CREATE OR REPLACE FUNCTION delete_ticket(p_ticket uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT can_delete_tickets() THEN
    RAISE EXCEPTION 'Unauthorized: Only managers and developers can delete tickets.' USING errcode = '42501';
  END IF;
  DELETE FROM tickets WHERE id = p_ticket;
  RETURN found;
END $$;

GRANT EXECUTE ON FUNCTION delete_ticket(uuid) TO authenticated;

-- 7. Update bulk ticket delete RPC
CREATE OR REPLACE FUNCTION delete_tickets(p_tickets uuid[]) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE deleted_count integer;
BEGIN
  IF NOT can_delete_tickets() THEN
    RAISE EXCEPTION 'Unauthorized: Only managers and developers can delete tickets.' USING errcode = '42501';
  END IF;
  DELETE FROM tickets WHERE id = ANY(p_tickets);
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END $$;

GRANT EXECUTE ON FUNCTION delete_tickets(uuid[]) TO authenticated;

-- 8. Update admin_delete_user to allow developer role
CREATE OR REPLACE FUNCTION admin_delete_user(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, extensions AS $$
DECLARE
  caller_id uuid := auth.uid();
  caller_role text;
  target_user auth.users%rowtype;
BEGIN
  SELECT role::text INTO caller_role FROM profiles WHERE id = caller_id;
  IF caller_role NOT IN ('admin', 'developer', 'manager') THEN
    RAISE EXCEPTION 'Unauthorized: Only managers and developers can delete users.' USING errcode = '42501';
  END IF;

  IF p_user_id = caller_id THEN
    RAISE EXCEPTION 'You cannot delete your own account.';
  END IF;

  SELECT * INTO target_user FROM auth.users WHERE id = p_user_id;

  -- Unclaim active tickets so they return to open queue
  UPDATE tickets SET claimed_by = null, claimed_at = null, status = 'open', updated_at = now()
  WHERE claimed_by = p_user_id AND status <> 'closed';

  DELETE FROM user_permissions WHERE user_id = p_user_id;
  UPDATE teams SET lead_id = null WHERE lead_id = p_user_id;
  DELETE FROM profiles WHERE id = p_user_id;
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION admin_delete_user(uuid) TO authenticated;

