-- ============================================================
-- Migration 013: Revoke EXECUTE on SECURITY DEFINER trigger functions
--
-- handle_new_user, handle_new_driver, handle_user_metadata_update and
-- handle_user_role_update are SECURITY DEFINER *trigger* functions (fired by
-- triggers on auth.users / users / drivers). They were EXECUTE-able by
-- anon/authenticated (via the default PUBLIC grant), so the advisor flags them
-- as callable-by-anon SECURITY DEFINER functions.
--
-- Trigger functions never need a direct EXECUTE grant — Postgres fires triggers
-- regardless of the invoking role's EXECUTE privilege. Revoking EXECUTE from
-- PUBLIC/anon/authenticated removes the API-callable surface without affecting
-- the triggers (signup, profile/role sync continue to work).
--
-- Advisor: 0017_security_definer_function (anon_/authenticated_..._executable).
-- NOTE: the 3 st_estimatedextent overloads are PostGIS (owned by supabase_admin)
-- and cannot be revoked from the postgres role — see docs/SECURITY_ADVISORS.md.
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.handle_new_user()             FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_driver()           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_user_metadata_update() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_user_role_update()     FROM PUBLIC, anon, authenticated;
