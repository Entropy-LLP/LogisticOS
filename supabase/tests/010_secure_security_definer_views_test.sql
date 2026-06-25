-- Test for migration 010 — SECURITY DEFINER views must not leak data to anon,
-- while the service-role backend must still read through them.
-- Run as the service-role/owner connection:
--   psql "$DATABASE_URL" -f supabase/tests/010_secure_security_definer_views_test.sql

DO $$
DECLARE
  seed    integer;
  leaked  integer;
  svc     integer;
  notes   text := '';
BEGIN
  SELECT count(*) INTO seed FROM public.bookings;
  IF seed = 0 THEN
    RAISE EXCEPTION 'INCONCLUSIVE: bookings empty — cannot prove anon is blocked';
  END IF;

  -- Security property: anon must receive ZERO rows. An RLS/privilege error also
  -- means zero rows reached anon (safe) — we record it but don't fail on it.
  SET LOCAL ROLE anon;
  BEGIN
    SELECT count(*) INTO leaked FROM public.v_active_bookings_with_driver;
  EXCEPTION WHEN OTHERS THEN leaked := 0; notes := notes || 'v_active err=' || SQLERRM || '; ';
  END;
  RESET ROLE;
  IF leaked > 0 THEN
    RAISE EXCEPTION 'FAIL: anon leaked % rows from v_active_bookings_with_driver', leaked;
  END IF;

  SET LOCAL ROLE anon;
  BEGIN
    SELECT count(*) INTO leaked FROM public.v_trip_summary;
  EXCEPTION WHEN OTHERS THEN leaked := 0; notes := notes || 'v_trip err=' || SQLERRM || '; ';
  END;
  RESET ROLE;
  IF leaked > 0 THEN
    RAISE EXCEPTION 'FAIL: anon leaked % rows from v_trip_summary', leaked;
  END IF;

  -- Regression: the service-role backend must still see data through the view.
  SET LOCAL ROLE service_role;
  SELECT count(*) INTO svc FROM public.v_active_bookings_with_driver;
  RESET ROLE;
  IF svc = 0 THEN
    RAISE EXCEPTION 'FAIL: service_role sees 0 rows through v_active_bookings_with_driver (backend broken)';
  END IF;

  RAISE NOTICE 'PASS 010: anon leaked 0 rows; service_role sees % (seed=% bookings). %',
    svc, seed, CASE WHEN notes = '' THEN 'clean 0-row reads' ELSE 'notes: ' || notes END;
END $$;
