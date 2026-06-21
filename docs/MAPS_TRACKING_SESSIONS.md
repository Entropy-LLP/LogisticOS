# Maps & Tracking — How to run the build across sessions

> You're building Maps & Tracking as **one focused Claude session per phase** (decision D-013). This file is your playbook: the per-session ritual, the phase→session map, and a **copy-paste kickoff prompt** for each phase. Start each new session by pasting the matching prompt.

The four docs that make this work:
- [MAPS_TRACKING_PLAN.md](MAPS_TRACKING_PLAN.md) — the full design (read the sections relevant to your phase).
- [MAPS_TRACKING_CONTRACT.md](MAPS_TRACKING_CONTRACT.md) — the **frozen interface** (endpoints, env keys, schema, snake_case). Build to it exactly.
- [MAPS_TRACKING_DECISIONS.md](MAPS_TRACKING_DECISIONS.md) — **append-only** log of every dynamic decision. Read first, append last.
- This file — the session runbook.

---

## The session ritual (do this every time)

**At the START of a session:**
1. Read `MAPS_TRACKING_CONTRACT.md` and `MAPS_TRACKING_DECISIONS.md` in full (they're short).
2. Read only the PLAN sections your phase touches (each kickoff prompt names them).
3. Restate the phase goal + its "done when" before writing code.

**While working:**
4. Build to the **frozen contract** (snake_case, the §2 endpoints, the env-key names). If something forces a contract change, follow the CONTRACT's **Change protocol**.
5. When you make a choice that affects another service/app or a threshold/cost, **append a `D-###` entry** to the decision log. If it's a real product fork, **ask the user** first, then log the answer.
6. Don't touch GPS ingestion (`bt-booking-service/src/routes/location.ts`) — it's frozen (D-010).

**At the END of a session:**
7. **Verify it actually works** — build/run/test the slice (use the `/verify` or `/run` skill). State honestly what passed and what didn't.
8. Append any decisions you made to `MAPS_TRACKING_DECISIONS.md`; bump the CONTRACT version if you changed a frozen field.
9. Commit on a branch named for the phase (e.g. `feat/maps-phase-2-tracking-service`), open a PR, and write a 3-line summary of what's done + what the next phase needs.

---

## Phase → session map

| Phase | Session goal | Main files | Done when |
|---|---|---|---|
| **0** | GMP project + 2 restricted keys + per-API quota caps + a hello-map | Google Cloud Console (you), `*/.env.local` | A bare map renders with the browser key; quota caps + budget alert set; server key restricted to Routes+Places. |
| **1** | Shipper live map over the **existing** location polling | `shipper/...bookings/[id]/page.tsx`, new `LiveTrackMap` | Shipper sees a moving truck marker fed by the current `getBookingLocation()` poll. |
| **2** | `bt-tracking-service` skeleton + route compute/cache + ETA read-through + migration 009 | new `bt-tracking-service/`, `supabase/migrations/009_maps_tracking.sql`, gateway, docker-compose | `GET /api/tracking/track/:bookingId` returns location+route+eta; 2nd call hits Redis (no Google). |
| **3** | Driver navigation screen + Google Maps deep-link handoff | `driver/...bookings/[id]/page.tsx`, `driver/src/lib/navigation.ts` | Driver sees route map + a "Navigate" button that opens Google Maps to pickup/drop. |
| **4** | Petrol pumps along route + fuel estimate | `bt-tracking-service` pumps/fuel routes, driver UI panels | Driver sees ≤8 pumps ahead + a litres/₹ fuel card. |
| **5** | Route alerts (off-route / geofence / idle / eta-slip) | `bt-tracking-service` alerts + geo math, both UIs | Alerts raise on the thresholds in D-005 and show in both apps. |
| **6** | GPS route-replay simulator + Android drive test + hardening | `*/src/lib/gps-sim.ts`, tests | Simulator "drives" the corridor and the shipper map moves; real drive test passes the §8 checklist. |

> Phases are ordered by dependency. **Phase 0 is required before any map code.** Each phase is ~a day or few of solo work and is independently shippable.

---

## Copy-paste kickoff prompts

Paste the matching block as your first message in a fresh session. (Each one assumes the repo root and the four docs above.)

### Phase 0 — Google Cloud setup + cost caps
```
You are doing Phase 0 of the BharatTruck Maps & Tracking build.
First read docs/MAPS_TRACKING_CONTRACT.md and docs/MAPS_TRACKING_DECISIONS.md, then docs/MAPS_TRACKING_PLAN.md §7 (Google Maps Platform setup + cost guardrails).
Goal: walk me (non-expert) click-by-click through creating a Google Cloud project, enabling EXACTLY Maps JavaScript API + Routes API + Places API (New), creating the two restricted keys (browser key = referrer-restricted + Maps-JS-only; server key = Routes+Places only, secret), setting per-API QUOTA LIMITS as the hard cap, and a billing budget alert. Then help me put NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY + NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID into driver/.env.local and shipper/.env.local and GOOGLE_MAPS_SERVER_KEY where the tracking-service will read it. Finish by rendering a bare map in one app to prove the browser key works.
Stop and ask me whenever a step needs my Google account. Follow the end-of-session ritual in docs/MAPS_TRACKING_SESSIONS.md.
```

### Phase 1 — Shipper live map
```
You are doing Phase 1 of the BharatTruck Maps & Tracking build.
Read docs/MAPS_TRACKING_CONTRACT.md and docs/MAPS_TRACKING_DECISIONS.md, then docs/MAPS_TRACKING_PLAN.md §5 (Frontend & UI — shipper live map + the LiveTrackMap component).
Goal: replace the text-only tracking panel in shipper/src/app/bookings/[id]/page.tsx with a real Google map (@vis.gl/react-google-maps) showing a smoothly-animated truck marker + origin/dest pins, fed by the EXISTING getBookingLocation() 10s poll. Do NOT build the tracking-service yet and do NOT change the GPS pipeline. Handle loading / waiting-for-driver / live / stale(>30s) / delivered states. Build to the frozen contract (snake_case).
Verify with the route-replay idea or DevTools sensors before declaring done. Follow the session ritual.
```

### Phase 2 — bt-tracking-service + migration 009
```
You are doing Phase 2 of the BharatTruck Maps & Tracking build.
Read docs/MAPS_TRACKING_CONTRACT.md and docs/MAPS_TRACKING_DECISIONS.md, then docs/MAPS_TRACKING_PLAN.md §3 (backend service) and §4 (migration 009).
Goal: scaffold bt-tracking-service (Node20/TS/Fastify, port 3006) per the existing service recipe — copy the auth + supabase + redis plugins, add the server-side Google proxy (Routes API) with the Redis cache + stampede guard, implement endpoints #1,#2,#3,#8 from the contract, and write supabase/migrations/009_maps_tracking.sql (trip_routes, fuel_estimates, route_alerts, location_history — all anchored on booking_id). Wire the gateway (/api/tracking/), docker-compose, and Makefile. Use GOOGLE_MAPS_SERVER_KEY server-side only; field masks are mandatory; /eta is TRAFFIC_AWARE, route is staticDuration.
Done when GET /api/tracking/track/:bookingId returns location+route+eta and a 2nd call within TTL is Redis-served (confirm: 1 Routes call per booking). Follow the session ritual; append any decisions.
```

### Phase 3 — Driver navigation + deep-link
```
You are doing Phase 3 of the BharatTruck Maps & Tracking build.
Read docs/MAPS_TRACKING_CONTRACT.md and docs/MAPS_TRACKING_DECISIONS.md, then docs/MAPS_TRACKING_PLAN.md §5 (driver navigation screen + the deep-link helper).
Goal: build the driver navigation view in driver/src/app/(app)/bookings/[id]/page.tsx — reuse LiveTrackMap centered on the driver's own position, show distance + ETA, and a big "Navigate" button. Create driver/src/lib/navigation.ts (pure deep-link builder, no Google key) that opens the phone's Google Maps app to pickup (status accepted) or drop (status in_transit), with an Android intent + iOS fallback. Keep the driver's existing watchPosition→pushLocation loop; add a Wake Lock so GPS survives screen-lock during a drive (D-007).
Verify the deep link opens Google Maps on your Android phone. Follow the session ritual.
```

### Phase 4 — Petrol pumps + fuel estimate
```
You are doing Phase 4 of the BharatTruck Maps & Tracking build.
Read docs/MAPS_TRACKING_CONTRACT.md and docs/MAPS_TRACKING_DECISIONS.md, then docs/MAPS_TRACKING_PLAN.md §3 (pumps + fuel endpoints) and §5 (driver panels) and §6 (fuel model).
Goal: implement endpoints #4 (pumps — Places API New Search-Along-Route, default 8, cached 6h) and #5 (fuel/estimate — pure math, prefill mileage by vehicle class, editable diesel_price default 90) in bt-tracking-service, then add the "Petrol pumps ahead" horizontal list (tap = deep-link to that pump) and the fuel-cost card to the driver screen. Reuse the already-cached route polyline for pumps — never recompute a route just to find pumps.
Done when the driver sees ≤8 real pumps ahead + a litres/₹ estimate. Follow the session ritual.
```

### Phase 5 — Route alerts
```
You are doing Phase 5 of the BharatTruck Maps & Tracking build.
Read docs/MAPS_TRACKING_CONTRACT.md and docs/MAPS_TRACKING_DECISIONS.md, then docs/MAPS_TRACKING_PLAN.md §3 (alerts) and §6/§7 (route-alert features).
Goal: implement endpoints #6/#7 (raise/list alerts) plus the server-side alert engine — off-route (>500 m from polyline, D-005), geofence arrival at pickup/delivery, long-idle (>15 min), eta-slip — using cheap haversine/point-to-polyline math (no PostGIS). Surface alerts in both the shipper read-through (#8) and the driver/shipper UIs. Also write throttled breadcrumbs to location_history (~1 pt/10-15s, D-001).
Tune thresholds against one real drive and LOG the revised numbers as a new D-### entry. Follow the session ritual.
```

### Phase 6 — GPS simulator + drive test + hardening
```
You are doing Phase 6 of the BharatTruck Maps & Tracking build.
Read docs/MAPS_TRACKING_CONTRACT.md and docs/MAPS_TRACKING_DECISIONS.md, then docs/MAPS_TRACKING_PLAN.md §8 (testing plan).
Goal: build the route-replay GPS simulator (override navigator.geolocation behind ?simulate=1 / NEXT_PUBLIC_GPS_SIM=1, playing an encoded-polyline path through watchPosition) so the driver app can "drive" the corridor and the shipper map moves with zero hardware. Add the Playwright geolocation e2e test, the backend unit tests (fuel model + off-route/geofence math + cache-hit), and prep the Android real-drive test (HTTPS tunnel for secure-context geolocation). Run the §8 drive-test checklist.
Done when the simulator drives end-to-end and the real Android drive test passes. Follow the session ritual; this phase closes Phase 1 scope.
```

---

## When a new decision comes up mid-session

1. Is it mechanical (a name inside one file)? → just do it, no log entry.
2. Does it affect another service/app, a contract field, a threshold, cost, or scope? → **append a `D-###` entry** to the decision log.
3. Is it a genuine product fork with no obvious right answer? → **ask the user** (use the question tool), then log their answer.

That's the whole mechanism: decisions live in one append-only file every session reads — so a choice made building the backend is automatically known to the session building the frontend.
