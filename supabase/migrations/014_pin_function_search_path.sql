-- ============================================================
-- Migration 014: Pin search_path on app functions (function_search_path_mutable)
--
-- These 5 postgres-owned functions had no SET search_path, so they inherited the
-- caller's mutable search_path — a hardening risk (a caller could prepend a
-- schema to shadow object references). All of them already FULLY QUALIFY their
-- references (public.bookings / public.trips / public.drivers) and use only
-- pg_catalog builtins (now(), extract, coalesce), so `search_path = ''` (the most
-- secure value — forces qualification) is safe and changes no behaviour.
--
-- Advisor: 0011_function_search_path_mutable.
-- ============================================================

ALTER FUNCTION public.accept_booking(uuid, uuid)        SET search_path = '';
ALTER FUNCTION public.complete_trip(uuid, numeric)      SET search_path = '';
ALTER FUNCTION public.start_trip(uuid)                  SET search_path = '';
ALTER FUNCTION public.update_updated_at()               SET search_path = '';
ALTER FUNCTION public.update_updated_at_column()        SET search_path = '';
