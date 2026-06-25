-- Test for migration 011 — users RLS must no longer recurse, and must not leak.
-- A recursion (42P17) is intentionally NOT caught, so it would fail this test.
-- insufficient_privilege IS caught (anon simply lacking a grant = safe, 0 rows).

DO $$
DECLARE
  n   integer;
  svc integer;
BEGIN
  -- anon reading users must not recurse; returns 0 (anon has no auth.uid()).
  SET LOCAL ROLE anon;
  BEGIN
    SELECT count(*) INTO n FROM public.users;
  EXCEPTION WHEN insufficient_privilege THEN n := 0;
  END;
  RESET ROLE;
  IF n > 0 THEN RAISE EXCEPTION 'FAIL: anon can read % users rows', n; END IF;

  -- The security_invoker view must now resolve cleanly for anon (no recursion).
  SET LOCAL ROLE anon;
  BEGIN
    SELECT count(*) INTO n FROM public.v_active_bookings_with_driver;
  EXCEPTION WHEN insufficient_privilege THEN n := 0;
  END;
  RESET ROLE;
  IF n > 0 THEN RAISE EXCEPTION 'FAIL: anon leaked % rows via view', n; END IF;

  -- Regression: service-role backend still reads users fully.
  SET LOCAL ROLE service_role;
  SELECT count(*) INTO svc FROM public.users;
  RESET ROLE;
  IF svc = 0 THEN RAISE EXCEPTION 'FAIL: service_role sees 0 users (backend broken)'; END IF;

  RAISE NOTICE 'PASS 011: no recursion; anon users=0, anon view=0; service_role users=%', svc;
END $$;
