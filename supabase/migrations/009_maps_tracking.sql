-- ============================================================
-- Migration 009: Maps & Tracking
-- Owned exclusively by bt-tracking-service (service-role writes).
-- All tables anchored on booking_id. RLS enabled, NO policies
-- (service-role bypasses RLS; no direct client access).
-- See docs/MAPS_TRACKING_CONTRACT.md §4 (data ownership).
-- ============================================================

-- update_updated_at() trigger fn already exists (migration 004); kept idempotent.
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ─── trip_routes ─── cached Routes API result, one per booking ───────────────
CREATE TABLE IF NOT EXISTS trip_routes (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id         uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  polyline           text NOT NULL,                 -- Routes API encoded polyline
  distance_m         integer NOT NULL,
  static_duration_s  integer NOT NULL,
  ne_lat             double precision NOT NULL,      -- viewport bounds
  ne_lng             double precision NOT NULL,
  sw_lat             double precision NOT NULL,
  sw_lng             double precision NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trip_routes_booking_id ON trip_routes(booking_id);

CREATE TRIGGER trip_routes_updated_at
  BEFORE UPDATE ON trip_routes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── fuel_estimates ─── litres/₹ estimates (Phase 4) ─────────────────────────
CREATE TABLE IF NOT EXISTS fuel_estimates (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid REFERENCES bookings(id) ON DELETE CASCADE,  -- optional (ad-hoc estimates allowed)
  distance_km    double precision NOT NULL,
  mileage_kmpl   double precision NOT NULL,
  litres         double precision NOT NULL,
  diesel_price   double precision NOT NULL,
  cost_inr       double precision NOT NULL,
  vehicle_class  text,
  laden          boolean,
  model_version  text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fuel_estimates_booking_id ON fuel_estimates(booking_id);

-- ─── route_alerts ─── off-route / idle / geofence / eta-slip (Phase 5) ───────
CREATE TABLE IF NOT EXISTS route_alerts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id    uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  type          text NOT NULL,
  message       text,
  lat           double precision,
  lng           double precision,
  acknowledged  boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_route_alerts_booking_id ON route_alerts(booking_id, created_at DESC);

-- ─── location_history ─── throttled breadcrumb trail (D-001, Phase 5) ────────
CREATE TABLE IF NOT EXISTS location_history (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id   uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  driver_id    uuid,
  lat          double precision NOT NULL,
  lng          double precision NOT NULL,
  heading      double precision,
  speed_kmh    double precision,
  recorded_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_location_history_booking_recorded
  ON location_history(booking_id, recorded_at DESC);

-- ─── RLS: enabled, no policies (service-role only) ───────────────────────────
ALTER TABLE trip_routes      ENABLE ROW LEVEL SECURITY;
ALTER TABLE fuel_estimates   ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_alerts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_history ENABLE ROW LEVEL SECURITY;
