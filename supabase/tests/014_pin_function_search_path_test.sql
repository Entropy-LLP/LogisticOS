-- Test for migration 014 — search_path pinned on all 5 functions, AND the action
-- functions still execute correctly under the pinned path. The action functions
-- are called with non-existent UUIDs, which hit their early "not found" return
-- BEFORE any INSERT/UPDATE, so this test has no side effects.
-- Run as the owner/service-role connection.

DO $$
DECLARE
  f       text;
  missing text := '';
  ok      boolean;
  zero    uuid := '00000000-0000-0000-0000-000000000000';
  fns     text[] := ARRAY['accept_booking','complete_trip','start_trip',
                          'update_updated_at','update_updated_at_column'];
BEGIN
  -- Static: every function now has a pinned search_path.
  FOREACH f IN ARRAY fns LOOP
    PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname=f
       AND COALESCE(array_to_string(p.proconfig, ','), '') LIKE '%search_path%';
    IF NOT FOUND THEN missing := missing || f || ' '; END IF;
  END LOOP;
  IF missing <> '' THEN
    RAISE EXCEPTION 'FAIL 014: search_path not pinned on: %', missing;
  END IF;

  -- Functional: the action functions resolve their qualified refs under search_path=''
  -- (bogus ids => early "not found" return, no mutation).
  SELECT success INTO ok FROM public.accept_booking(zero, zero);
  IF ok IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL: accept_booking returned %', ok; END IF;

  SELECT success INTO ok FROM public.start_trip(zero);
  IF ok IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL: start_trip returned %', ok; END IF;

  SELECT success INTO ok FROM public.complete_trip(zero, NULL);
  IF ok IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL: complete_trip returned %', ok; END IF;

  RAISE NOTICE 'PASS 014: search_path pinned on 5 fns; action fns execute correctly under pinned path';
END $$;
