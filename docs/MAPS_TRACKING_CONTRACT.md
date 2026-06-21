# Maps & Tracking — FROZEN Integration Contract (v1)

> **This is the single source of truth for the integration surface between `bt-tracking-service`, the driver app, and the shipper app.** Every session building any part of Maps & Tracking MUST read this first and build to it exactly. Do **not** change a frozen field name, path, or shape casually — see **§ Change protocol** at the bottom. Full design rationale lives in [MAPS_TRACKING_PLAN.md](MAPS_TRACKING_PLAN.md); dynamic decisions live in [MAPS_TRACKING_DECISIONS.md](MAPS_TRACKING_DECISIONS.md).

Contract version: **v1** · Frozen: **2026-06-18**

---

## 0. Conventions (frozen)

| Rule | Value |
|---|---|
| JSON field casing | **`snake_case` everywhere** (matches the existing `bt-booking-service` location API and the frontend `DriverLocation` type). This resolves the PLAN's flagged §3-vs-§5 naming drift — see decision **D-012**. |
| Response envelope | `{ "success": boolean, "data"?: T, "error"?: string, "code"?: string }` |
| Auth | `Authorization: Bearer <JWT>` on every endpoint. JWT payload `{ userId, role }`, roles `driver \| shipper \| admin`. |
| Service | `bt-tracking-service`, **port 3006**, gateway prefix **`/api/tracking/`** |
| Path style | **`:bookingId` path param** (the §3 canonical style — NOT the §5 query-string convenience form). |
| Coords | decimal lat/lng, no PostGIS. |

> **Frontend note:** the plan's §5 lists a query-string convenience form (`/api/tracking/route?bookingId=…`) with camelCase fields. **That form is NOT canonical.** Build `driver/src/lib/api.ts` and `shipper/src/lib/api.ts` against the endpoints + snake_case fields below.

---

## 1. Environment variables (frozen names)

| Name | Where | Restriction | Purpose |
|---|---|---|---|
| `NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY` | both frontends (public) | **HTTP-referrer restricted**, **Maps JS API only** | Draw map tiles in the browser. Safe to expose. |
| `NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID` | both frontends (public) | — | Map style ID for `AdvancedMarker`. Falls back to demo map id. |
| `GOOGLE_MAPS_SERVER_KEY` | `bt-tracking-service` only (**secret**) | **Routes API + Places API (New) only**, no referrer (server-to-server) | All priced Google calls. **Never shipped to the browser.** |
| `DIESEL_PRICE_INR` | `bt-tracking-service` | default `90` | Fallback diesel price for fuel estimate (editable per request). |
| `NEXT_PUBLIC_API_URL` | both frontends (existing) | — | Gateway base URL. Unchanged. |
| localStorage JWT keys (existing) | driver `bt_driver_token`, shipper `bt_token` | — | Unchanged. |

Legacy Google APIs (Directions, Distance Matrix, legacy Places) are **forbidden** — new GCP projects cannot enable them. Use **Routes API + Places API (New) + Maps JavaScript API** only.

---

## 2. Endpoints (frozen) — all under `/api/tracking/`

All require `Authorization: Bearer <JWT>`. Authz: caller must be the booking's shipper or the assigned driver.

| # | Method & Path | Role | Request | `data` response (snake_case) |
|---|---|---|---|---|
| 1 | `POST /api/tracking/route/:bookingId` | driver \| shipper | — (reads booking coords from DB) | `{ polyline, distance_m, static_duration_s, bounds, cached:false }` |
| 2 | `GET /api/tracking/route/:bookingId` | driver \| shipper | — | same shape, `cached:true` (computes if missing) |
| 3 | `GET /api/tracking/eta/:bookingId` | driver \| shipper | — | `{ eta_s, eta_text, remaining_m, traffic, computed_at, stale? }` |
| 4 | `GET /api/tracking/pumps/:bookingId` | driver \| shipper | `?limit=8` (default **8**) | `{ pumps: [{ name, brand?, lat, lng, address, distance_m }], cached }` |
| 5 | `POST /api/tracking/fuel/estimate` | driver \| shipper | `{ booking_id?, distance_km?, vehicle_class, laden?, diesel_price?, mileage_kmpl? }` | `{ distance_km, mileage_kmpl, litres, diesel_price, cost_inr, model_version }` |
| 6 | `POST /api/tracking/alerts` | driver | `{ booking_id, type, message?, lat?, lng? }` | `{ id, created_at }` |
| 7 | `GET /api/tracking/alerts/:bookingId` | driver \| shipper | — | `{ alerts: [{ id, type, message, lat, lng, acknowledged, created_at }] }` |
| 8 | `GET /api/tracking/track/:bookingId` | driver \| shipper | — | **the read-through** — see §3 |

`bounds` shape (frozen): `{ "ne_lat": number, "ne_lng": number, "sw_lat": number, "sw_lng": number }`.

- **Endpoint #4 default `limit=8`** (confirmed decision D-004 — overrides the plan's `?limit=10` example).
- **Endpoint #8 is the only call the shipper map makes** (once per 10s poll). Everything inside is cache-served except the live-location read.

---

## 3. `GET /api/tracking/track/:bookingId` — the read-through (frozen)

```jsonc
{
  "success": true,
  "data": {
    "booking_id": "uuid",
    "status": "in_transit",
    "location": { "lat": 19.07, "lng": 72.87, "heading": 210, "speed_kmh": 54, "updated_at": "ISO" },
    "route":    { "polyline": "encoded…", "distance_m": 142000, "bounds": { "ne_lat": 19.1, "ne_lng": 72.9, "sw_lat": 18.5, "sw_lng": 73.9 } },
    "eta":      { "eta_s": 7380, "eta_text": "2 hr 3 min", "remaining_m": 96000, "traffic": "moderate", "stale": false },
    "destination": { "lat": 18.52, "lng": 73.85 },
    "alerts":   [ { "id": "uuid", "type": "jam", "message": "Stuck near toll", "created_at": "ISO" } ]
  }
}
```

- If the driver is **offline** (Redis `loc:driver:*` key expired, TTL=30s): `location` is `null`, and `eta` is the last cached value with `"stale": true`.
- ETA is **traffic-aware (Pro tier)** per decision D-003.

---

## 4. Data ownership (frozen)

**`bt-tracking-service` WRITES (its own namespace only):**
- Redis: `trk:route:{bookingId}` (TTL 6h), `trk:eta:{bookingId}` (TTL 45s), `trk:pumps:{bookingId}` (TTL 6h), `trk:lock:{key}` (TTL 10s).
- Supabase (migration 009): `trip_routes`, `fuel_estimates`, `route_alerts`, `location_history` (all anchored on `booking_id`; service-role; RLS enabled, no policies).

**`bt-tracking-service` READS (owned by others — never writes):**
- Redis: `loc:driver:{driverId}`, `loc:booking-driver:{bookingId}` (written by `bt-booking-service` GPS ingestion).
- Supabase: `bookings` (source/dest lat/lng, status, shipper_id, driver_id), `drivers`, `vehicles`.

**Untouched (do NOT modify):** `bt-booking-service/src/routes/location.ts` and its `loc:*` Redis writes. GPS ingestion stays exactly as-is. Tracking-service is read-only on those keys.

**Existing endpoints the apps keep using (unchanged):**
- Driver pushes GPS: `POST /api/location/update` → `pushLocation()` in `driver/src/lib/api.ts`.
- Shipper reads live pos: `GET /api/location/booking/:id` → `getBookingLocation()`.

---

## 5. Change protocol (how to evolve a frozen contract)

A "frozen" field is not unchangeable — it's changeable only **deliberately and visibly**:

1. **Append a decision** to [MAPS_TRACKING_DECISIONS.md](MAPS_TRACKING_DECISIONS.md) (id, date, what changed, why, impact).
2. **Bump the contract version** at the top of this file (v1 → v2) and edit the affected row.
3. **Update both `api.ts` files** (driver + shipper) and the service in the SAME change so they can't drift.
4. If it's a genuine product fork (not a mechanical rename), **ask the user** before committing.

If you are a session and the contract here disagrees with the PLAN body, **this file wins** (the PLAN is design narrative; this is the agreed interface).
