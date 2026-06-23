-- Migration 006: Fix public.users schema for Supabase Auth triggers
--
-- Migration 005 added triggers that INSERT into public.users using columns
-- (auth_id, phone_number, email, full_name) and cast role to public.user_role,
-- but none of those were present in the table after migrations 001-004.
-- This migration adds the missing pieces so the signup trigger succeeds.

-- ── 1. Create user_role enum (used by the trigger cast in 005) ───────────────
DO $$ BEGIN
  CREATE TYPE public.user_role AS ENUM ('shipper', 'driver', 'fleet_owner', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 2. Add columns the trigger inserts into ──────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS auth_id   uuid UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS email     text,
  ADD COLUMN IF NOT EXISTS full_name text;

-- ── 3. Normalise phone column name ───────────────────────────────────────────
-- Migration 001 created the column as 'phone'; migrations 002 and the trigger
-- in 005 both reference it as 'phone_number'. Rename it if the old name exists
-- and the new name does not.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'phone'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'phone_number'
  ) THEN
    ALTER TABLE public.users RENAME COLUMN phone TO phone_number;
  END IF;
END $$;

-- ── 4. Make phone_number nullable ────────────────────────────────────────────
-- Email and Google sign-ups have no phone number; the NOT NULL constraint from
-- migration 001 would fail the trigger for every non-phone signup.
ALTER TABLE public.users ALTER COLUMN phone_number DROP NOT NULL;

-- ── 5. Drop the stale unique index on the old 'phone' column if it survived ──
DROP INDEX IF EXISTS idx_users_phone;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_number
  ON public.users (phone_number)
  WHERE phone_number IS NOT NULL;

-- ── 6. Add index on auth_id for fast JWT → user lookups ──────────────────────
CREATE INDEX IF NOT EXISTS idx_users_auth_id ON public.users (auth_id);
