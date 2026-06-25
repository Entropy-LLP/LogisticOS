-- Verification for migration 012 (spatial_ref_sys lock-down).
-- NOTE: this PASSES only once 012 has been applied by a privileged role
-- (supabase_admin). With the default `postgres` migration role it reports
-- PENDING, because the table is owned by supabase_admin and can't be altered.
-- Run as the owner/service-role connection.

DO $$
DECLARE
  rls_on    boolean;
  anon_write boolean;
BEGIN
  SELECT c.relrowsecurity INTO rls_on
  FROM pg_class c WHERE c.relname='spatial_ref_sys' AND c.relnamespace='public'::regnamespace;

  SELECT bool_or(privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE')) INTO anon_write
  FROM information_schema.role_table_grants
  WHERE table_schema='public' AND table_name='spatial_ref_sys' AND grantee IN ('anon','authenticated');

  IF rls_on AND COALESCE(anon_write,false) = false THEN
    RAISE NOTICE 'PASS 012: spatial_ref_sys has RLS enabled and no anon/authenticated write grants.';
  ELSE
    RAISE NOTICE 'PENDING 012: rls_enabled=%, anon/authenticated_write=% — apply migration 012 as supabase_admin (see docs/SECURITY_ADVISORS.md).',
      rls_on, COALESCE(anon_write,false);
  END IF;
END $$;
