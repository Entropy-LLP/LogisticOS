-- ============================================================
-- Migration 004: Driver Track Complete Schema
-- Adds all tables required for the full Driver Track MVP:
--   2.1 Onboarding, 2.2 Load Discovery, 2.3 Bidding,
--   2.4 Trip Execution, 2.5 Payments, 2.6 Tools, 2.7 Settings
--
-- Applied to remote Supabase on 2026-06-03.
-- ============================================================

-- ─── Ensure update_updated_at trigger function exists ────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2.1  ONBOARDING & IDENTITY
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Extend drivers table ────────────────────────────────────────────────────
ALTER TABLE drivers
  ADD COLUMN IF NOT EXISTS photo_url          text,
  ADD COLUMN IF NOT EXISTS languages          text[]         DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS home_base_city     varchar(100),
  ADD COLUMN IF NOT EXISTS home_base_lat      decimal(10,8),
  ADD COLUMN IF NOT EXISTS home_base_lng      decimal(11,8),
  ADD COLUMN IF NOT EXISTS verification_badge text           NOT NULL DEFAULT 'pending'
    CHECK (verification_badge IN ('pending', 'verified', 'premium'));

-- ─── Vehicles ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vehicles (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id       uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  rc_number       varchar(20) NOT NULL UNIQUE,
  rc_storage_path text,
  vehicle_photos  text[] DEFAULT '{}',
  capacity_tons   decimal(6,2),
  body_type       text CHECK (body_type IN (
                    'open','closed','container','flatbed','tanker','refrigerated'
                  )),
  axle_config     text CHECK (axle_config IN (
                    '4x2','6x2','6x4','8x4','10x2'
                  )),
  maker_model     varchar(100),
  fuel_type       varchar(20),
  rc_status       text NOT NULL DEFAULT 'pending'
                    CHECK (rc_status IN ('pending','verified','rejected')),
  rc_expiry       date,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vehicles_driver_id ON vehicles(driver_id);

CREATE TRIGGER vehicles_updated_at
  BEFORE UPDATE ON vehicles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── Driver Licenses ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS driver_licenses (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id       uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  dl_number       varchar(30) NOT NULL UNIQUE,
  dl_storage_path text,
  vehicle_classes text[] DEFAULT '{}',
  expiry_date     date,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','verified','rejected')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (driver_id)
);

CREATE TRIGGER driver_licenses_updated_at
  BEFORE UPDATE ON driver_licenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── Driver Insurance ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS driver_insurance (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id       uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  vehicle_id      uuid NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  policy_number   varchar(50),
  provider        varchar(100),
  storage_path    text,
  expiry_date     date,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','verified','rejected')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (vehicle_id, policy_number)
);

CREATE INDEX IF NOT EXISTS idx_driver_insurance_driver_id ON driver_insurance(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_insurance_vehicle_id ON driver_insurance(vehicle_id);

CREATE TRIGGER driver_insurance_updated_at
  BEFORE UPDATE ON driver_insurance
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── Bank Accounts ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bank_accounts (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  account_number_enc   text NOT NULL,
  account_number_last4 varchar(4) NOT NULL,
  ifsc                 varchar(11) NOT NULL,
  bank_name            varchar(100),
  account_holder_name  varchar(100) NOT NULL,
  is_primary           boolean NOT NULL DEFAULT true,
  verification_status  text NOT NULL DEFAULT 'pending'
                         CHECK (verification_status IN ('pending','verified','rejected')),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bank_accounts_user_id ON bank_accounts(user_id);

CREATE TRIGGER bank_accounts_updated_at
  BEFORE UPDATE ON bank_accounts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── KYC Documents ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS kyc_documents (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  doc_type         text NOT NULL CHECK (doc_type IN ('aadhaar','pan','license','rc','permit')),
  storage_path     text NOT NULL,
  status           text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','approved','rejected')),
  rejection_reason text,
  uploaded_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_kyc_documents_user_id ON kyc_documents(user_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2.2  LOAD DISCOVERY
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Saved Lanes ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS saved_lanes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id        uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  origin_city      varchar(100),
  origin_lat       decimal(10,8),
  origin_lng       decimal(11,8),
  origin_radius_km integer DEFAULT 50,
  destination_city varchar(100),
  dest_lat         decimal(10,8),
  dest_lng         decimal(11,8),
  dest_radius_km   integer DEFAULT 50,
  notify_enabled   boolean NOT NULL DEFAULT true,
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_saved_lanes_driver_id ON saved_lanes(driver_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2.3  BIDDING & BOOKING
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Booking Responses (decline / report) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS booking_responses (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id      uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  driver_id       uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  action          text NOT NULL CHECK (action IN ('accepted','declined','reported')),
  decline_reason  text,
  report_reason   text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (booking_id, driver_id)
);

CREATE INDEX IF NOT EXISTS idx_booking_responses_booking_id ON booking_responses(booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_responses_driver_id ON booking_responses(driver_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2.4  TRIP EXECUTION
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Trip Events (granular status timeline) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS trip_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id     uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  event_type  text NOT NULL CHECK (event_type IN (
                'arrived_pickup','loading','loaded','in_transit',
                'arrived_delivery','delivered','cancelled'
              )),
  latitude    decimal(10,8),
  longitude   decimal(11,8),
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trip_events_trip_id ON trip_events(trip_id);

-- ─── Trip Documents (e-way bill photos, LR, weighbridge, POD) ───────────────
CREATE TABLE IF NOT EXISTS trip_documents (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id      uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  booking_id   uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  doc_type     text NOT NULL CHECK (doc_type IN (
                 'eway_bill_photo','lr_copy','weighbridge_slip',
                 'pod_photo','pod_signature','other'
               )),
  storage_path text NOT NULL,
  metadata     jsonb,
  uploaded_by  uuid NOT NULL REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trip_documents_trip_id ON trip_documents(trip_id);
CREATE INDEX IF NOT EXISTS idx_trip_documents_booking_id ON trip_documents(booking_id);

-- ─── Messages (in-app chat per booking) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  sender_id      uuid NOT NULL REFERENCES users(id),
  content        text,
  message_type   text NOT NULL DEFAULT 'text'
                   CHECK (message_type IN ('text','image','location','system')),
  attachment_url text,
  is_read        boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_booking_id ON messages(booking_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2.5  EARNINGS & PAYMENTS
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS payments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id      uuid NOT NULL REFERENCES bookings(id),
  payer_id        uuid NOT NULL REFERENCES users(id),
  payee_id        uuid NOT NULL REFERENCES users(id),
  amount          decimal(12,2) NOT NULL CHECK (amount > 0),
  platform_fee    decimal(12,2) DEFAULT 0,
  tds_amount      decimal(12,2) DEFAULT 0,
  net_amount      decimal(12,2) NOT NULL CHECK (net_amount >= 0),
  payment_method  text CHECK (payment_method IN ('razorpay','upi','bank_transfer','cash')),
  gateway_txn_id  text,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','captured','settled','failed','refunded')),
  settled_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_booking_id ON payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_payments_payee_id ON payments(payee_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);

CREATE TRIGGER payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2.6  DRIVER TOOLS
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Trip Expenses ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS trip_expenses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id    uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  trip_id      uuid REFERENCES trips(id) ON DELETE SET NULL,
  category     text NOT NULL CHECK (category IN (
                 'fuel','toll','food','maintenance','parking','other'
               )),
  amount       decimal(10,2) NOT NULL CHECK (amount > 0),
  description  text,
  receipt_path text,
  expense_date date NOT NULL DEFAULT CURRENT_DATE,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trip_expenses_driver_id ON trip_expenses(driver_id);
CREATE INDEX IF NOT EXISTS idx_trip_expenses_trip_id ON trip_expenses(trip_id);

-- ─── Driver Reviews ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS driver_reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  uuid NOT NULL REFERENCES bookings(id) UNIQUE,
  driver_id   uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES users(id),
  rating      integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment     text,
  tags        text[] DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_driver_reviews_driver_id ON driver_reviews(driver_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2.7  ACCOUNT & SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── User Settings ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_settings (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  preferred_language     varchar(10) DEFAULT 'hi',
  notify_new_loads       boolean NOT NULL DEFAULT true,
  notify_booking_updates boolean NOT NULL DEFAULT true,
  notify_payments        boolean NOT NULL DEFAULT true,
  notify_documents       boolean NOT NULL DEFAULT true,
  notify_promotions      boolean NOT NULL DEFAULT false,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER user_settings_updated_at
  BEFORE UPDATE ON user_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── Support Tickets ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS support_tickets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  booking_id  uuid REFERENCES bookings(id),
  category    text NOT NULL CHECK (category IN (
                'payment_dispute','booking_issue','document_help','app_bug','other'
              )),
  subject     text NOT NULL,
  description text NOT NULL,
  status      text NOT NULL DEFAULT 'open'
                CHECK (status IN ('open','in_progress','resolved','closed')),
  priority    text NOT NULL DEFAULT 'medium'
                CHECK (priority IN ('low','medium','high')),
  resolved_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id ON support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status);

CREATE TRIGGER support_tickets_updated_at
  BEFORE UPDATE ON support_tickets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════════════

-- New tables
ALTER TABLE vehicles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_licenses   ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_insurance  ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_accounts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc_documents     ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_lanes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_documents    ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_expenses     ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_reviews    ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings     ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets   ENABLE ROW LEVEL SECURITY;

-- Security fix: existing tables that had RLS disabled
ALTER TABLE quotes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE negotiations  ENABLE ROW LEVEL SECURITY;
