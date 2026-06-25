# Supabase Security Advisors — remediation log

Project: **bharattruck-mvp** (`rxbdzbcndpzznvqcbimg`). Tracks each Supabase
security-advisor finding and how it was resolved. Re-run with the Supabase MCP
`get_advisors(type: security)` or Dashboard → Advisors. Tests live in
`supabase/tests/`; run them as the service-role/owner connection
(`psql "$DATABASE_URL" -f supabase/tests/<file>.sql`).

> Architecture note: all app data access goes through the **service-role
> backend** (which bypasses RLS). The frontends do **not** query data tables via
> the Supabase client (shipper/driver don't use it; bt-ops-web uses it only for
> auth). So "RLS enabled, no policy" = deny-by-default = secure for this design.

---

## Fixed

### `security_definer_view` (ERROR) — `v_active_bookings_with_driver`, `v_trip_summary`
Views were SECURITY DEFINER (default), bypassing RLS while readable by `anon` →
leaked shipper/driver PII + booking/trip data. **Fix:** `security_invoker = on`
(migration 010). anon now reads 0 rows; service-role unaffected.
Test: `supabase/tests/010_secure_security_definer_views_test.sql`.

### Recursive RLS policy on `users` (runtime bug, surfaced by 010)
*"Admins can view all users"* queried `users` from a policy on `users` →
infinite recursion (42P17). Unused (no anon/authenticated data queries).
**Fix:** dropped it (migration 011); own-profile policies remain. Reintroduce
admin RLS via a SECURITY DEFINER `is_admin()` helper if ops-web ever queries
data directly. Test: `supabase/tests/011_fix_users_rls_recursion_test.sql`.

---

## Residual (cannot fix from the `postgres` role)

### `rls_disabled_in_public` (ERROR) — `spatial_ref_sys`
PostGIS reference table (coordinate-system definitions). RLS is disabled and
`anon`/`authenticated` hold full grants incl. TRUNCATE.

- **Data risk: low.** Contents are non-sensitive public reference data (identical
  in every PostGIS install). The real risk is *integrity/availability* — someone
  with the anon key could TRUNCATE it and break coordinate transforms; it is
  re-creatable from PostGIS.
- **Why not auto-fixed:** the table is owned by `supabase_admin`; the `postgres`
  role used for migrations cannot `ALTER` it or `REVOKE` its grants
  (`ERROR 42501 must be owner`). Verified.
- **Self-healing migration:** `012_secure_spatial_ref_sys.sql` attempts the
  lock-down (enable RLS + read-only policy + revoke writes) and no-ops with a
  NOTICE when it lacks ownership — so it applies automatically if ever run by a
  privileged role.
- **Manual remediation (recommended):** run the body of migration 012 as
  `supabase_admin` (e.g. via the Dashboard SQL editor if it has owner rights) or
  open a Supabase support request to enable RLS on `spatial_ref_sys`. Verify with
  `supabase/tests/012_secure_spatial_ref_sys_test.sql`.
