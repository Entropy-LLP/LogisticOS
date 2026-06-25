-- ============================================================
-- Migration 010: Fix SECURITY DEFINER views leaking data to anon
--
-- v_active_bookings_with_driver and v_trip_summary were created without
-- security_invoker, so they execute with the VIEW OWNER's privileges and
-- BYPASS RLS on the underlying tables (bookings, drivers, users, trips,
-- trip_locations). Because anon holds SELECT on the views, anyone with the
-- public anon key could read shipper contacts, driver names/phones, addresses,
-- and booking/trip data.
--
-- Fix: security_invoker = on makes each view run as the QUERYING role, so RLS
-- on the base tables applies. anon (no policies) then gets zero rows; the
-- service-role backend (bypasses RLS) is unaffected; authenticated users see
-- only what the base-table policies allow. No app/service code references these
-- views (verified), so behaviour for real consumers is unchanged.
--
-- Advisor: 0010_security_definer_view
-- ============================================================

ALTER VIEW public.v_active_bookings_with_driver SET (security_invoker = on);
ALTER VIEW public.v_trip_summary             SET (security_invoker = on);
