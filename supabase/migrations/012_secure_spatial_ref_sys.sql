-- ============================================================
-- Migration 012: Lock down PostGIS spatial_ref_sys (best-effort)
--
-- spatial_ref_sys is a PostGIS reference table (coordinate-system definitions)
-- with RLS disabled and full grants to anon/authenticated. The data is
-- non-sensitive public reference data, but anon technically holds
-- INSERT/UPDATE/DELETE/TRUNCATE, so it could be corrupted/wiped via the anon key.
--
-- The table is owned by `supabase_admin`; the `postgres` role used for migrations
-- CANNOT ALTER it or REVOKE its grants (ERROR 42501 "must be owner"). So this
-- block attempts the lock-down and degrades to a NOTICE if it lacks ownership —
-- the migration never fails, and it self-heals if ever run by a privileged role
-- (e.g. supabase_admin).
--
-- Residual + manual remediation: see docs/SECURITY_ADVISORS.md.
-- Advisor: 0013_rls_disabled_in_public (spatial_ref_sys).
-- ============================================================

DO $$
BEGIN
  ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY;

  BEGIN
    EXECUTE 'CREATE POLICY "spatial_ref_sys read-only" ON public.spatial_ref_sys FOR SELECT TO public USING (true)';
  EXCEPTION WHEN duplicate_object THEN NULL;  -- already created
  END;

  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON public.spatial_ref_sys FROM anon, authenticated;

  RAISE NOTICE 'spatial_ref_sys locked down: RLS on, read-only policy, writes revoked.';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'spatial_ref_sys: insufficient privilege (owned by supabase_admin) — skipped. Apply as supabase_admin; see docs/SECURITY_ADVISORS.md.';
END $$;
