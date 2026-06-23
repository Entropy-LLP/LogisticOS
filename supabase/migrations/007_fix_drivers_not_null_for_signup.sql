-- Migration 007: Make driver onboarding columns nullable
--
-- The handle_new_driver trigger (005) inserts only (user_id) into public.drivers
-- when a new driver signs up. truck_number and truck_type were NOT NULL with no
-- defaults, so every driver signup failed. Drivers fill these in during the
-- onboarding wizard — they must be nullable at row-creation time.

ALTER TABLE public.drivers
  ALTER COLUMN truck_number DROP NOT NULL,
  ALTER COLUMN truck_type   DROP NOT NULL;
