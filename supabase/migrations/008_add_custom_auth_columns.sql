-- Migration 008: Add columns required for custom email/password auth
--
-- The auth service issues its own JWTs (custom JWT, not Supabase Auth).
-- This migration adds the columns the auth routes need:
--   password_hash  — bcrypt hash for email+password login
--   avatar_url     — profile picture URL (Google OAuth, etc.)
--   email_verified — true after the user completes email OTP verification
--
-- All columns are nullable so existing rows are not affected.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS password_hash  text,
  ADD COLUMN IF NOT EXISTS avatar_url     text,
  ADD COLUMN IF NOT EXISTS email_verified boolean NOT NULL DEFAULT false;

-- Index for fast email lookups during login
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email
  ON public.users (email)
  WHERE email IS NOT NULL;
