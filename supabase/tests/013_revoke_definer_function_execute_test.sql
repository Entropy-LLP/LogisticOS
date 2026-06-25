-- Test for migration 013 — the 4 SECURITY DEFINER trigger functions must no
-- longer be EXECUTE-able by anon/authenticated, while the triggers that use them
-- must still be attached. Run as the owner/service-role connection.

DO $$
DECLARE
  fn   text;
  bad  text := '';
  fns  text[] := ARRAY[
    'public.handle_new_user()',
    'public.handle_new_driver()',
    'public.handle_user_metadata_update()',
    'public.handle_user_role_update()'
  ];
  trig_count integer;
BEGIN
  FOREACH fn IN ARRAY fns LOOP
    IF has_function_privilege('anon', fn, 'EXECUTE') THEN
      bad := bad || 'anon:' || fn || ' ';
    END IF;
    IF has_function_privilege('authenticated', fn, 'EXECUTE') THEN
      bad := bad || 'authenticated:' || fn || ' ';
    END IF;
  END LOOP;

  IF bad <> '' THEN
    RAISE EXCEPTION 'FAIL 013: still EXECUTE-able by client roles: %', bad;
  END IF;

  -- Regression: the trigger functions are still wired to triggers (not orphaned).
  SELECT count(*) INTO trig_count
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE p.proname IN ('handle_new_user','handle_new_driver',
                      'handle_user_metadata_update','handle_user_role_update')
    AND NOT t.tgisinternal;
  IF trig_count = 0 THEN
    RAISE EXCEPTION 'FAIL 013: no triggers reference the handle_* functions (would break signup/sync)';
  END IF;

  RAISE NOTICE 'PASS 013: 4 definer fns not client-executable; % trigger(s) still wired', trig_count;
END $$;
