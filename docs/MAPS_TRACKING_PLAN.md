# BharatTruck — Maps & Tracking Feature Plan

> Sprint 3-4 milestone. A complete, dependency-ordered plan for a **non-expert solo developer** to add live maps, driver navigation, petrol-pump/fuel insights, and route alerts to BharatTruck — built on the existing LogisticOS microservice infra, optimized for the **easiest viable path** and **~₹0/month** at pilot scale.

---

## TL;DR for a solo dev

- **What we're building:** turn the two existing text-only "tracking" panels into real Google Maps — a **shipper live-tracking map** and a **driver navigation view** (Phase 1, together) — then layer on **petrol pumps along route, a fuel-cost estimate, and route alerts**.
- **The stack decision:** **Google Maps Platform** (chosen for ease over cost) + a **new `bt-tracking-service` (port 3006)** that proxies Google's Routes API + Places API (New) behind a secret server key with aggressive Redis caching. The browser only ever draws map tiles with a separate, referrer-locked key. Navigation is a **deep-link handoff** to the phone's Google Maps app — no in-app turn-by-turn to build.
- **Why it's cheap/easy:** the GPS pipeline (driver streams GPS, shipper polls every 10s) **already works** — the *only* missing piece is the map layer. Google's 2025 per-SKU free caps + Redis caching keep a ~20-user pilot at **$0**. No GPS rebuild, no PostGIS, no new auth, no extra Google SDK (plain `fetch`).
- **The very first action:** create a Google Cloud project, enable exactly three APIs (Maps JavaScript, Routes, Places New), make two restricted keys, and set per-API quota caps — see **Phase 0** / **§7**. Do not write a line of map code before the keys are restricted and capped.

---

> **✅ Decisions confirmed (2026-06-18):** traffic-aware ETA (Pro tier) · persist `location_history` breadcrumbs · minimal PWA manifest now · prefill-mileage fuel with editable diesel price · 10s polling for pilot · top-8 petrol pumps · alert thresholds 500 m / 15 min / 2 km · copy the map component per app. Full list + rationale in **§10**.
>
> **🔁 Built across sessions (one phase per session).** The integration surface is frozen in **[MAPS_TRACKING_CONTRACT.md](MAPS_TRACKING_CONTRACT.md)**; every dynamic decision is logged append-only in **[MAPS_TRACKING_DECISIONS.md](MAPS_TRACKING_DECISIONS.md)**; the per-phase kickoff prompts + session ritual are in **[MAPS_TRACKING_SESSIONS.md](MAPS_TRACKING_SESSIONS.md)**. Any session reads CONTRACT + DECISIONS first and appends decisions last (enforced by the repo `CLAUDE.md`).

## 1. What already exists vs what's missing

The reassuring part: **almost everything is already built.** You are adding a map layer and one stateless proxy service — nothing in the GPS path changes.

| Concern | Status | Where |
|---|---|---|
| Driver streams GPS | ✅ **Exists** | `driver/src/app/(app)/bookings/[id]/page.tsx` — `navigator.geolocation.watchPosition()` → `pushLocation()` in `driver/src/lib/api.ts` |
| GPS ingestion + Redis store (TTL 30s) | ✅ **Exists** | `bt-booking-service/src/routes/location.ts` — `POST /location/update`, keys `loc:driver:{driverId}`, `loc:booking-driver:{bookingId}`, `loc:driver-booking:{driverId}` |
| Shipper reads live location (polls 10s) | ✅ **Exists** | `shipper/src/app/bookings/[id]/page.tsx` → `getBookingLocation()`; gateway maps `/api/location/` → booking:3002 |
| Auth (JWT Bearer `{userId, role}`) | ✅ **Exists** | `bt-booking-service/src/plugins/auth.ts` (copy verbatim) |
| Booking coords (source/dest lat/lng), status lifecycle | ✅ **Exists** | `bookings` table |
| **The actual map** (both apps render raw lat/lng as TEXT) | ❌ **MISSING** | this plan |
| **Routing / ETA / petrol-pump / fuel / alerts logic** | ❌ **MISSING** | new `bt-tracking-service` |
| Map library, Google keys, PWA manifest | ❌ **MISSING** | this plan |

> **The only two missing pieces are (1) the map UI layer and (2) the new `bt-tracking-service`.** The working GPS ingestion in `bt-booking-service` is **left untouched** — the new service is read-only on its Redis keys.

---

## 2. Architecture overview

`bt-tracking-service` is a **stateless Google proxy + cache**. It never ingests GPS (that stays in `bt-booking-service`); it only *reads* live location from the shared Redis and wraps Google Routes/Places behind a server-side key with aggressive Redis caching so a 20-user pilot stays at ~$0.

```
bt-tracking-service  (NEW, port 3006, gateway /api/tracking/)
  ├─► Redis (SAME instance as booking-service)
  │     READS  loc:driver:{driverId}, loc:booking-driver:{bookingId}   (booking writes these, TTL 30s)
  │     WRITES trk:route:*, trk:eta:*, trk:pumps:*, trk:lock:*         (its own namespace)
  ├─► Supabase (service-role)
  │     READS  bookings (source_lat/lng, dest_lat/lng, status, shipper_id, driver_id) for authz + route input
  │     WRITES route_alerts, trip_routes, fuel_estimates (new tables, migration 009)
  └─► Google Maps Platform (Routes API + Places API New) — SERVER key, cached
```

**Sequence — GPS in (unchanged), shipper map out:**

```
DRIVER APP            BOOKING-SVC           REDIS (shared)         TRACKING-SVC           GOOGLE              SHIPPER APP
   │                      │                      │                     │                    │                    │
   │ watchPosition()      │                      │                     │                    │                    │
   │ POST /api/location/update                   │                     │                    │                    │
   │─────────────────────►│ SET loc:driver:{d}   │                     │                    │                    │
   │                      │ SET loc:booking-driver:{b}  ──TTL 30s──►│   │                    │                    │
   │                      │                      │                     │                    │                    │
   │  (repeats every few seconds while in_transit)                    │                    │                    │
   │                      │                      │                     │                    │  opens map         │
   │                      │                      │                     │  GET /api/tracking/track/{bookingId}    │
   │                      │                      │                     │◄────────────────────────────────────────│
   │                      │                      │  GET loc:booking-driver:{b} ► loc:driver:{d}                  │
   │                      │                      │◄────────────────────│  (live pos, fresh)                      │
   │                      │                      │  GET trk:route:{b} ─► HIT (cached 6h)     │                   │
   │                      │                      │  GET trk:eta:{b} ──► MISS                 │                   │
   │                      │                      │                     │ Routes API (TRAFFIC_AWARE, pos→dest)    │
   │                      │                      │                     │───────────────────►│                   │
   │                      │                      │                     │◄───────────────────│ duration (traffic) │
   │                      │                      │  SET trk:eta:{b} EX 45 ◄─────────────────│                   │
   │                      │                      │                     │  {location,route,eta,alerts}            │
   │                      │                      │                     │────────────────────────────────────────►│ renders
   │                      │                      │                     │                    │       (Maps-JS browser key draws tiles)
   │  next poll @10s: route+eta now cache HITs → ZERO Google calls until eta TTL (45s) lapses                    │
```

**Net effect:** the driver writes GPS (unchanged); the shipper's repeated polling is absorbed by Redis — Google is touched **once per trip** for the route/pumps and **at most ~1×/45s** for traffic ETA, keeping a 20-user pilot inside the free SKU caps (~$0).

**Key & port conventions used throughout this document (harmonized):**

| Thing | Value |
|---|---|
| New service | `bt-tracking-service`, port **3006**, gateway route `/api/tracking/` |
| **Browser** Maps key (public, in both frontends) | `NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY` |
| Map ID (for AdvancedMarker) | `NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID` |
| **Server** Maps key (secret, tracking-service only) | `GOOGLE_MAPS_SERVER_KEY` |
| Driver JWT in localStorage | `bt_driver_token` |
| Shipper JWT in localStorage | `bt_token` |
| Response convention everywhere | `{ success, data?, error?, code? }` |

---

## 3. Backend — the `bt-tracking-service`

A new Node 20 + TypeScript + Fastify microservice on **port 3006**, exposed via gateway at `/api/tracking/...`. It is a **stateless Google proxy + cache**: it never ingests GPS (that stays in `bt-booking-service`), it only *reads* live location from the shared Redis and wraps Google Routes/Places behind a server-side key with aggressive Redis caching so a 20-user pilot stays at ~$0.

### 3.1 Folder layout (mirrors the existing service recipe)

```
bt-tracking-service/
├── Dockerfile
├── .dockerignore
├── package.json
├── tsconfig.json
├── env.example
└── src/
    ├── server.ts                 # Fastify bootstrap, registers plugins + routes, GET /health
    ├── plugins/
    │   ├── auth.ts               # COPY verbatim from bt-booking-service/src/plugins/auth.ts
    │   └── redis.ts              # ioredis client (shares the SAME Redis as booking-service)
    ├── lib/
    │   ├── redis.ts             # key builders + TTL constants (route/eta/pumps/locks)
    │   ├── supabase.ts          # service-role client (COPY from auth-service/src/plugins/supabase.ts)
    │   ├── google.ts            # the ONLY place that calls Google. fieldmasks + fetch + cache
    │   ├── booking.ts          # read-through to booking-service: getBookingLocation(), getBooking()
    │   ├── fuel.ts             # pure fn: mileage tables + diesel price -> litres + Rs
    │   ├── geo.ts              # haversine, distance-to-route, geofence helpers
    │   └── types.ts            # TrackingError, response types (mirror BookingError convention)
    └── routes/
        ├── route.ts            # POST /route/:bookingId, GET /route/:bookingId
        ├── eta.ts             # GET /eta/:bookingId
        ├── pumps.ts           # GET /pumps/:bookingId
        ├── fuel.ts            # POST /fuel/estimate
        ├── alerts.ts          # POST /alerts, GET /alerts/:bookingId
        └── track.ts           # GET /track/:bookingId  <-- shipper read-through (ONE call)
```

**`package.json`** (copy the booking-service one, trim to this):

```json
{
  "name": "bt-tracking-service",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/server.js",
    "test": "vitest run"
  },
  "dependencies": {
    "@fastify/cors": "^10.0.0",
    "@supabase/supabase-js": "^2.45.0",
    "fastify": "^5.0.0",
    "fastify-plugin": "^5.0.0",
    "ioredis": "^5.4.1",
    "jsonwebtoken": "^9.0.2",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/jsonwebtoken": "^9.0.6",
    "@types/node": "^20.14.0",
    "tsx": "^4.16.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0"
  }
}
```

> **No Google SDK.** Routes API + Places API (New) are plain REST `POST` calls over `fetch` (built into Node 20). Zero extra deps = nothing to break.

### 3.2 Complete endpoint list (all under `/tracking`, exposed as `/api/tracking/...`)

All routes require `Authorization: Bearer <JWT>` (auth plugin). Response convention everywhere: `{ success, data?, error?, code? }`.

| # | Method & Path | Role | Request body / params | Response `data` | Purpose |
|---|---|---|---|---|---|
| 1 | `POST /route/:bookingId` | driver \| shipper (on booking) | none (reads booking coords from DB) | `{ polyline, distance_m, static_duration_s, bounds, cached:false }` | Compute route once via **Routes API**, cache for trip lifetime. |
| 2 | `GET /route/:bookingId` | driver \| shipper | param | same as above, `cached:true` | Return the cached route; computes if missing. |
| 3 | `GET /eta/:bookingId` | driver \| shipper | param | `{ eta_s, eta_text, remaining_m, traffic, computed_at }` | Traffic-aware ETA from **live driver pos → dest**, cached 45s. |
| 4 | `GET /pumps/:bookingId` | driver \| shipper | param, `?limit=10` | `{ pumps:[{name,lat,lng,address,distance_m}], cached }` | Petrol pumps along the route (**Places New, Search-Along-Route**), cached per route. |
| 5 | `POST /fuel/estimate` | driver \| shipper | `{ bookingId?, distance_km?, vehicle_class, laden?, diesel_price?, mileage_kmpl? }` | `{ distance_km, mileage_kmpl, litres, diesel_price, cost_inr }` | Pure-math fuel estimate (no Google call). |
| 6 | `POST /alerts` | driver | `{ bookingId, type, message, lat?, lng? }` | `{ id, created_at }` | Driver raises a route alert (breakdown, jam, detour). |
| 7 | `GET /alerts/:bookingId` | driver \| shipper | param | `{ alerts:[...] }` | List alerts for a booking. |
| 8 | **`GET /track/:bookingId`** | driver \| shipper | param | `{ location, route, eta, pumps?, alerts }` | **THE shipper read-through** — one call returns live pos + route + ETA + alerts. |

**Endpoint #8 is the one the frontend hits.** The shipper map makes exactly **one** request every 10s; everything inside is cache-served except a fresh live-location read.

> **Note on URL style:** the service is the single source of truth for these paths. Endpoints 1-8 above are the canonical contract. The Frontend section (§5) and the simpler Roadmap snippets (§8) use query-string variants (`/tracking/route?bookingId=…`) for read-only convenience; either style is fine as long as the service exposes both — pick one when you implement and keep `api.ts` consistent with it. The `:bookingId` param style is recommended (matches `location.ts`).

#### `GET /track/:bookingId` response shape (the important one)

```jsonc
{
  "success": true,
  "data": {
    "booking_id": "uuid",
    "status": "in_transit",
    "location": { "lat": 19.07, "lng": 72.87, "heading": 210, "speed_kmh": 54, "updated_at": "..." },
    "route": { "polyline": "encoded…", "distance_m": 142000, "bounds": {…} },
    "eta": { "eta_s": 7380, "eta_text": "2 hr 3 min", "remaining_m": 96000, "traffic": "moderate" },
    "destination": { "lat": 18.52, "lng": 73.85 },
    "alerts": [ { "type": "jam", "message": "Stuck near toll", "created_at": "…" } ]
  }
}
```

If the driver is offline (Redis location key expired, TTL=30s), `location` is `null` and `eta` falls back to the last cached value with `"stale": true`.

### 3.3 Server-side Google proxy + Redis cache design

**Why proxy:** the Google **server key never leaves the backend**. A browser-exposed key calling the priced Routes/Places SKUs is a financial liability — anyone can scrape it and burn your quota. The Maps-JS *browser* key (HTTP-referrer-restricted) only draws map tiles; **all priced calls (Routes, Places) go through this service.** Caching in Redis collapses N polls into 1 Google call.

#### Redis key scheme + TTLs

```ts
// src/lib/redis.ts  (shared Redis instance with booking-service)
export const routeKey  = (b: string) => `trk:route:${b}`    // TTL 6h (trip lifetime)
export const etaKey    = (b: string) => `trk:eta:${b}`      // TTL 45s
export const pumpsKey  = (b: string) => `trk:pumps:${b}`    // TTL 6h (tied to route)
export const lockKey   = (k: string) => `trk:lock:${k}`     // TTL 10s (stampede guard)

export const ROUTE_TTL = 60 * 60 * 6   // 21600s
export const ETA_TTL   = 45
export const PUMPS_TTL = 60 * 60 * 6
```

| Cache | TTL | Naive cost trap → how cache prevents it |
|---|---|---|
| `trk:route:{b}` | 6h | Route only changes if origin/dest change → compute **once per trip**. Without cache, every map open = 1 Routes call. |
| `trk:eta:{b}` | 45s | Shipper polls every 10s. **Without** the 45s cache that's 6 traffic-aware (Pro tier, ~2×) calls/min/trip. With it: ~1.3 calls/min → caps absorb it. |
| `trk:pumps:{b}` | 6h | Pumps don't move. Cache keyed to the route → one Places call per trip, not per open. |
| `trk:lock:{k}` | 10s | **Cache-stampede guard:** on a miss, `SET NX` the lock before calling Google; concurrent requests wait/serve-stale instead of firing parallel Google calls. |

**Read-through pattern (every Google call):**

```ts
// src/lib/google.ts
async function cached<T>(key: string, ttl: number, fetcher: () => Promise<T>): Promise<{v:T; cached:boolean}> {
  const hit = await redis.get(key)
  if (hit) return { v: JSON.parse(hit), cached: true }
  // stampede guard: only one caller fetches from Google
  const got = await redis.set(lockKey(key), '1', 'EX', 10, 'NX')
  if (!got) { await sleep(300); const r = await redis.get(key); if (r) return { v: JSON.parse(r), cached: true } }
  const v = await fetcher()
  await redis.set(key, JSON.stringify(v), 'EX', ttl)
  return { v, cached: false }
}
```

#### Field masks (REQUIRED — request errors without them; they also pin the SKU/price)

```ts
// Routes API — Essentials tier (traffic-UNAWARE) for the stored route geometry:
'X-Goog-FieldMask': 'routes.polyline.encodedPolyline,routes.distanceMeters,routes.staticDuration,routes.viewport'

// Routes API — Pro tier (traffic-AWARE) ONLY for live ETA (eta endpoint):
'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters'
//  body includes:  "routingPreference": "TRAFFIC_AWARE", "travelMode": "DRIVE"

// Places API (New) Text Search — Search-Along-Route, cheap SKU:
'X-Goog-FieldMask': 'places.displayName,places.location,places.formattedAddress'
//  body includes:  "textQuery": "petrol pump",
//                  "searchAlongRouteParameters": { "polyline": { "encodedPolyline": "<route polyline>" } }
```

> **Quota trap flagged:** the *route* endpoint must use `staticDuration` (Essentials). Only `/eta` uses `TRAFFIC_AWARE` + `routes.duration` (Pro, ~2×). Mixing them up silently doubles cost. Pumps reuse the **already-cached route polyline** — never recompute a route just to find pumps. (**Confirmed 2026-06-18:** `/eta` runs **`TRAFFIC_AWARE` (Pro tier)** for accurate, traffic-adjusted ETAs; the cached *route* stays `staticDuration`/Essentials. Watch the Pro free cap — widen the ETA cache TTL or fall back to `TRAFFIC_UNAWARE` if it's ever approached.)

**Hard cost cap (config, not code):** restrict `GOOGLE_MAPS_SERVER_KEY` to *Routes API + Places API* only, no referrer (server-to-server); restrict the browser key by HTTP referrer + *Maps JS only*; set **per-API quota limits** in Cloud Console (a billing budget only alerts, it does not stop spend). See §7 for the exact steps.

### 3.4 How it talks to the other pieces

**What stays in booking-service (untouched):** raw GPS ingestion — `POST /location/update` and the `loc:*` Redis writes. Tracking-service is **read-only** on those keys.

**Live location read** (avoid a second HTTP hop — read Redis directly, it's the same instance):

```ts
// src/lib/booking.ts
import { redis } from './redis.js'
const driverLocationKey = (d: string) => `loc:driver:${d}`        // booking-service's key
const bookingDriverKey  = (b: string) => `loc:booking-driver:${b}`

export async function getBookingLocation(bookingId: string) {
  const driverId = await redis.get(bookingDriverKey(bookingId))   // booking-service set this
  if (!driverId) return null
  const raw = await redis.get(driverLocationKey(driverId))
  return raw ? JSON.parse(raw) : null
}
```

> Authz mirrors `location.ts`: shipper may only read a booking where `bookings.shipper_id = req.user.userId`; driver only their own assigned booking. Reuse the same Supabase check.

### 3.5 Gateway + infra wiring

**`bt-gateway/nginx.conf.template`** — add the comment line and a new location block (mirror `/api/location/`):

```nginx
#   /api/tracking/   -> TRACKING_SERVICE_URL (routes, ETA, pumps, fuel, alerts)
```
```nginx
    location /api/tracking/ {
      limit_req zone=api_zone burst=30 nodelay;
      set $tracking_upstream ${TRACKING_SERVICE_URL};
      rewrite ^/api/tracking/(.*) /tracking/$1 break;
      proxy_set_header Host ${TRACKING_SERVICE_HOST};
      proxy_pass $tracking_upstream;
    }
```

**`bt-gateway/docker-entrypoint.sh`** — add the host extraction + both vars to `envsubst`:

```sh
export TRACKING_SERVICE_HOST=$(echo "$TRACKING_SERVICE_URL" | sed 's|https\?://||' | sed 's|/.*||')
```
```sh
envsubst '${DNS_RESOLVER} ${AUTH_SERVICE_URL} ${BOOKING_SERVICE_URL} ${PRICING_SERVICE_URL} ${PAYMENT_SERVICE_URL} ${CARGO_SERVICE_URL} ${TRACKING_SERVICE_URL} ${AUTH_SERVICE_HOST} ${BOOKING_SERVICE_HOST} ${PRICING_SERVICE_HOST} ${PAYMENT_SERVICE_HOST} ${CARGO_SERVICE_HOST} ${TRACKING_SERVICE_HOST} ${CORS_ALLOWED_ORIGINS}' \
  < /etc/nginx/nginx.conf.template \
  > /etc/nginx/nginx.conf
```

**`docker-compose.yml`** — new service + add `TRACKING_SERVICE_URL` to the gateway env:

```yaml
  bt-tracking-service:
    build: ./bt-tracking-service
    ports: ["3006:3006"]
    environment:
      PORT: 3006
      JWT_SECRET: ${JWT_SECRET}
      REDIS_URL: ${REDIS_URL}                 # SAME Redis as booking-service
      SUPABASE_URL: ${SUPABASE_URL}
      SUPABASE_SERVICE_ROLE_KEY: ${SUPABASE_SERVICE_ROLE_KEY}
      GOOGLE_MAPS_SERVER_KEY: ${GOOGLE_MAPS_SERVER_KEY}
      DIESEL_PRICE_INR: ${DIESEL_PRICE_INR:-90}
    depends_on: [redis]

  bt-gateway:
    environment:
      # ...existing...
      TRACKING_SERVICE_URL: http://bt-tracking-service:3006
```

**`Makefile`** — add to the backend services list:

```makefile
BACKEND_SVCS = bt-auth-service bt-booking-service bt-pricing-service bt-payment-service bt-cargo-ledger bt-tracking-service
```

**`bt-tracking-service/env.example`:**

```
PORT=3006
JWT_SECRET=
REDIS_URL=redis://localhost:6379
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
GOOGLE_MAPS_SERVER_KEY=        # server key: Routes + Places(New) only, NO referrer
DIESEL_PRICE_INR=90            # default; overridable per /fuel/estimate request
ROUTE_CACHE_TTL_SECONDS=21600  # route/pumps cache (6h); ETA cache is 45s in code
```

> **Cloud Run deploy:** add `bt-tracking-service` alongside the other asia-south1 services and set `TRACKING_SERVICE_URL` on the gateway to its `*.run.app` URL (the entrypoint already strips it to `TRACKING_SERVICE_HOST`).

**Existing files this section builds on/around:**
- `bt-booking-service/src/routes/location.ts` (GPS pipeline — untouched)
- `bt-booking-service/src/plugins/auth.ts` (copy verbatim)
- `bt-gateway/nginx.conf.template`, `bt-gateway/docker-entrypoint.sh`
- New: `bt-tracking-service/` and `supabase/migrations/009_maps_tracking.sql`

---

## 4. Database — Migration 009 (`009_maps_tracking.sql`)

### Design decisions (read first)

| Question | Decision | Why |
|---|---|---|
| Reuse `trip_events` or add tables? | **Add 3 new tables; do NOT touch `trip_events`.** | `trip_events` is a human-meaningful, append-only *milestone audit* (`arrived_pickup`, `delivered`…). Route caches, fuel math, and machine-generated alerts are a different concern with different lifecycles (caches expire; alerts get acknowledged). Overloading `trip_events.event_type` would pollute the legal/POD audit trail and force an `event_type` CHECK change. Keep them separate. |
| Anchor on `trips` or `bookings`? | **Anchor everything on `booking_id`.** | The `trips` table is *referenced* by FKs in 004 but its `CREATE TABLE` is **not present in any migration** (verified: 001-008 never create `trips`/`bookings`/`drivers` — they're in the pre-existing base schema). `booking_id` is the one anchor 004 actually creates FKs against. Migration 009 must NOT assume `trips` exists. → all new FKs point at `bookings(id)` / `drivers(id)`. |
| Persist the 30s-TTL Redis GPS pings? | **YES — persist a breadcrumb trail.** `location_history` is **enabled** (confirmed 2026-06-18). | The user opted to capture the full route path from day one for **route replay, payment/delivery dispute resolution, and audit**. To keep volume sane at pilot scale the writer **throttles inserts to ~1 point / 10-15s** (not every 5-10s ping); the table is append-only and pruned by `recorded_at` with a periodic job. |
| `decimal` vs PostGIS | **`decimal(10,8)`/`decimal(11,8)`**, matching `source_lat/lng`. No PostGIS. | Consistency; geofence math is cheap haversine in the service. |
| RLS | **Enable RLS on all new tables, define NO policies.** | Exactly mirrors `trip_events` and the 15 tables in 004. `bt-tracking-service` uses the Supabase **service-role** key (bypasses RLS). Per-row policies are deferred to the RN phase. |

### Table-by-table notes

- **`trip_routes`** — one cached Routes-API result per booking (`UNIQUE(booking_id)`, upsert). `expires_at` lets the service decide staleness without deleting rows; `bounds` stored as four decimals (no geometry type) so the JS map can `fitBounds()` without re-decoding the polyline. This is the single biggest cost lever — every cache hit is one Routes API call you didn't pay for.
- **`fuel_estimates`** — append-only (history per booking; `model_version` lets you recompute when you tweak mileage benchmarks). Snapshots the inputs (`mileage_kmpl`, `diesel_price`) so a historical estimate stays explainable even after prices/benchmarks change.
- **`route_alerts`** — machine-generated events with `acknowledged` flag for the shipper/driver UI. `payload jsonb` holds type-specific extras (e.g. `{ "off_route_m": 480 }`, `{ "eta_slip_min": 22 }`) so you never migrate for a new alert flavor. `alert_type` CHECK is the documented set.

```sql
-- supabase/migrations/009_maps_tracking.sql
-- Maps & Tracking (Sprint 3-4): route cache, fuel estimates, route alerts.
-- Anchored on bookings(id)/drivers(id) — the `trips` table is referenced by
-- 004 but never CREATEd in migrations, so 009 deliberately does NOT touch it.
-- RLS: enabled, NO policies (service-role bypass) — identical to 004. Policies
-- are deferred to the React Native phase.
-- No PostGIS; coords use decimal(10,8)/decimal(11,8) like bookings.source_lat/lng.

-- =====================================================================
-- 1. trip_routes — cached Routes API result (1 row per booking, upsert)
-- =====================================================================
create table if not exists trip_routes (
  id                  uuid primary key default gen_random_uuid(),
  booking_id          uuid not null references bookings(id) on delete cascade,
  encoded_polyline    text not null,                -- Routes API polyline.encodedPolyline
  distance_m          integer not null check (distance_m >= 0),
  duration_s          integer not null check (duration_s >= 0),  -- staticDuration (traffic-unaware)
  duration_traffic_s  integer check (duration_traffic_s >= 0),   -- duration (traffic-aware, Pro tier); nullable
  bounds_ne_lat       decimal(10,8),   -- viewport for map fitBounds(); no geometry type
  bounds_ne_lng       decimal(11,8),
  bounds_sw_lat       decimal(10,8),
  bounds_sw_lng       decimal(11,8),
  route_source        text not null default 'google_routes',
  computed_at         timestamptz not null default now(),
  expires_at          timestamptz not null,         -- service treats row as stale past this
  unique (booking_id)                               -- one live cache per booking -> ON CONFLICT upsert
);

create index if not exists idx_trip_routes_booking_id on trip_routes(booking_id);
create index if not exists idx_trip_routes_expires_at on trip_routes(expires_at);

-- =====================================================================
-- 2. fuel_estimates — append-only fuel cost snapshots (history per booking)
-- =====================================================================
create table if not exists fuel_estimates (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid not null references bookings(id) on delete cascade,
  driver_id     uuid references drivers(id) on delete set null,
  mileage_kmpl  decimal(5,2) not null check (mileage_kmpl > 0),   -- e.g. 4.50 HCV, 12.00 LCV
  distance_km   decimal(10,2) not null check (distance_km >= 0),  -- from trip_routes.distance_m / 1000
  est_litres    decimal(10,2) not null check (est_litres >= 0),   -- distance_km / mileage_kmpl
  diesel_price  decimal(6,2)  not null check (diesel_price > 0),  -- Rs/L snapshot at compute time
  est_cost      decimal(12,2) not null check (est_cost >= 0),     -- est_litres * diesel_price (Rs)
  laden         boolean not null default true,                    -- laden burns more; affects chosen mileage
  model_version text not null default 'v1',                       -- bump when benchmarks change
  computed_at   timestamptz not null default now()
);

create index if not exists idx_fuel_estimates_booking_id on fuel_estimates(booking_id);
create index if not exists idx_fuel_estimates_driver_id  on fuel_estimates(driver_id);

-- =====================================================================
-- 3. route_alerts — machine-generated tracking alerts (ack-able)
-- =====================================================================
create table if not exists route_alerts (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid not null references bookings(id) on delete cascade,
  driver_id    uuid references drivers(id) on delete set null,
  alert_type   text not null check (alert_type in (
                 'off_route', 'geofence_pickup', 'geofence_delivery',
                 'long_idle', 'eta_slip', 'breakdown', 'jam', 'detour', 'weather', 'other')),
  payload      jsonb not null default '{}'::jsonb,   -- {off_route_m:480} / {eta_slip_min:22} ...
  message      text,                                 -- free-text for driver-raised alerts
  latitude     decimal(10,8),
  longitude    decimal(11,8),
  acknowledged boolean not null default false,
  acknowledged_at timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists idx_route_alerts_booking_id on route_alerts(booking_id);
create index if not exists idx_route_alerts_driver_id  on route_alerts(driver_id);
-- fast "unacked alerts for this booking" lookup for the shipper/driver UI:
create index if not exists idx_route_alerts_unacked
  on route_alerts(booking_id) where acknowledged = false;

-- =====================================================================
-- 4. location_history — raw GPS breadcrumb archive. ENABLED (confirmed 2026-06-18).
--    A small writer in bt-tracking-service THROTTLES inserts to ~1 point / 10-15s
--    (NOT every 5-10s ping) to keep volume sane. Append-only; prune by recorded_at
--    with a periodic job. Powers route replay, payment/delivery dispute
--    resolution, and audit.
-- =====================================================================
create table if not exists location_history (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null references bookings(id) on delete cascade,
  driver_id   uuid not null references drivers(id) on delete cascade,
  latitude    decimal(10,8) not null,
  longitude   decimal(11,8) not null,
  heading     decimal(5,2),
  speed_kmh   decimal(6,2),
  accuracy_m  decimal(7,2),
  recorded_at timestamptz not null default now()
);
create index if not exists idx_location_history_booking on location_history(booking_id, recorded_at);

-- =====================================================================
-- RLS: enable, NO policies (service-role bypass). Mirrors 004. Deferred to RN.
-- =====================================================================
alter table trip_routes      enable row level security;
alter table fuel_estimates   enable row level security;
alter table route_alerts     enable row level security;
alter table location_history enable row level security;
```

> The `alert_type` CHECK above merges the machine-generated set (`off_route`, `geofence_*`, `long_idle`, `eta_slip`) with the driver-raised set (`breakdown`, `jam`, `detour`, `weather`, `other`) and adds a `message` column, so a single `route_alerts` table backs both the automatic evaluator (Phase 5) and the `POST /alerts` endpoint (#6).

### How the tracking service uses these (one line each)
- **`trip_routes`**: `INSERT ... ON CONFLICT (booking_id) DO UPDATE` after a Routes API call; on read, serve cached row if `now() < expires_at`, else refetch. This is what keeps you inside the GMP free caps.
- **`fuel_estimates`**: insert a fresh snapshot when route is (re)computed or diesel price changes; read latest by `computed_at DESC`.
- **`route_alerts`**: service inserts on geofence/off-route detection (haversine vs `trip_routes` polyline) or on `POST /alerts`; UI marks `acknowledged = true, acknowledged_at = now()`; partial index `idx_route_alerts_unacked` powers the badge count.

### Defending against the missing `trips` table
Migration 009 contains **zero references to `trips`**. Every FK targets `bookings(id)` or `drivers(id)`. If a real `trips` table lands later, these tables don't need to change; you'd add an optional `trip_id uuid references trips(id)` column in a future migration without disturbing the `booking_id` anchor.

**File to save:** `supabase/migrations/009_maps_tracking.sql`

---

## 5. Frontend & UI design (both apps)

This section turns the two existing text-only tracking panels into real maps and adds the driver navigation screen. It assumes the `bt-tracking-service` (port 3006, gateway `/api/tracking/`) endpoints from §3.

| Endpoint (read-only query-string convenience form) | Used by | Returns (`data`) |
|---|---|---|
| `GET /api/tracking/route?bookingId=…` | both | `{ encodedPolyline, distanceMeters, durationSeconds, staticDurationSeconds, originLat, originLng, destLat, destLng }` (cached) |
| `GET /api/tracking/eta?bookingId=…&lat=&lng=` | both | `{ distanceMeters, durationSeconds }` (driver→dest, traffic-aware) |
| `GET /api/tracking/fuel-stops?bookingId=…&lat=&lng=` | driver | `{ stops: [{ name, brand, lat, lng, distanceAheadMeters }] }` |
| `GET /api/tracking/fuel-estimate?bookingId=…&lat=&lng=` | driver | `{ litres, costInr, dieselPriceInr, mileageKmpl }` |
| `GET /api/tracking/alerts?bookingId=…` | driver | `{ alerts: [{ id, severity, text }] }` |

Live position keeps coming from the existing `GET /api/location/booking/:id` (shipper) and the driver's own `watchPosition → pushLocation` loop. **Nothing in the GPS pipeline changes.**

### A. Shared map library decision: `@vis.gl/react-google-maps`

One install per app (both are separate Next projects):

```bash
# run in BOTH driver/ and shipper/
npm i @vis.gl/react-google-maps @googlemaps/polyline-codec
```

- `@vis.gl/react-google-maps` — Google-endorsed React wrapper, App-Router safe behind a `'use client'` boundary, `<AdvancedMarker>` support, and ports 1:1 to `react-native-maps` later.
- `@googlemaps/polyline-codec` — tiny, dependency-free decoder for the Routes API `encodedPolyline` (no need to load the Maps `geometry` library).

**Key loading.** Maps JS runs in the browser, so it needs a **separate, HTTP-referrer-restricted** browser key (NOT the server key the tracking-service uses). Add to `driver/.env.local` and `shipper/.env.local` (and Vercel/Cloud Run env):

```
NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY=AIza...
NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID=...        # optional; falls back to DEMO_MAP_ID
```

In Google Cloud Console restrict this key to: **Application restriction = HTTP referrers** (`https://driver.bharattruck.app/*`, `https://shipper.bharattruck.app/*`, `http://localhost:3000/*`) and **API restriction = Maps JavaScript API only**. A leaked referrer-restricted key cannot be billed from another domain.

### B. Reusable shared pieces (two separate Next projects)

Both apps are independent Next projects, so there is no shared `node_modules`. Use a **vendored copy** approach: author each file once, drop an identical copy into both `src/lib/` (and `src/components/maps/`). The files below are written to be byte-identical across apps — only the env var name and token key differ, and those are read from `process.env`/existing `api.ts`.

```
driver/src/lib/navigation.ts          shipper/src/lib/navigation.ts        (identical)
driver/src/lib/maps.ts                 shipper/src/lib/maps.ts              (identical)
driver/src/components/maps/            shipper/src/components/maps/         (identical)
  LiveTrackMap.tsx                       LiveTrackMap.tsx
  useAnimatedMarker.ts                   useAnimatedMarker.ts
```

A 6-line guard script (`scripts/sync-maps.sh`) `diff`s the two folders in CI so they never drift:

```bash
#!/usr/bin/env bash
set -e
for f in lib/navigation.ts lib/maps.ts components/maps/LiveTrackMap.tsx components/maps/useAnimatedMarker.ts; do
  diff -q "driver/src/$f" "shipper/src/$f" || { echo "DRIFT: $f"; exit 1; }
done
echo "maps shared files in sync"
```

> When the apps move to React Native, `navigation.ts` is reused verbatim (deep links are identical) and `LiveTrackMap` is reimplemented once with `react-native-maps` against the *same* tracking endpoints.

### C. `src/lib/maps.ts` — shared helpers (polyline decode, geometry, env)

```ts
// src/lib/maps.ts  (identical in driver/ and shipper/)
import { decode } from '@googlemaps/polyline-codec'

export const MAPS_BROWSER_KEY = process.env.NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY ?? ''

export interface LatLng { lat: number; lng: number }

/** Routes API encoded polyline -> [{lat,lng}] for <Polyline>/path rendering. */
export function decodePolyline(encoded: string): LatLng[] {
  if (!encoded) return []
  return decode(encoded, 5).map(([lat, lng]) => ({ lat, lng }))
}

/** Bearing in degrees (0=N) from a->b, used to rotate the truck icon. */
export function bearing(a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180
  const y = Math.sin(toRad(b.lng - a.lng)) * Math.cos(toRad(b.lat))
  const x =
    Math.cos(toRad(a.lat)) * Math.sin(toRad(b.lat)) -
    Math.sin(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.cos(toRad(b.lng - a.lng))
  return (Math.atan2(y, x) * 180) / Math.PI
}

/** Linear interpolation for smooth marker movement between two GPS fixes. */
export function lerp(a: LatLng, b: LatLng, t: number): LatLng {
  return { lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t }
}

export function fmtKm(meters: number): string {
  return meters >= 1000 ? `${(meters / 1000).toFixed(1)} km` : `${Math.round(meters)} m`
}

export function fmtEta(seconds: number): string {
  const m = Math.round(seconds / 60)
  if (m < 60) return `${m} min`
  return `${Math.floor(m / 60)}h ${m % 60}m`
}
```

### D. `src/components/maps/useAnimatedMarker.ts` — smooth interpolation between 10s polls

Polls arrive every 10s; a raw marker jump looks broken. This hook animates from the last rendered point to the new fix over ~1.4s using `requestAnimationFrame`, exposing a live `LatLng` plus the current `heading` for icon rotation.

```ts
// src/components/maps/useAnimatedMarker.ts  (identical in both apps)
import { useEffect, useRef, useState } from 'react'
import { bearing, lerp, type LatLng } from '@/lib/maps'

const DURATION_MS = 1400

/** Animates marker from its current position to `target` whenever target changes. */
export function useAnimatedMarker(target: LatLng | null) {
  const [pos, setPos] = useState<LatLng | null>(target)
  const [heading, setHeading] = useState(0)
  const fromRef = useRef<LatLng | null>(target)
  const rafRef = useRef<number | null>(null)

  useEffect(() => {
    if (!target) return
    const from = fromRef.current
    if (!from) {           // first fix: snap, no animation
      fromRef.current = target
      setPos(target)
      return
    }
    if (from.lat === target.lat && from.lng === target.lng) return

    setHeading(bearing(from, target))
    const start = performance.now()

    const tick = (now: number) => {
      const t = Math.min((now - start) / DURATION_MS, 1)
      const eased = t * (2 - t)                 // easeOutQuad
      setPos(lerp(from, target, eased))
      if (t < 1) rafRef.current = requestAnimationFrame(tick)
      else fromRef.current = target
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => { if (rafRef.current) cancelAnimationFrame(rafRef.current) }
  }, [target])

  return { pos, heading }
}
```

### E. `src/components/maps/LiveTrackMap.tsx` — the one reusable map

Used by both screens. Renders origin/dest pins, the route polyline, and an animated, rotated truck `AdvancedMarker`. `'use client'` + `<APIProvider>` is the App-Router boundary. `mapId` is required for `AdvancedMarker` (create a free vector Map ID in Cloud Console → Map Management; falls back to `'DEMO_MAP_ID'` for local prototyping). Add `data-testid="driver-marker"` to the truck marker so Playwright (§8.C) has a stable handle.

```tsx
'use client'
// src/components/maps/LiveTrackMap.tsx  (identical in both apps)
import { useMemo } from 'react'
import {
  APIProvider, Map, AdvancedMarker, Pin, useMap,
} from '@vis.gl/react-google-maps'
import { useEffect } from 'react'
import { MAPS_BROWSER_KEY, decodePolyline, type LatLng } from '@/lib/maps'
import { useAnimatedMarker } from './useAnimatedMarker'

const MAP_ID = process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? 'DEMO_MAP_ID'

export interface LiveTrackMapProps {
  origin: LatLng
  dest: LatLng
  encodedPolyline?: string
  driver?: LatLng | null          // live position (null = not started)
  className?: string
}

export default function LiveTrackMap(props: LiveTrackMapProps) {
  if (!MAPS_BROWSER_KEY) {
    return (
      <div className="flex items-center justify-center h-full bg-gray-100 text-sm text-gray-500 rounded-2xl">
        Map unavailable
      </div>
    )
  }
  return (
    <APIProvider apiKey={MAPS_BROWSER_KEY}>
      <div className={props.className ?? 'h-72 w-full rounded-2xl overflow-hidden'}>
        <Map
          mapId={MAP_ID}
          defaultCenter={props.origin}
          defaultZoom={11}
          gestureHandling="greedy"
          disableDefaultUI
          zoomControl
        >
          <MapContent {...props} />
        </Map>
      </div>
    </APIProvider>
  )
}

function MapContent({ origin, dest, encodedPolyline, driver }: LiveTrackMapProps) {
  const map = useMap()
  const path = useMemo(() => decodePolyline(encodedPolyline ?? ''), [encodedPolyline])
  const { pos, heading } = useAnimatedMarker(driver ?? null)

  // Draw the route polyline imperatively (no React <Polyline> in this wrapper).
  useEffect(() => {
    if (!map || path.length === 0) return
    const line = new google.maps.Polyline({
      path, geodesic: true, strokeColor: '#2563eb', strokeOpacity: 0.9, strokeWeight: 5,
    })
    line.setMap(map)
    const bounds = new google.maps.LatLngBounds()
    path.forEach(p => bounds.extend(p))
    bounds.extend(origin); bounds.extend(dest)
    map.fitBounds(bounds, 48)
    return () => line.setMap(null)
  }, [map, path, origin, dest])

  return (
    <>
      <AdvancedMarker position={origin}><Pin background="#16a34a" borderColor="#15803d" glyphColor="#fff" /></AdvancedMarker>
      <AdvancedMarker position={dest}><Pin background="#dc2626" borderColor="#b91c1c" glyphColor="#fff" /></AdvancedMarker>
      {pos && (
        <AdvancedMarker position={pos} data-testid="driver-marker">
          <div style={{ transform: `rotate(${heading}deg)` }} className="text-2xl leading-none drop-shadow">🚚</div>
        </AdvancedMarker>
      )}
    </>
  )
}
```

### F. `src/lib/navigation.ts` — deep-link handoff (free, no SDK)

Decision #4: tapping "Navigate" hands off to the phone's Google Maps app. All builders below open the native app if installed and fall back to the web/Apple Maps. **Identical in React Native** (use `Linking.openURL(buildNavUrl(...))`).

```ts
// src/lib/navigation.ts  (identical in driver/ and shipper/, reused as-is in React Native)
export interface NavPoint { lat: number; lng: number }

const isIOS = () =>
  typeof navigator !== 'undefined' && /iphone|ipad|ipod/i.test(navigator.userAgent)

/**
 * Universal Google Maps navigation URL. Opens the Google Maps app if installed
 * (Android Chrome + iOS Safari), else the web map. Supports intermediate waypoints
 * (e.g. a chosen petrol pump) via &waypoints=lat,lng|lat,lng.
 */
export function buildNavUrl(
  dest: NavPoint,
  opts: { origin?: NavPoint; waypoints?: NavPoint[] } = {},
): string {
  const p = (pt: NavPoint) => `${pt.lat},${pt.lng}`
  const params = new URLSearchParams({
    api: '1',
    destination: p(dest),
    travelmode: 'driving',
    dir_action: 'navigate',
  })
  if (opts.origin) params.set('origin', p(opts.origin))
  if (opts.waypoints?.length) params.set('waypoints', opts.waypoints.map(p).join('|'))
  return `https://www.google.com/maps/dir/?${params.toString()}`
}

/** Android-only intent that launches turn-by-turn directly to a single point. */
export function buildAndroidNavUrl(dest: NavPoint): string {
  return `google.navigation:q=${dest.lat},${dest.lng}&mode=d`
}

/** Apple Maps fallback for iOS users without Google Maps installed. */
export function buildAppleMapsUrl(dest: NavPoint): string {
  return `maps://?daddr=${dest.lat},${dest.lng}&dirflg=d`
}

/** One call to "just navigate" — picks the best scheme for the device. */
export function openNavigation(dest: NavPoint, opts?: { origin?: NavPoint; waypoints?: NavPoint[] }) {
  // Universal URL works everywhere and opens the native app if present.
  const url = buildNavUrl(dest, opts)
  if (typeof window !== 'undefined') window.location.assign(url)
  return url
}

/** Deep-link straight to a petrol pump (single destination, no waypoints). */
export function openPumpNavigation(pump: NavPoint) {
  if (isIOS()) { window.location.assign(buildNavUrl(pump)); return }
  // Android: try the native intent first (instant turn-by-turn).
  window.location.assign(buildAndroidNavUrl(pump))
}
```

### G. Shipper live-tracking screen

**Location.** Extend the existing `shipper/src/app/bookings/[id]/page.tsx`. Replace the text block inside `TripTrackingSection` (the `location ? (...)` panel) with the map. The existing 10s `getBookingLocation` poll stays; we add a one-time route fetch. No new route file.

**New shipper API calls** (add to `shipper/src/lib/api.ts`):

```ts
export interface RouteData {
  encodedPolyline: string; distanceMeters: number; durationSeconds: number
  staticDurationSeconds: number; originLat: number; originLng: number; destLat: number; destLng: number
}
export interface EtaData { distanceMeters: number; durationSeconds: number }

export function getRoute(bookingId: string): Promise<RouteData> {
  return request<RouteData>(`/tracking/route?bookingId=${bookingId}`)
}
export function getEta(bookingId: string, lat: number, lng: number): Promise<EtaData> {
  return request<EtaData>(`/tracking/eta?bookingId=${bookingId}&lat=${lat}&lng=${lng}`)
}
```

**ASCII wireframe (shipper, status = `in_transit`, live):**

```
┌─────────────────────────────────────────────┐
│  Trip Status                                  │
│  ━━●━━━━━●━━━━━○━━━━━○                         │  ← existing progress steps
│  Assigned  In Transit  Delivered  Paid        │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │  ⏱ ETA 2h 40m  •  126 km remaining       │ │  ← banner (live=blue)
│ ├─────────────────────────────────────────┤ │
│ │            [ Google Map ]                 │ │
│ │   🟢origin                                │ │
│ │      \____ blue route polyline ____       │ │
│ │              🚚(rotated, animates)        │ │
│ │                       \______ 🔴dest      │ │
│ │                                           │ │
│ └─────────────────────────────────────────┘ │
│  ● Live · updated 6s ago                      │  ← freshness dot
└─────────────────────────────────────────────┘
```

**States:**

| State | Condition | UI |
|---|---|---|
| loading | route not yet fetched | skeleton box (`h-72 animate-pulse bg-gray-100`) |
| waiting-for-driver | status `accepted`, or `in_transit` but `location===null` | map with route + pins, **no truck**, caption "Waiting for driver to start sharing location" |
| live | fix with `age ≤ 30s` | animated truck, blue ETA banner, green "● Live" dot |
| stale | fix `age > 30s` | grey truck, amber banner "Driver offline — last seen Xm ago", dot amber/pulsing |
| delivered | status `completed`/`paid` | static map, route + both pins, no truck, "Delivered ✓" caption |

**Component tree (shipper):**

```
BookingDetailPage
└─ TripTrackingSection
   ├─ <progress steps>            (existing, unchanged)
   └─ ShipperTrackPanel          (NEW — wraps the map)
      ├─ EtaBanner                (distance + ETA, color by freshness)
      ├─ LiveTrackMap             (shared)  ← driver={fresh ? loc : null}, gray when stale via prop
      └─ FreshnessCaption         (● Live / Driver offline / Delivered)
```

**`ShipperTrackPanel` (drop into `shipper/src/app/bookings/[id]/page.tsx`):**

```tsx
function ShipperTrackPanel({
  booking, location,
}: { booking: Booking; location: DriverLocation | null }) {
  const [route, setRoute] = useState<RouteData | null>(null)
  const [eta, setEta] = useState<EtaData | null>(null)

  useEffect(() => {            // route is static for the booking → fetch once (server caches)
    getRoute(booking.id).then(setRoute).catch(() => setRoute(null))
  }, [booking.id])

  const ageMs = location ? Date.now() - new Date(location.updated_at).getTime() : Infinity
  const fresh = ageMs <= 30_000
  const driverPt = location ? { lat: location.lat, lng: location.lng } : null

  useEffect(() => {            // live ETA, refreshed only when we have a fresh fix
    if (!location || !fresh) return
    getEta(booking.id, location.lat, location.lng).then(setEta).catch(() => {})
  }, [booking.id, location?.lat, location?.lng, fresh])

  const delivered = booking.status === 'completed' || booking.status === 'paid'

  if (!route) return <div className="h-72 w-full rounded-2xl bg-gray-100 animate-pulse" />

  return (
    <div className="space-y-2">
      {!delivered && (
        <div className={`flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-medium ${
          fresh ? 'bg-blue-50 text-blue-700' : 'bg-amber-50 text-amber-700'}`}>
          {fresh
            ? <>⏱ ETA {eta ? fmtEta(eta.durationSeconds) : '—'} · {eta ? fmtKm(eta.distanceMeters) : '—'} remaining</>
            : <>Driver offline — last seen {location ? Math.round(ageMs / 60000) : 0}m ago</>}
        </div>
      )}
      <LiveTrackMap
        origin={{ lat: route.originLat, lng: route.originLng }}
        dest={{ lat: route.destLat, lng: route.destLng }}
        encodedPolyline={route.encodedPolyline}
        driver={delivered ? null : (fresh ? driverPt : driverPt)}  // shown grey-ish when stale via caption
      />
      <p className="text-xs text-gray-400 flex items-center gap-1.5">
        {delivered ? 'Delivered ✓'
          : fresh ? <><span className="w-2 h-2 rounded-full bg-green-500 animate-pulse inline-block" /> Live</>
          : <><span className="w-2 h-2 rounded-full bg-amber-400 inline-block" /> Stale</>}
      </p>
    </div>
  )
}
```

Wire it in `TripTrackingSection` by replacing the inner `location ? (...) : ...` block with `<ShipperTrackPanel booking={booking} location={location} />` (the existing 10s poll already produces `location`).

### H. Driver navigation screen

**Location.** Phase-1: render inside the existing `ActiveTripSection` in `driver/src/app/(app)/bookings/[id]/page.tsx`, directly below the GPS-status pill, so it appears only when `status === 'in_transit'`. The GPS `watchPosition` loop and wake-lock already live here. (A dedicated `(app)/bookings/[id]/navigate` route can be split out later, but Phase-1 keeps it on one screen to avoid plumbing the live `position` across routes.)

**New driver API calls** (add to `driver/src/lib/api.ts`, reuse the same `RouteData`/`EtaData` as shipper):

```ts
export interface FuelStop { name: string; brand: string; lat: number; lng: number; distanceAheadMeters: number }
export interface FuelEstimate { litres: number; costInr: number; dieselPriceInr: number; mileageKmpl: number }
export interface RouteAlert { id: string; severity: 'info' | 'warn'; text: string }

export function getRoute(id: string) { return request<RouteData>(`/tracking/route?bookingId=${id}`) }
export function getEta(id: string, lat: number, lng: number) { return request<EtaData>(`/tracking/eta?bookingId=${id}&lat=${lat}&lng=${lng}`) }
export function getFuelStops(id: string, lat: number, lng: number) { return request<{ stops: FuelStop[] }>(`/tracking/fuel-stops?bookingId=${id}&lat=${lat}&lng=${lng}`) }
export function getFuelEstimate(id: string, lat: number, lng: number) { return request<FuelEstimate>(`/tracking/fuel-estimate?bookingId=${id}&lat=${lat}&lng=${lng}`) }
export function getAlerts(id: string) { return request<{ alerts: RouteAlert[] }>(`/tracking/alerts?bookingId=${id}`) }
```

**ASCII wireframe (driver):**

```
┌─────────────────────────────────────────────┐
│  Trip In Progress                      1h 12m │
│  ● Location active — sharing with shipper     │  ← existing GPS pill + wake-lock
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │           [ Route overview map ]          │ │  ← LiveTrackMap (own GPS = driver)
│ │   🟢 \___route___ 🚚 _____ 🔴             │ │
│ └─────────────────────────────────────────┘ │
│   126 km to go   •   ⏱ 2h 40m (live)         │  ← distance + ETA
├─────────────────────────────────────────────┤
│  ⚠ ALERTS                                     │
│  [ Heavy traffic near Nashik · ~15 min ]      │  ← horizontal strip
├─────────────────────────────────────────────┤
│  ⛽ Petrol pumps ahead          (scroll →)    │
│  ┌────────┐┌────────┐┌────────┐┌────────┐    │
│  │ HP     ││ IOCL   ││ BPCL   ││ Shell  │    │  ← horiz scroll, tap=deep-link
│  │ 8 km   ││ 23 km  ││ 41 km  ││ 60 km  │    │
│  │  → Nav ││  → Nav ││  → Nav ││  → Nav │    │
│  └────────┘└────────┘└────────┘└────────┘    │
├─────────────────────────────────────────────┤
│  ⛽ Fuel estimate (remaining)                 │
│   ≈ 31 L   ·   ₹2,790   (@ ₹90/L · 4 km/L)    │  ← fuel card
├─────────────────────────────────────────────┤
│  ╔═══════════════════════════════════════╗   │
│  ║   ▶  NAVIGATE in Google Maps           ║   │  ← big primary, deep-link
│  ╚═══════════════════════════════════════╝   │
│  [ Mark as Delivered ]                         │  (existing)
└─────────────────────────────────────────────┘
```

**Component tree (driver):**

```
ActiveTripSection                       (existing — owns watchPosition + wake-lock)
├─ <GPS status pill>                     (existing)
└─ DriverNavPanel  (NEW)   props: { booking, position: LatLng | null }
   ├─ LiveTrackMap            (shared)   driver = own live position
   ├─ EtaRow                             distance + live ETA
   ├─ AlertsStrip                        horizontal chips from /alerts
   ├─ PumpsAhead                         horizontal-scroll cards → openPumpNavigation()
   ├─ FuelCard                           litres + ₹ from /fuel-estimate
   └─ NavigateButton                     openNavigation(dest, {origin, waypoints?})
```

**`DriverNavPanel`** (the live `position` comes from the existing `watchPosition`; thread it out by storing the latest fix in state — add `const [position, setPosition] = useState<LatLng|null>(null)` in `ActiveTripSection` and `setPosition({lat,lng})` inside the existing success callback, right where it calls `pushLocation`):

```tsx
function DriverNavPanel({ booking, position }: { booking: Booking; position: LatLng | null }) {
  const [route, setRoute] = useState<RouteData | null>(null)
  const [eta, setEta] = useState<EtaData | null>(null)
  const [stops, setStops] = useState<FuelStop[]>([])
  const [fuel, setFuel] = useState<FuelEstimate | null>(null)
  const [alerts, setAlerts] = useState<RouteAlert[]>([])

  useEffect(() => { getRoute(booking.id).then(setRoute).catch(() => {}) }, [booking.id])

  // Recompute insights when we move ~>2km (throttled by rounding lat/lng to 2 dp).
  const cell = position ? `${position.lat.toFixed(2)},${position.lng.toFixed(2)}` : null
  useEffect(() => {
    if (!position) return
    const { lat, lng } = position
    getEta(booking.id, lat, lng).then(setEta).catch(() => {})
    getFuelStops(booking.id, lat, lng).then(r => setStops(r.stops)).catch(() => {})
    getFuelEstimate(booking.id, lat, lng).then(setFuel).catch(() => {})
    getAlerts(booking.id).then(r => setAlerts(r.alerts)).catch(() => {})
  }, [booking.id, cell]) // eslint-disable-line react-hooks/exhaustive-deps

  const dest = route ? { lat: route.destLat, lng: route.destLng } : null

  return (
    <div className="space-y-3 mt-3">
      {route && (
        <>
          <LiveTrackMap
            origin={{ lat: route.originLat, lng: route.originLng }}
            dest={{ lat: route.destLat, lng: route.destLng }}
            encodedPolyline={route.encodedPolyline}
            driver={position}
          />
          <div className="flex items-center justify-between text-sm font-medium text-gray-700 px-1">
            <span>{eta ? fmtKm(eta.distanceMeters) : fmtKm(route.distanceMeters)} to go</span>
            <span className="text-purple-700">⏱ {fmtEta((eta ?? route).durationSeconds)}</span>
          </div>
        </>
      )}

      {alerts.length > 0 && (
        <div className="flex gap-2 overflow-x-auto -mx-1 px-1 pb-1">
          {alerts.map(a => (
            <span key={a.id}
              className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium ${
                a.severity === 'warn' ? 'bg-amber-100 text-amber-800' : 'bg-blue-100 text-blue-800'}`}>
              {a.severity === 'warn' ? '⚠ ' : 'ℹ '}{a.text}
            </span>
          ))}
        </div>
      )}

      {stops.length > 0 && (
        <div>
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2 px-1">⛽ Petrol pumps ahead</p>
          <div className="flex gap-2 overflow-x-auto -mx-1 px-1 pb-1 snap-x">
            {stops.map((s, i) => (
              <button key={i} onClick={() => openPumpNavigation(s)}
                className="shrink-0 w-32 snap-start rounded-xl border border-gray-200 bg-white p-3 text-left active:scale-[0.97] transition-transform">
                <p className="text-sm font-bold text-gray-900 truncate">{s.brand || s.name}</p>
                <p className="text-xs text-gray-500 truncate">{s.name}</p>
                <p className="text-xs text-gray-400 mt-1">{fmtKm(s.distanceAheadMeters)} ahead</p>
                <p className="text-xs font-medium text-blue-600 mt-1">→ Navigate</p>
              </button>
            ))}
          </div>
        </div>
      )}

      {fuel && (
        <div className="rounded-xl bg-orange-50 border border-orange-200 p-3">
          <p className="text-xs font-semibold text-orange-700 uppercase tracking-wide mb-1">⛽ Fuel estimate (remaining)</p>
          <p className="text-base font-bold text-orange-800">
            ≈ {Math.round(fuel.litres)} L · ₹{Math.round(fuel.costInr).toLocaleString('en-IN')}
          </p>
          <p className="text-xs text-orange-600 mt-0.5">@ ₹{fuel.dieselPriceInr}/L · {fuel.mileageKmpl} km/L</p>
        </div>
      )}

      {dest && (
        <button
          onClick={() => openNavigation(dest, { origin: position ?? undefined })}
          className="w-full h-14 rounded-2xl bg-blue-600 text-white font-bold text-lg active:scale-[0.98] transition-transform flex items-center justify-center gap-2 shadow-lg shadow-blue-600/30">
          ▶ Navigate in Google Maps
        </button>
      )}
    </div>
  )
}
```

### I. Wake lock + PWA install hint (driver only)

The driver screen must stay awake so GPS keeps streaming. `navigator.wakeLock` is re-acquired on `visibilitychange` (the OS releases it when the tab backgrounds). Add this hook to `ActiveTripSection` (it already manages the trip lifecycle):

```ts
// inside ActiveTripSection, alongside the existing GPS effect
useEffect(() => {
  let sentinel: WakeLockSentinel | null = null
  let released = false
  async function acquire() {
    try {
      // @ts-expect-error wakeLock is not yet in all TS lib versions
      if (navigator.wakeLock) sentinel = await navigator.wakeLock.request('screen')
    } catch { /* battery saver / unsupported — non-fatal */ }
  }
  const onVisible = () => { if (document.visibilityState === 'visible' && !released) acquire() }
  acquire()
  document.addEventListener('visibilitychange', onVisible)
  return () => {
    released = true
    document.removeEventListener('visibilitychange', onVisible)
    sentinel?.release().catch(() => {})
  }
}, [])
```

> Wake Lock requires HTTPS and a foreground tab; if the driver leaves the app, GPS pauses — that is acceptable for the pilot, and the shipper's "stale > 30s" state handles it gracefully.

**PWA install hint.** No manifest exists yet. Add a minimal `driver/public/manifest.webmanifest` (`display: "standalone"`, name "BharatTruck Driver", a 192/512 icon) linked from the root layout, then show a one-time dismissible banner on the in-transit screen:

```tsx
// InstallHint — show until dismissed; Android fires beforeinstallprompt, iOS shows manual hint
function InstallHint() {
  const [prompt, setPrompt] = useState<any>(null)
  const [dismissed, setDismissed] = useState(() =>
    typeof window !== 'undefined' && localStorage.getItem('bt_install_dismissed') === '1')
  useEffect(() => {
    const h = (e: any) => { e.preventDefault(); setPrompt(e) }
    window.addEventListener('beforeinstallprompt', h)
    return () => window.removeEventListener('beforeinstallprompt', h)
  }, [])
  if (dismissed) return null
  const close = () => { localStorage.setItem('bt_install_dismissed', '1'); setDismissed(true) }
  return (
    <div className="flex items-center gap-2 rounded-xl bg-gray-900 text-white text-xs px-3 py-2">
      <span className="flex-1">📲 Add BharatTruck to your home screen for full-screen tracking.</span>
      {prompt
        ? <button onClick={() => { prompt.prompt(); close() }} className="font-semibold underline">Install</button>
        : <span className="opacity-80">Share → Add to Home Screen</span>}
      <button onClick={close} aria-label="Dismiss" className="opacity-70">✕</button>
    </div>
  )
}
```

Standalone (installed) mode keeps the screen full-bleed and makes Wake Lock + GPS far more reliable on Android, which is the primary pilot test device (decision #5).

### J. Testing hooks for the frontend

- The **route-replay simulator** (§8.A) calls the *same* `POST /api/location/update` the real driver uses, so `ShipperTrackPanel` and the driver map animate identically without driving. No frontend changes needed to test movement.
- The animated marker, stale>30s, and "driver offline" states are all driven purely by `updated_at` age, so the simulator can exercise every state by simply stopping/resuming its replay loop.

**Files added/touched:**
- `driver/src/components/maps/{LiveTrackMap.tsx,useAnimatedMarker.ts}` and `shipper/src/components/maps/{…}` (identical pair)
- `driver/src/lib/{maps.ts,navigation.ts}` and `shipper/src/lib/{maps.ts,navigation.ts}` (identical pair)
- Edit `shipper/src/app/bookings/[id]/page.tsx` (`TripTrackingSection` → `ShipperTrackPanel`) and `shipper/src/lib/api.ts` (`getRoute`,`getEta`)
- Edit `driver/src/app/(app)/bookings/[id]/page.tsx` (`ActiveTripSection` → add `DriverNavPanel`, wake lock, `position` state) and `driver/src/lib/api.ts` (tracking calls)
- `driver/public/manifest.webmanifest` + layout `<link>`; `scripts/sync-maps.sh`
- env: `NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY`, `NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID` in both apps

---

## 6. Google Maps Platform Setup + Cost Guardrails (Step-by-Step, Non-Expert)

This is a do-it-in-order checklist. Follow top to bottom; do not skip the restriction steps — an unrestricted key is the only way a 20-user pilot becomes a surprise bill.

### 0. The mental model (read once)

| Key | Used by | Shipped to browser? | Calls | Locked by |
|-----|---------|---------------------|-------|-----------|
| **BROWSER key** (`NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY`) | Maps JS in `driver/` + `shipper/` | YES (`NEXT_PUBLIC_*`) | Maps JavaScript API only | HTTP referrer + API restriction |
| **SERVER key** (`GOOGLE_MAPS_SERVER_KEY`) | `bt-tracking-service` only | NO (server env secret) | Routes API + Places API (New) | IP (if static) + API restriction; kept secret |

Two rules that make this foolproof:
1. **The browser key is always public** (anyone can read it in page source). Referrer + API restriction is what makes a public key safe.
2. **A budget alert never stops spend.** Only a **per-API QUOTA LIMIT** is a hard ceiling. Set both.

### 1. Create / select the Cloud project

1. Go to **https://console.cloud.google.com/**.
2. Top bar → project dropdown → **NEW PROJECT**.
3. Name: `bharattruck-maps` → **CREATE**. Wait ~20s, then select it in the dropdown.
4. Confirm the project ID shown (e.g. `bharattruck-maps-xxxxx`) — you'll see it in URLs later.

> New projects (created 2025+) **cannot** enable legacy Directions / Distance Matrix / legacy Places even if you try. This is good — it forces you onto the correct New APIs.

### 2. Enable EXACTLY three APIs (nothing legacy)

Direct links (each opens the enable page in the current project — confirm the project name in the top bar before clicking ENABLE):

1. **Maps JavaScript API** → https://console.cloud.google.com/apis/library/maps-backend.googleapis.com → **ENABLE**
2. **Routes API** → https://console.cloud.google.com/apis/library/routes.googleapis.com → **ENABLE**
3. **Places API (New)** → https://console.cloud.google.com/apis/library/places.googleapis.com → **ENABLE**

> **Do NOT enable** "Directions API", "Distance Matrix API", or the old "Places API" (the one WITHOUT "(New)"). If you see them as already-enabled, leave them — but never call them; we only use the three above. The library card for Places API (New) is literally titled **"Places API (New)"** — match that exactly.

Verify: **APIs & Services → Enabled APIs & services** should list exactly those three (plus auto-added internal ones).

### 3. Create the BROWSER key (Maps JS, public, referrer-locked)

1. **APIs & Services → Credentials → + CREATE CREDENTIALS → API key**.
2. It creates a key — click **Edit API key** (pencil) immediately. Rename to `bt-browser-maps-js`.
3. **Application restrictions → Websites** (this is the HTTP-referrer restriction). Add these referrers:

```
http://localhost:3000/*
http://localhost:3001/*
https://*.vercel.app/*          ← only if you preview on Vercel; tighten later
https://app.bharattruck.in/*    ← your real shipper domain (edit to match)
https://driver.bharattruck.in/* ← your real driver domain (edit to match)
```

4. **API restrictions → Restrict key → select ONLY: `Maps JavaScript API`**. Save.
5. Copy the key string. This is `NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY`.

> A referrer-restricted Maps-JS key that leaks is near-useless to an attacker: requests from other domains are rejected. Still pair it with the quota cap in §5.

### 4. Create the SERVER key (Routes + Places New, secret)

1. **+ CREATE CREDENTIALS → API key** again. Edit → rename `bt-tracking-server`.
2. **API restrictions → Restrict key → select ONLY: `Routes API` AND `Places API (New)`**. Save.
3. **Application restrictions:**
   - Cloud Run does **not** give a stable outbound IP by default, so "IP addresses" restriction will break calls unless you set up a **static outbound IP via Serverless VPC + Cloud NAT**. For a 20-user pilot that's overkill.
   - **Pilot choice:** leave Application restriction = **None**, and keep the key **secret** (server env only, never `NEXT_PUBLIC`, never committed). The API restriction + quota cap in §5 is your real protection.
   - *(Later hardening, optional:)* add Serverless VPC Connector + Cloud NAT for a static egress IP, then switch to **IP addresses** restriction with that NAT IP.
4. Copy the key string. This is `GOOGLE_MAPS_SERVER_KEY` (tracking-service only).

> Treat this key like a DB password. It lives in Cloud Run env vars / `.env` (gitignored) and is sent only from your server to Google.

### 5. The HARD CAP — per-API quota limits (this is what physically stops spend)

Path for each API: **APIs & Services → [click the API name] → Quotas & System Limits** (or **IAM & Admin → Quotas**, filter by service). Find the **"Requests per day"** (and where present, **"Requests per minute"**) quota, click the pencil/checkbox → **EDIT QUOTAS** → enter a lower limit → **SUBMIT**. When the cap is hit, Google returns `429`/`RESOURCE_EXHAUSTED` and **bills nothing further** — this is the ceiling a budget can't give you.

Recommended pilot ceilings (≈10x your real expected load, so a normal day never trips it but abuse does):

| API | Quota to edit | Set "per day" | Set "per minute" | Real expected/day |
|-----|---------------|---------------|------------------|-------------------|
| **Maps JavaScript API** | Map loads per day | **2,000** | — | ~50–100 |
| **Routes API** | Requests per day (Compute Routes) | **500** | 60 | ~10–30 |
| **Places API (New)** | Requests per day (Text Search) | **300** | 30 | ~5–10 |

> If a quota shows a very large default and no editable "per day" row, edit the **"per minute"** limit instead — that still caps a runaway loop. The key principle: every billable API must have at least one editable rate quota set to a low number.

**Billing budget + alert (the soft layer):**

1. **Billing → Budgets & alerts → CREATE BUDGET**.
2. Scope = this project. Amount = **₹500 (~$6)/month**.
3. Alert thresholds: **50% / 90% / 100%** → email yourself.
4. Create.

> ⚠️ **A budget ONLY emails you. It does NOT stop API calls or cap spend.** The §5 quota limits above are the only thing that hard-stops billing. Set both: quotas = wall, budget = smoke alarm.

### 6. Credit card? + Demo Key prototyping path

- **To use real keys against the live APIs you must enable Billing** (attach a card / UPI-linked GPay billing account). The 2025 model gives monthly free caps per SKU, but a billing account must still exist.
- **Prototype with ZERO billing first** using the **Demo / "Try it" key**: open the **Google Maps Platform** product page in console → many API docs pages (Routes, Places, Maps JS) have a **"Try it"** / interactive console that issues a temporary demo key, and the Maps JS **codelab / "Get a Maps demo key"** flow lets you render a map with no card. Use this only to confirm the map renders and your code shape is right.
- **Demo keys are NOT for production**: rate-limited, watermarked/limited, and can vanish. The moment you go past "does my map draw?", create the real restricted keys (§3–4) under a billing-enabled project.

**Recommended order:** Demo key → see a map → enable billing → swap in restricted Browser key + Server key → set quota caps (§5) the same hour you enable billing.

### 7. Concrete monthly cost estimate (pilot)

**Assumptions:** 20 users, **5 active trips/day**, ~22 active days/month → **110 trips/month**.

Per trip:
| Action | API | Events/trip | Note |
|--------|-----|-------------|------|
| Shipper opens live map + driver opens nav view | Maps JS (map load) | ~3 loads | counts as dynamic map loads |
| Route compute (driver route + shipper ETA route) | Routes API | 2 | traffic-aware = Pro tier |
| Petrol-pump search along route | Places API (New) Text Search | 1 | Search-Along-Route, 1 call |
| ETA refresh during trip | Routes API | **0 extra** | **cached** (see guardrail #1); refresh ≤ every 45s–3 min, not per-poll |

**Monthly totals:**

```
Map loads:        110 trips × 3   = 330   loads/mo
Routes API:       110 trips × 2   = 220   calls/mo  (+ throttled ETA refreshes, say ≤4/trip = 440 → ~660 total worst case)
Places (New):     110 trips × 1   = 110   calls/mo
```

**Against free caps (per SKU / month):**

| API | Our usage/mo | Free cap (approx) | Inside free? |
|-----|--------------|-------------------|--------------|
| Maps JavaScript (Dynamic) | ~330 | ~10,000 (Essentials) | ✅ ~3% of cap |
| Routes API (traffic-aware, Pro) | ~660 worst case | ~5,000 (Pro) | ✅ ~13% of cap |
| Places API New (Text Search, Pro) | ~110 | ~5,000 (Pro) | ✅ ~2% of cap |

**Cost math (overage rate only matters if you blow the cap — you don't):**

- All three APIs land **well inside** their monthly free caps.
- **Estimated bill: USD $0.00 / mo ≈ ₹0.00 / mo.**
- Reference for context (India list ≈ 1/3 global), so *if* you somehow exceeded caps, ballpark overage: Routes Pro ≈ $0.005/call → ₹0.42/call; Places Text Search Pro ≈ $0.025/call → ₹2.1/call; Dynamic map load ≈ $0.0023/load → ₹0.2/load. At our volumes (660 + 110 + 330) the *theoretical un-capped* spend would still be only ≈ **$6.8 / ₹570** — and the free caps zero it out.

**TOP 3 ways cost could unexpectedly grow → and the exact cap that neutralizes each:**

| # | Failure mode | Why it explodes | Neutralized by |
|---|--------------|-----------------|----------------|
| 1 | **Polling Routes API every few seconds for ETA** (e.g. on the shipper's 10s poll) | 5s polling × 5 trips × 8h = ~28,000 Routes calls/day → blows the 5,000 Pro cap in hours | **Server-side cache the ETA in `bt-tracking-service`** (Redis, recompute ≤ every 45s–3 min) **+ Routes "per day" quota = 500** (§5) hard-stops a loop |
| 2 | **Unbounded Places Autocomplete** on an address field (each keystroke = a billable request) | "B-h-a-r-a-t…" = 6 calls per field per user; forms hammer it | **Debounce + session tokens** in client, **and Places "per day" quota = 300** (§5) caps the blast radius |
| 3 | **An unrestricted / leaked key** (esp. the public browser key scraped from page source) | Bots replay it from any domain → thousands of map loads/day | **Referrer restriction (§3) + API restriction (§4) + Maps-JS "per day" quota = 2,000** (§5); server key never shipped to browser at all (§4) |

### 8. `.env.example` blocks for the new keys

**`bt-tracking-service/.env.example`** (server key only — never `NEXT_PUBLIC`):
```bash
# --- Google Maps Platform (SERVER key: Routes API + Places API New) ---
# Restricted to Routes API + Places API (New). Keep SECRET. Never expose to browser.
GOOGLE_MAPS_SERVER_KEY=AIza__SERVER_KEY_HERE__

# ETA/route cache TTL so we don't hammer Routes API (see cost guardrail #1)
ROUTE_CACHE_TTL_SECONDS=21600
```

**`driver/.env.example`** (browser key — public by design, referrer-locked):
```bash
# --- Google Maps Platform (BROWSER key: Maps JavaScript API ONLY) ---
# Public by design; safe because HTTP-referrer + API restricted in Cloud Console.
NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY=AIza__BROWSER_KEY_HERE__
NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID=__MAP_ID_HERE__
```

**`shipper/.env.example`** (same browser key, same restrictions):
```bash
# --- Google Maps Platform (BROWSER key: Maps JavaScript API ONLY) ---
# Public by design; safe because HTTP-referrer + API restricted in Cloud Console.
NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY=AIza__BROWSER_KEY_HERE__
NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID=__MAP_ID_HERE__
```

> The **same** browser key string goes in both frontends (both domains are in its referrer allow-list). The server key appears in **exactly one** place — `bt-tracking-service`. If you ever see `GOOGLE_MAPS_SERVER_KEY` in a `driver/` or `shipper/` file, that's a bug: delete it.

**One-line pre-flight checklist before you write any map code:**
`[ ] 3 APIs enabled (Maps JS, Routes, Places New)` · `[ ] Browser key: referrer + Maps-JS-only` · `[ ] Server key: Routes+Places, secret` · `[ ] Per-day quotas set (2000/500/300)` · `[ ] Budget ₹500 alert created` · `[ ] keys in .env (gitignored), not committed`

---

## 7. Testing plan — without a fleet, then with the Android phone

You will test the live map in **four escalating modes**, cheapest first:

| Mode | Tool | What it proves | Setup cost |
|---|---|---|---|
| A | **Route-replay GPS simulator** (this repo) | Driver "drives" the corridor in a browser; shipper map moves. No phone, no driving. | 1 file |
| B | **Chrome DevTools Sensors** | A single static coordinate renders correctly. | 0 |
| C | **Playwright** `setGeolocation` | Automated CI assertion: marker moves as points are pushed. | 1 test file |
| D | **Real Android phone + drive test** | The whole stack on real GPS, screen-lock, signal loss, deep-link. | tunnel/HTTPS |

The simulator (A) is the workhorse — it exercises the **real** `watchPosition → pushLocation → Redis → shipper poll → map` path end-to-end, with zero changes to your production code.

### A. Route-replay GPS simulator

**Design:** A `'use client'` module that, when a flag is set, **replaces `navigator.geolocation`** with a fake that interpolates along an encoded polyline (or GPX) at a configurable speed and emits positions to every `watchPosition()` callback. Because the driver page already calls the standard `navigator.geolocation.watchPosition()`, **nothing in the app changes** — the fake's positions flow straight into the existing `pushLocation()`. The shipper's existing 10s poll then animates the marker for free.

**Gating:** runs only if `?simulate=1` is in the URL **or** `NEXT_PUBLIC_GPS_SIM=1`. Never set that env in prod → dead code.

#### File 1 — `driver/src/lib/gps-sim.ts` (the engine, framework-free)

```ts
// driver/src/lib/gps-sim.ts
// Route-replay GPS simulator. Overrides navigator.geolocation behind a flag.
// Plays back an encoded polyline (Google format) at a configurable speed.

type SimOpts = {
  /** Google-encoded polyline OR array of [lat,lng] */
  path: string | [number, number][]
  /** ground speed in km/h (default 40) */
  speedKmh?: number
  /** position emit interval ms (default 1000) */
  intervalMs?: number
  /** loop back to start when finished (default false) */
  loop?: boolean
}

const R = 6371000 // earth radius m

function decodePolyline(str: string): [number, number][] {
  let index = 0, lat = 0, lng = 0
  const out: [number, number][] = []
  while (index < str.length) {
    let b, shift = 0, result = 0
    do { b = str.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
    lat += (result & 1) ? ~(result >> 1) : (result >> 1)
    shift = 0; result = 0
    do { b = str.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
    lng += (result & 1) ? ~(result >> 1) : (result >> 1)
    out.push([lat / 1e5, lng / 1e5])
  }
  return out
}

const toRad = (d: number) => (d * Math.PI) / 180
const toDeg = (r: number) => (r * 180) / Math.PI

function haversine(a: [number, number], b: [number, number]): number {
  const dLat = toRad(b[0] - a[0]), dLng = toRad(b[1] - a[1])
  const s = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(s))
}

function bearing(a: [number, number], b: [number, number]): number {
  const dLng = toRad(b[1] - a[1])
  const y = Math.sin(dLng) * Math.cos(toRad(b[0]))
  const x = Math.cos(toRad(a[0])) * Math.sin(toRad(b[0])) -
    Math.sin(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.cos(dLng)
  return (toDeg(Math.atan2(y, x)) + 360) % 360
}

/** linear interpolate fraction f (0..1) between two coords */
function lerp(a: [number, number], b: [number, number], f: number): [number, number] {
  return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]
}

export function installGpsSimulator(opts: SimOpts) {
  if (typeof window === 'undefined') return // SSR guard
  const pts = typeof opts.path === 'string' ? decodePolyline(opts.path) : opts.path
  if (pts.length < 2) { console.warn('[gps-sim] need >=2 points'); return }

  const speedMs = ((opts.speedKmh ?? 40) * 1000) / 3600 // m/s
  const interval = opts.intervalMs ?? 1000

  // Build cumulative distances so we can advance by real metres per tick
  const segLen: number[] = []
  let total = 0
  for (let i = 1; i < pts.length; i++) { const d = haversine(pts[i - 1], pts[i]); segLen.push(d); total += d }

  let traveled = 0
  const watchers = new Map<number, (p: GeolocationPosition) => void>()
  let nextId = 1
  let timer: ReturnType<typeof setInterval> | null = null

  function positionAt(dist: number): GeolocationPosition {
    let d = dist, seg = 0
    while (seg < segLen.length && d > segLen[seg]) { d -= segLen[seg]; seg++ }
    if (seg >= segLen.length) seg = segLen.length - 1
    const f = segLen[seg] ? d / segLen[seg] : 0
    const [lat, lng] = lerp(pts[seg], pts[seg + 1], f)
    const hdg = bearing(pts[seg], pts[seg + 1])
    return {
      coords: {
        latitude: lat, longitude: lng, accuracy: 5,
        altitude: null, altitudeAccuracy: null,
        heading: hdg, speed: speedMs,
        toJSON() { return this },
      } as GeolocationCoordinates,
      timestamp: Date.now(),
      toJSON() { return this },
    } as GeolocationPosition
  }

  function tick() {
    traveled += speedMs * (interval / 1000)
    if (traveled >= total) {
      if (opts.loop) traveled = 0
      else { traveled = total; stop() }
    }
    const pos = positionAt(traveled)
    watchers.forEach((cb) => cb(pos))
  }
  function start() { if (!timer) timer = setInterval(tick, interval) }
  function stop() { if (timer) { clearInterval(timer); timer = null } }

  const fake: Geolocation = {
    getCurrentPosition(success) { success(positionAt(traveled)) },
    watchPosition(success) {
      const id = nextId++
      watchers.set(id, success as (p: GeolocationPosition) => void)
      success(positionAt(traveled)) // immediate first fix
      start()
      return id
    },
    clearWatch(id) { watchers.delete(id); if (watchers.size === 0) stop() },
  }

  Object.defineProperty(navigator, 'geolocation', { value: fake, configurable: true })
  console.warn('[gps-sim] ACTIVE — fake GPS installed.',
    `${pts.length} pts, ${(total / 1000).toFixed(1)} km @ ${opts.speedKmh ?? 40} km/h`)
}
```

#### File 2 — gate it at app boot

Mount once, high in the driver tree. Add to `driver/src/app/(app)/layout.tsx` (or a tiny client component imported there):

```tsx
// driver/src/components/GpsSimBoot.tsx
'use client'
import { useEffect } from 'react'
import { installGpsSimulator } from '@/lib/gps-sim'
// Your pilot corridor encoded polyline. Generate once (see "How to get a polyline" below).
import { CORRIDOR_POLYLINE } from '@/lib/sim-routes'

export default function GpsSimBoot() {
  useEffect(() => {
    const flag =
      process.env.NEXT_PUBLIC_GPS_SIM === '1' ||
      new URLSearchParams(window.location.search).get('simulate') === '1'
    if (!flag) return
    const sp = new URLSearchParams(window.location.search)
    installGpsSimulator({
      path: CORRIDOR_POLYLINE,
      speedKmh: Number(sp.get('kmh')) || 50,
      loop: sp.get('loop') === '1',
    })
  }, [])
  return null
}
```

```tsx
// in driver/src/app/(app)/layout.tsx — render once
import GpsSimBoot from '@/components/GpsSimBoot'
// ...inside the returned JSX, near the top:
<GpsSimBoot />
```

```ts
// driver/src/lib/sim-routes.ts
// Paste the corridor polyline here (Google-encoded). Example shape only:
export const CORRIDOR_POLYLINE =
  'YOUR_ENCODED_POLYLINE_HERE'
// Fallback: a literal coord array also works:
// export const CORRIDOR_POLYLINE = [[28.61,77.20],[28.59,77.25], ...] as [number,number][]
```

#### How to get a polyline for your corridor (one-time)
Reuse the **Routes API** you're already building in `bt-tracking-service`: it returns `routes[].polyline.encodedPolyline`. Call it once for `source → dest`, copy the string into `sim-routes.ts`. (Or grab any path manually and store it as a `[lat,lng][]` array — the sim accepts both.)

#### Run it
```bash
# Terminal: start the stack (gateway + booking + redis), then the apps
make up                 # or docker-compose up
cd driver && npm run dev    # :3000-ish
cd shipper && npm run dev
```
1. Driver browser → open the in-transit booking with **`?simulate=1&kmh=60`**.
2. Console prints `[gps-sim] ACTIVE …`. The marker (or the existing lat/lng text) starts moving; each tick fires the real `pushLocation()` → Redis `loc:booking-driver:{bookingId}`.
3. Shipper browser → same booking. Its 10s `getBookingLocation()` poll returns the moving point → **map marker animates**.

```
┌────────── DRIVER (?simulate=1) ──────────┐        ┌──────── SHIPPER (no flag) ────────┐
│  fake navigator.geolocation              │        │  getBookingLocation() every 10s   │
│      │ watchPosition (UNCHANGED app code)│        │      │                            │
│      ▼                                   │        │      ▼                            │
│  pushLocation({lat,lng,heading,...})─────┼──HTTP──▶ POST /location/update             │
│                                          │  Redis │  GET /location/booking/:id ◀──────┤
│  🚚 marker creeps down corridor          │        │  🚚 marker creeps down corridor   │
└──────────────────────────────────────────┘        └───────────────────────────────────┘
```

**GPX option:** if you have a `.gpx`, parse `<trkpt lat lon>` into a `[lat,lng][]` and pass it as `path`. (10-line regex; not duplicated here — the engine already accepts the array form.)

### B. Chrome DevTools Sensors location override

Use for a **5-second sanity check** that one coordinate renders, *before* wiring the simulator.

1. DevTools → `⋮` → **More tools → Sensors**.
2. **Location** dropdown → "Other…" → type `lat, lng` (e.g. your pickup point), or pick a preset city.
3. Reload the booking page; `watchPosition` gets that fixed point once.

**Limits (why this is not enough):** it emits a **single static point** — no movement, no heading, no speed, no multiple updates. The marker appears but never moves, and ETA/off-route logic never changes. That gap is exactly what the simulator (A) fills.

### C. Playwright automated E2E (marker moves)

Playwright sets geolocation per-context and you can **call `setGeolocation()` repeatedly** to simulate a moving driver, then assert the shipper marker's screen position changes.

```ts
// tests/e2e/live-tracking.spec.ts
import { test, expect, chromium } from '@playwright/test'

const BOOKING_ID = process.env.E2E_BOOKING_ID!     // an in_transit booking
const DRIVER_TOKEN = process.env.E2E_DRIVER_TOKEN!  // bt_driver_token
const SHIPPER_TOKEN = process.env.E2E_SHIPPER_TOKEN! // bt_token
const DRIVER_URL = 'http://localhost:3000'
const SHIPPER_URL = 'http://localhost:3001'

// A few points walking down the corridor
const TRACK: [number, number][] = [
  [28.610, 77.200], [28.600, 77.220], [28.590, 77.240], [28.580, 77.260],
]

test('shipper marker tracks the driver', async () => {
  const browser = await chromium.launch()

  // DRIVER context: grant geo + seed token, open the booking page
  const driverCtx = await browser.newContext({
    permissions: ['geolocation'],
    geolocation: { latitude: TRACK[0][0], longitude: TRACK[0][1] },
  })
  const driver = await driverCtx.newPage()
  await driver.addInitScript(t => localStorage.setItem('bt_driver_token', t), DRIVER_TOKEN)
  await driver.goto(`${DRIVER_URL}/bookings/${BOOKING_ID}`)

  // SHIPPER context: open the same booking, grab a stable marker handle
  const shipperCtx = await browser.newContext({ permissions: ['geolocation'] })
  const shipper = await shipperCtx.newPage()
  await shipper.addInitScript(t => localStorage.setItem('bt_token', t), SHIPPER_TOKEN)
  await shipper.goto(`${SHIPPER_URL}/bookings/${BOOKING_ID}`)

  const marker = shipper.getByTestId('driver-marker') // add data-testid to the <AdvancedMarker>
  await expect(marker).toBeVisible({ timeout: 15_000 })
  const firstBox = await marker.boundingBox()

  // "Drive": move the driver's geolocation; app's watchPosition pushes each point
  for (const [lat, lng] of TRACK.slice(1)) {
    await driverCtx.setGeolocation({ latitude: lat, longitude: lng })
    await driver.evaluate(() => window.dispatchEvent(new Event('focus'))) // nudge watch if needed
    await shipper.waitForTimeout(11_000) // > shipper 10s poll interval
  }

  const lastBox = await marker.boundingBox()
  // Marker must have moved on screen
  expect(Math.abs(lastBox!.x - firstBox!.x) + Math.abs(lastBox!.y - firstBox!.y))
    .toBeGreaterThan(5)

  await browser.close()
})
```

**Notes:**
- Add `data-testid="driver-marker"` to the shipper map marker so the test has a stable handle (already shown in §5.E).
- Playwright's real Chromium `watchPosition` re-fires when `setGeolocation` changes — no app change needed.
- The 11s wait covers the shipper's 10s poll; for a faster CI you can temporarily drop `getBookingLocation`'s interval via an env, but 11s is fine for a single test.

### D. Real Android phone testing

**The one hard rule: `navigator.geolocation` only works in a SECURE CONTEXT (HTTPS).** `localhost` is treated as secure, but a **LAN IP like `http://192.168.x.x:3000` is NOT** → the phone silently returns no fix. Pick one of these (easiest first):

| Option | Command | When |
|---|---|---|
| **Tunnel (recommended)** | `cloudflared tunnel --url http://localhost:3000` → prints a `https://*.trycloudflare.com` URL. Open that on the phone. | Fastest. No certs, real HTTPS, works on cellular too. |
| ngrok | `ngrok http 3000` → use the `https://` forwarding URL. | Same idea; needs a free account/token. |
| mkcert (HTTPS over LAN) | `mkcert -install && mkcert 192.168.1.50 localhost` then run Next with HTTPS: `next dev --experimental-https` (Next 16 supports `--experimental-https`), import the mkcert root CA onto the Android device. | Offline / no internet. More steps (install CA on phone). |
| Deployed preview | Use your Cloud Run / Vercel preview URL directly. | Already HTTPS; closest to prod. |

**Tunnel gotcha:** you tunnel **two** apps (driver `:3000`, shipper on its own port). Run two `cloudflared` commands, or just tunnel the **gateway'd frontends** if you serve them behind one host. Also set `NEXT_PUBLIC_API_URL` to a tunneled gateway URL so the phone can reach `bt-gateway`.

**Android Chrome permissions + high accuracy:**
1. Open the HTTPS URL → Chrome shows a location prompt → **Allow**.
2. If you tapped Block earlier: Chrome `⋮` → site settings → **Location → Allow**, reload.
3. OS-level: Android **Settings → Location → ON**, and **Location → Location Services → Google Location Accuracy → ON** (uses Wi-Fi/cell for better fixes).
4. App-level: ensure Chrome itself has Location permission (Android **Settings → Apps → Chrome → Permissions → Location → Allow**).
5. Flip the driver page's watch to **`enableHighAccuracy: true`** for drive tests (currently `false`) — gate it behind a "drive test" flag so you don't drain battery in normal use.

### Live drive-test checklist

**Pre-drive setup**
- [ ] Phone on HTTPS (tunnel up, both apps reachable). Second device or laptop open on the **shipper** booking page.
- [ ] Booking is `in_transit`, driver assigned, `NEXT_PUBLIC_API_URL` → reachable gateway.
- [ ] Driver location permission = Allow; OS Location + Google Location Accuracy = ON.
- [ ] `enableHighAccuracy: true` active for this run.
- [ ] Charger/power bank in the cab (high-accuracy GPS drains fast).
- [ ] Remote console: open `chrome://inspect` on a laptop (USB debugging) **or** rely on a visible on-screen debug line showing last lat/lng + push count.

**During the drive — watch for:**
| Check | Expected | Where |
|---|---|---|
| Marker tracks | Driver 🚚 follows the road on shipper map, lag ≤ ~10s | shipper booking page |
| ETA updates | ETA from `bt-tracking-service` Routes proxy decreases over time | shipper header |
| Petrol pumps appear | Pump pins from Places "Search Along Route" render along the line | shipper/driver map |
| Deep-link opens | "Navigate" button opens the **Google Maps app** in navigate mode | driver booking page |
| Survives screen-lock | Lock the phone for 2 min → marker still updates (Wake Lock held) | shipper side |
| Store-and-forward | Drive through a no-signal patch → on reconnect, queued points flush; no permanent gap | shipper side |
| Status transitions | `arrived_pickup`/`in_transit`/`delivered` write `trip_events` rows | DB / ops web |

**Wake-lock note:** browser GPS pauses when the screen sleeps. Hold a Screen Wake Lock on the driver booking page (`await navigator.wakeLock.request('screen')`, re-acquire on `visibilitychange` — see §5.I). Test explicitly by locking the screen — if the marker freezes, the wake lock isn't holding. (Full background tracking later needs the Capacitor escape hatch; web wake-lock is the pilot solution.)

**Store-and-forward note:** if `pushLocation()` rejects (offline), queue the point in `localStorage` and flush on the next successful push / `online` event. The drive test through a dead zone is the only real validation of this.

**Capturing logs:**
- Driver: `chrome://inspect` (USB) → remote DevTools console + Network tab (watch `POST /location/update` 200s).
- Backend: `docker-compose logs -f bt-booking-service bt-tracking-service` — confirm location writes and Routes/Places proxy hits.
- Redis: `redis-cli --scan --pattern 'loc:*'` then `TTL loc:booking-driver:{bookingId}` (should hover near 30s while live).

### Backend tests — `bt-tracking-service`

Use `vitest` (mirrors what `bt-booking-service` uses). Three suites:

#### 1. Fuel model — unit (pure function, no I/O)
```ts
// bt-tracking-service/src/lib/fuel.ts  (the unit under test)
export type TruckClass = 'lcv' | 'medium' | 'hcv' | 'trailer'
const MILEAGE_KMPL: Record<TruckClass, number> = { lcv: 12, medium: 7, hcv: 4.5, trailer: 3.5 }

export function estimateFuel(distanceKm: number, cls: TruckClass, dieselPricePerL: number, laden = true) {
  if (distanceKm < 0) throw new Error('distance must be >= 0')
  const base = MILEAGE_KMPL[cls]
  const kmpl = laden ? base * 0.9 : base      // laden burns ~10% more
  const litres = distanceKm / kmpl
  return { litres: +litres.toFixed(2), cost: +(litres * dieselPricePerL).toFixed(2), kmpl }
}
```
```ts
// bt-tracking-service/test/fuel.test.ts
import { describe, it, expect } from 'vitest'
import { estimateFuel } from '../src/lib/fuel.js'

describe('estimateFuel', () => {
  it('laden HCV over 100km @ Rs.90/L', () => {
    const r = estimateFuel(100, 'hcv', 90, true)
    expect(r.kmpl).toBeCloseTo(4.05, 2)        // 4.5 * 0.9
    expect(r.litres).toBeCloseTo(24.69, 1)     // 100 / 4.05
    expect(r.cost).toBeCloseTo(2222.2, 0)
  })
  it('empty burns less than laden', () => {
    expect(estimateFuel(100, 'medium', 90, false).litres)
      .toBeLessThan(estimateFuel(100, 'medium', 90, true).litres)
  })
  it('zero distance → zero fuel', () => {
    expect(estimateFuel(0, 'lcv', 90).litres).toBe(0)
  })
  it('rejects negative distance', () => {
    expect(() => estimateFuel(-5, 'lcv', 90)).toThrow()
  })
})
```

#### 2. Off-route / geofence math — unit
```ts
// bt-tracking-service/src/lib/geo.ts
export function haversineM(a: [number, number], b: [number, number]) { /* same formula as gps-sim */ }
/** shortest distance (m) from point P to polyline pts */
export function distanceToRouteM(p: [number, number], pts: [number, number][]): number { /* per-segment min */ }
export function isOffRoute(p: [number, number], pts: [number, number][], thresholdM = 300) {
  return distanceToRouteM(p, pts) > thresholdM
}
export function withinGeofence(p: [number, number], center: [number, number], radiusM: number) {
  return haversineM(p, center) <= radiusM
}
```
```ts
// bt-tracking-service/test/geo.test.ts
import { describe, it, expect } from 'vitest'
import { isOffRoute, withinGeofence } from '../src/lib/geo.js'

const route: [number, number][] = [[28.61, 77.20], [28.60, 77.25], [28.59, 77.30]]

describe('off-route', () => {
  it('point ON the line is not off-route', () => {
    expect(isOffRoute([28.605, 77.225], route, 300)).toBe(false)
  })
  it('point ~2km away IS off-route', () => {
    expect(isOffRoute([28.63, 77.22], route, 300)).toBe(true)
  })
})
describe('geofence (pickup arrival)', () => {
  const pickup: [number, number] = [28.61, 77.20]
  it('inside 150m radius', () => expect(withinGeofence([28.6105, 77.2003], pickup, 150)).toBe(true))
  it('outside 150m radius', () => expect(withinGeofence([28.620, 77.210], pickup, 150)).toBe(false))
})
```

#### 3. Google proxy caching — integration (2nd call hits Redis, not Google)
Assert that the Routes/Places proxy **caches** so you stay inside the free caps. Mock `fetch` to Google and a real/mock Redis; the second identical request must **not** re-call `fetch`.

```ts
// bt-tracking-service/test/routes-cache.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'
import { trackingRoutes } from '../src/routes/tracking.js'

// In-memory redis stub (get/set/setex) — or use ioredis-mock
const store = new Map<string, string>()
const redisStub = {
  get: vi.fn(async (k: string) => store.get(k) ?? null),
  setex: vi.fn(async (k: string, _ttl: number, v: string) => { store.set(k, v) }),
}

const googleFetch = vi.fn(async () =>
  new Response(JSON.stringify({
    routes: [{ duration: '3600s', distanceMeters: 50000, polyline: { encodedPolyline: 'abc' } }],
  }), { status: 200 }))

beforeEach(() => { store.clear(); googleFetch.mockClear(); vi.stubGlobal('fetch', googleFetch) })

function build() {
  const app = Fastify()
  app.decorate('redis', redisStub as any)
  app.register(trackingRoutes)
  return app
}

describe('Routes proxy caching', () => {
  const body = { origin: { lat: 28.61, lng: 77.20 }, dest: { lat: 28.59, lng: 77.30 }, bookingId: 'b1' }

  it('first call hits Google, second call hits Redis', async () => {
    const app = build()

    const r1 = await app.inject({ method: 'POST', url: '/route', payload: body })
    expect(r1.statusCode).toBe(200)
    expect(googleFetch).toHaveBeenCalledTimes(1)        // Google called once
    expect(redisStub.setex).toHaveBeenCalledTimes(1)    // result cached

    const r2 = await app.inject({ method: 'POST', url: '/route', payload: body })
    expect(r2.statusCode).toBe(200)
    expect(googleFetch).toHaveBeenCalledTimes(1)        // STILL 1 → served from Redis
    expect(JSON.parse(r2.body).data.distanceMeters).toBe(50000)
  })
})
```
**Cache key convention:** `trk:route:{bookingId}` (one route per booking); for ad-hoc origin/dest routing round coords to ~4dp so near-identical requests share a cache entry; TTL ~45s for traffic-aware ETA, 6h for static distance/polyline. This is the single most important test for cost — a broken cache is what blows past the free caps.

**Run all backend tests:**
```bash
cd bt-tracking-service && npm test     # vitest run
```

---

## 8. Phased build roadmap + acceptance checks

Each phase is independently shippable. Build top-to-bottom — later phases assume earlier ones. Effort is for one non-expert solo dev.

```
P0 keys/caps ──▶ P1 shipper map ──▶ P2 tracking-svc + route/ETA ──▶ P3 driver nav + deep-link
                                              │                              │
                                              └──────────────┬───────────────┘
                                                             ▼
                                       P4 petrol pumps + fuel estimate ──▶ P5 route alerts ──▶ P6 simulator + drive test + harden
```

### Phase 0 — GMP project + keys + caps + hello-map  (~½ day)

**Goal:** A locked-down Google Cloud project with two restricted keys and a map that renders once.

**Do:**
1. New Cloud project → enable **only**: `Maps JavaScript API`, `Routes API`, `Places API (New)`. (Do NOT touch legacy Directions/Distance Matrix — a new project can't enable them anyway.)
2. Create **two** API keys (full steps in §6):
   - **Browser key** (`NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY`): *Application restriction* = HTTP referrers (`localhost:*`, your `*.vercel.app`, your phone's dev origin); *API restriction* = Maps JavaScript API only.
   - **Server key** (`GOOGLE_MAPS_SERVER_KEY`, lives in bt-tracking-service only): *Application restriction* = IP / none; *API restriction* = Routes API + Places API (New) only.
3. **Quotas** (Console → APIs → Quotas): set per-minute + per-day caps low (Routes 500/day, Places 300/day, Maps JS 2000/day) so a leaked key can't drain the cap. A billing budget only *alerts* — quotas are the only hard stop.
4. Install in `shipper/` (and later `driver/`): `npm i @vis.gl/react-google-maps @googlemaps/polyline-codec`.

**Files:** `shipper/.env.local`, `driver/.env.local` (browser key); Cloud Console only for the rest.

**Done when:** A throwaway `'use client'` `<APIProvider><Map/></APIProvider>` renders a centered India map in the shipper app at `localhost`, and the key is referrer-restricted (pasting it on a random site fails).

### Phase 1 — Shipper live map over the EXISTING polling  (~1 day)

**Goal:** Replace the raw-text lat/lng on the shipper booking page with a live map. **Zero backend change** — reuse `getBookingLocation()` (already polling `/api/location/booking/:id` every 10s).

**Files touched:**
- `shipper/src/app/bookings/[id]/page.tsx` — swap the lat/lng text block for `<LiveTrackMap/>` (the shared component from §5.E; for this first cut you can render origin/dest pins + the live truck marker without a route line, then add the polyline in P2).
- `shipper/src/components/maps/LiveTrackMap.tsx` — **new** (the shared component).

```tsx
// minimal first-cut shipper map (no route line yet — added in P2)
'use client'
import { APIProvider, Map, AdvancedMarker, Pin } from '@vis.gl/react-google-maps'

type LatLng = { lat: number; lng: number }
export default function LiveTrackMapMinimal({
  driver, source, dest,
}: { driver: LatLng | null; source: LatLng; dest: LatLng }) {
  const center = driver ?? source
  return (
    <APIProvider apiKey={process.env.NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY!}>
      <div className="h-72 w-full overflow-hidden rounded-xl">
        <Map mapId={process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? 'DEMO_MAP_ID'}
             defaultCenter={center} defaultZoom={9}
             gestureHandling="greedy" disableDefaultUI>
          <AdvancedMarker position={source}><Pin background="#16a34a"/></AdvancedMarker>
          <AdvancedMarker position={dest}><Pin background="#dc2626"/></AdvancedMarker>
          {driver && (
            <AdvancedMarker position={driver}>
              <div className="text-2xl">🚚</div>
            </AdvancedMarker>
          )}
        </Map>
      </div>
    </APIProvider>
  )
}
```

```
SHIPPER  /bookings/[id]            (status: in_transit)
┌──────────────────────────────────────────────┐
│  Mumbai  →  Pune        ETA: 2h 40m  (P2)      │
│ ┌──────────────────────────────────────────┐ │
│ │   (green)pickup ····· 🚚 ·····> (red)drop │ │ ← live map, driver marker
│ │                                          │ │   re-renders on 10s poll
│ └──────────────────────────────────────────┘ │
│  Last update: 6s ago      Speed: 54 km/h      │
└──────────────────────────────────────────────┘
```

**Done when:** Open a booking in `in_transit`; the truck marker moves as the driver app pings; if the location 404s (driver offline / TTL expired) the map still shows pickup+drop pins and a "Driver offline" note.

### Phase 2 — bt-tracking-service skeleton + route compute/cache + ETA read-through  (~1–2 days)

**Goal:** Stand up the new service. First endpoint computes a route once (polyline + ETA), caches it in Redis, and serves a cheap ETA read-through.

**Scaffold (copy bt-booking-service):**
- New dir `bt-tracking-service/` — copy `package.json`, `tsconfig.json`, `Dockerfile`, `src/plugins/auth.ts`, redis plugin, supabase plugin. Port **3006**.
- `docker-compose.yml`: add `bt-tracking-service` (port 3006, same env block + `GOOGLE_MAPS_SERVER_KEY`).
- `Makefile`: add `bt-tracking-service` to `BACKEND_SVCS`.
- `bt-gateway/nginx.conf.template` + `bt-gateway/docker-entrypoint.sh`: add the `/api/tracking/` block + `TRACKING_SERVICE_URL`/`TRACKING_SERVICE_HOST` (full snippets in §3.5).

**Endpoint** `GET /tracking/route/:bookingId` (auth required; shipper must own booking / driver must be assigned — reuse the booking-service ownership check pattern):

```ts
// bt-tracking-service/src/routes/route.ts (core)
const cacheKey = `trk:route:${bookingId}`
const cached = await redis.get(cacheKey)
if (cached) return reply.send({ success: true, data: JSON.parse(cached) })

// fetch booking source/dest from supabase (bookings.source_lat/lng, dest_lat/lng)
const body = {
  origin:      { location: { latLng: { latitude: src.lat, longitude: src.lng } } },
  destination: { location: { latLng: { latitude: dst.lat, longitude: dst.lng } } },
  travelMode: 'DRIVE',
  routingPreference: 'TRAFFIC_UNAWARE', // route geometry is static → Essentials tier (cheap). The live traffic-aware ETA (Pro) comes from the separate /eta endpoint.
}
const res = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': process.env.GOOGLE_MAPS_SERVER_KEY!,
    // FIELD MASK IS MANDATORY — request 400s without it, and it sets the SKU/price
    'X-Goog-FieldMask': 'routes.duration,routes.staticDuration,routes.distanceMeters,routes.polyline.encodedPolyline',
  },
  body: JSON.stringify(body),
})
const r = (await res.json()).routes[0]
const data = {
  encodedPolyline: r.polyline.encodedPolyline,
  distanceMeters:  r.distanceMeters,
  durationSec:     Number(String(r.staticDuration).replace('s','')),
}
await redis.set(cacheKey, JSON.stringify(data), 'EX', 21600) // route fixed per booking → cache 6h
return reply.send({ success: true, data })
```

The shipper map decodes the polyline (`@googlemaps/polyline-codec`) and draws the route line; ETA = `durationSec`.

**Done when:** `GET /api/tracking/route/:bookingId` returns polyline + ETA on first call (Routes API), and a second call within the TTL returns instantly from Redis (no GMP hit — confirm via Cloud Console metrics: 1 Routes call per booking). Shipper map now draws the route line + an ETA label.

### Phase 3 — Driver navigation screen + deep-link handoff  (~1 day)

**Goal:** Driver sees the same route map plus a big "Navigate" button that hands off to the phone's Google Maps app. **No in-app turn-by-turn.**

**Files touched:**
- `driver/src/app/(app)/bookings/[id]/page.tsx` — add the map (reuse `LiveTrackMap`, centered on driver's own position) + the `DriverNavPanel` from §5.H + a Navigate button.
- `driver/src/lib/navigation.ts` — **new**, pure deep-link builder (full code in §5.F; no GMP key, free).

Show **two** navigation targets depending on trip stage: "Navigate to Pickup" (status `accepted`) → dest = source coords; "Navigate to Drop" (status `in_transit`) → dest = dest coords.

```
DRIVER  /bookings/[id]            (status: in_transit)
┌──────────────────────────────────────────────┐
│ ┌──────────────────────────────────────────┐ │
│ │   you 🚚 ·······route······> (red)drop    │ │ ← own GPS centered
│ │   ⏱ etc.                                  │ │
│ └──────────────────────────────────────────┘ │
│  120 km left · ETA 2h 40m                      │
│ ┌────────────────────────────────────────────┐│
│ │   ▶  NAVIGATE TO DROP (opens Google Maps)  ││ ← deep link
│ └────────────────────────────────────────────┘│
│  [ Mark Delivered ]                            │
└──────────────────────────────────────────────┘
```

**Done when:** On your Android phone, tapping "Navigate" opens the Google Maps app already in driving-navigation mode to the right coordinate; the in-app map still shows the route while GPS continues streaming (existing `watchPosition`).

### Phase 4 — Petrol pumps + fuel estimate  (~1–2 days)

**Goal:** Along-route fuel pumps + a diesel cost estimate, both from the cached polyline.

**New endpoints (bt-tracking-service):**
- `GET /tracking/pumps/:bookingId` (a.k.a. fuel-stops) — Places API (New) **Text Search "Search Along Route"**, passing the cached `encodedPolyline`:
  ```ts
  fetch('https://places.googleapis.com/v1/places:searchText', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': process.env.GOOGLE_MAPS_SERVER_KEY!,
      'X-Goog-FieldMask': 'places.displayName,places.location,places.formattedAddress', // keeps cheap SKU
    },
    body: JSON.stringify({
      textQuery: 'petrol pump',
      searchAlongRouteParameters: { polyline: { encodedPolyline } },
    }),
  })
  ```
  Cache result `trk:pumps:{bookingId}` for 6h (same fixed route). Trim to N results server-side (Open Decision #4).
- `POST /fuel/estimate` (or `GET /tracking/fuel-estimate/:bookingId?mileage=X&price=Y`) — **pure math, no GMP call**:
  ```ts
  const km     = distanceMeters / 1000
  const litres = km / mileage                 // mileage km/L from vehicle class
  const cost   = litres * pricePerLitre        // ₹/L, default state diesel price
  // benchmarks: LCV 10–14, medium 6–8, HCV 3.5–5, trailer-laden 3–4
  ```
  Prefill `mileage` from the driver's vehicle class when known; let it be overridden.

**UI:** fuel pumps as horizontal-scroll cards (⛽, tap = deep-link) + an estimate card "≈ 32 L · ≈ ₹2,880 diesel" on the driver booking page (see §5.H wireframe).

**Done when:** Pumps endpoint returns pumps near the corridor in one Places call (verify in Cloud metrics), the estimate card shows litres + ₹ for a real corridor, and re-requests hit Redis not GMP.

### Phase 5 — Route alerts  (~1 day)

**Goal:** Lightweight, derived-from-existing-data alerts. No new data ingestion — compute from the GPS pings already in Redis + the cached polyline.

**Where:** a small evaluator in bt-tracking-service, called either on shipper poll (`GET /tracking/alerts/:bookingId`) or piggy-backed on the location read. Persisted to `route_alerts` (migration 009); driver-raised alerts come via `POST /alerts`.

**Alerts (all pure geometry / time math):**
| Alert | Rule (defaults — Open Decision #5) |
|---|---|
| Off-route | driver point > **500 m** from nearest polyline point |
| Idle / stopped | speed < 3 km/h for > **15 min** (track `idle_since` in a Redis key) |
| Stale GPS | no location (Redis key TTL'd out, >30s) → "Driver offline" |
| Near drop | within **2 km** of dest → notify shipper "arriving soon" |

Reuse the existing FCM path (booking service fires push) for the shipper-facing ones; keep in-app banners for the rest to avoid coupling.

```
SHIPPER booking page — alert banner
┌──────────────────────────────────────────────┐
│ ⚠ Driver appears stopped (18 min near Lonavla)│
└──────────────────────────────────────────────┘
```

**Done when:** Forcing each condition (drag a sim point off-route; stop the sim; let GPS go stale) raises the correct banner within one poll cycle, and clears when resolved.

### Phase 6 — GPS simulator + drive test + harden  (~1–2 days)

**Goal:** Test movement without driving; then one real drive; then lock costs.

**Route-replay simulator** — two equivalent ways to drive movement, both reusing the real `POST /api/location/update`:
1. **In-app (recommended):** the `?simulate=1` browser simulator from §7.A — overrides `navigator.geolocation`, so the *exact* production `watchPosition → pushLocation` path runs.
2. **Standalone script** (handy for CI / headless):
   ```
   tools/gps-sim.ts
     1. login as a driver → JWT
     2. computeRoutes for the booking → decode polyline → list of points
     3. loop points, POST /location/update {lat,lng,heading,speed_kmh,booking_id}
        every 3s (interpolate for smoothness)
     run: TOKEN=... BOOKING=... npx tsx tools/gps-sim.ts
   ```
This drives the shipper map, ETA, alerts, and fuel UI end-to-end from your desk.

**Drive test:** open driver app on your Android phone, accept a real pilot booking, drive part of the corridor; watch shipper map on a second device (full checklist in §7.D).

**Harden checklist:**
- Confirm both keys are restricted; re-check quotas; switch off the demo key.
- Verify cache TTLs (route/pumps 6h, ETA 45s, location 30s) — re-check Cloud metrics show ~1 Routes + ~1 Places call **per booking**, well inside free caps for 20 users.
- Graceful degradation: every GMP failure → map/route hides, app still functional (text fallback already exists).

**Done when:** A full booking lifecycle runs entirely on the simulator with map+ETA+pumps+alerts all live, one real drive validates GPS accuracy, and Cloud Console shows usage ≈ ₹0 inside free caps.

---

## 9. React Native portability map

When the pilot graduates web → React Native, **all backend + business logic is reused unchanged**; only the device/UI shell is swapped.

| Layer | Web (now) | RN (later) | Carries over? |
|---|---|---|---|
| **bt-tracking-service** (route/ETA/fuel/alerts) | HTTP via gateway | **identical HTTP** | ✅ UNCHANGED |
| **bt-booking-service** location ingest/read | `/api/location/*` | **identical HTTP** | ✅ UNCHANGED |
| **Auth** | JWT Bearer `{userId,role}` | same header | ✅ UNCHANGED |
| **Deep-link navigation** | `https://maps/dir/?api=1...` | same URL via `Linking.openURL` (or `google.navigation:` intent) | ✅ UNCHANGED |
| **Fuel / alert math** | server-side TS | same server-side TS | ✅ UNCHANGED |
| **Route polyline decode** | `@googlemaps/polyline-codec` | RN maps `Polyline` coords | ✅ logic same, render swapped |
| **Map render** | `@vis.gl/react-google-maps` | `react-native-maps` (Google provider) | 🔁 SWAP (same markers/concepts) |
| **GPS capture** | `navigator.geolocation.watchPosition` | RN background geolocation lib | 🔁 SWAP (true background tracking — *better* on RN) |
| **Token storage** | `localStorage` (`bt_driver_token`/`bt_token`) | secure storage / Keychain | 🔁 SWAP |
| **Screen-on during drive** | Web Wake Lock | native keep-awake / foreground service | 🔁 SWAP (more reliable on RN) |

**Conclusion:** The only throwaway code is the *map component wrapper and the device-API glue* (~2 files per app). Every endpoint, the entire tracking service, the deep-link handoff, and all fuel/alert/ETA logic move over **verbatim**. The pilot is a forward investment, not a prototype.

---

## 10. Decisions — confirmed (2026-06-18)

All eight choices below are now locked with the user. **Build to these.** Each remains reversible later, but no further confirmation is needed to start.

1. **Persist location history to DB → YES.** `location_history` (migration 009) is **enabled** — capture a **throttled breadcrumb trail (~1 point / 10-15s)** for route replay, payment/delivery disputes, and audit from day one. Append-only, pruned by `recorded_at`.
2. **Polling vs WebSocket → stay on 10s polling for the pilot.** Revisit WS (Fastify `ws` is already a dep in booking-service) only if >50 concurrent viewers or sub-5s freshness is demanded.
3. **ETA → TRAFFIC-AWARE (Pro tier).** The live `/eta` endpoint runs `TRAFFIC_AWARE` for accurate, traffic-adjusted ETAs; the cached *route* polyline stays `staticDuration`/Essentials. Monitor the Pro free cap — if usage nears it, widen the ETA cache TTL (currently 45s) or fall back to `TRAFFIC_UNAWARE`.
4. **Petrol pumps → top 8 along route**, trimmed server-side, refreshed once per booking (6h cache).
5. **Alert thresholds → 500 m off-route, 15 min idle, 2 km near-drop.** Tune after the first real drive (GPS noise may push off-route toward ~750 m).
6. **Fuel inputs → prefill mileage from vehicle class + editable price.** Driver can correct the km/L; diesel price defaults to `DIESEL_PRICE_INR=90` and is editable per corridor (state-dependent ₹88–95/L).
7. **PWA → add a minimal manifest + service worker now** (no offline caching) for home-screen install + reliable Wake Lock during drives. ~1 file; directly improves the drive test. Full offline waits for React Native.
8. **`LiveTrackMap` → copy into each app**, guarded by `scripts/sync-maps.sh` so the two copies don't drift; extract to a shared package at the React Native stage.
