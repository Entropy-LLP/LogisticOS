# Maps & Tracking — Decision Log (append-only)

> **This is how decisions made in one Claude session reach every other session.** It is **append-only**: never delete or rewrite a past entry — if a decision changes, add a *new* entry that supersedes it (and note `Supersedes: D-xxx`). Every session must **read this file before building** and **append any new decision before finishing**.
>
> A "decision" = any choice that affects another service/app, a contract field, a threshold, a cost, or scope. Mechanical, self-contained choices (variable names inside one function) don't need an entry.
>
> When you hit a genuine **product fork** (not a mechanical choice), use the question tool to ask the user, then log their answer here.

**How to add an entry:** copy the template at the bottom, give it the next `D-###`, fill it in, append.

Related: [MAPS_TRACKING_PLAN.md](MAPS_TRACKING_PLAN.md) (design) · [MAPS_TRACKING_CONTRACT.md](MAPS_TRACKING_CONTRACT.md) (frozen interface) · [MAPS_TRACKING_SESSIONS.md](MAPS_TRACKING_SESSIONS.md) (how to run sessions).

---

## Confirmed decisions

### D-001 — Persist location history: YES
- **Date:** 2026-06-18 · **By:** user
- **Decision:** Enable the `location_history` table (migration 009). Capture a **throttled breadcrumb trail (~1 point / 10–15s)**, not every ping. Append-only, pruned by `recorded_at`.
- **Why:** route replay, payment/delivery dispute resolution, audit from day one.
- **Impact:** migration 009 includes `location_history`; tracking-service writes throttled inserts.

### D-002 — Real-time transport: 10s HTTP polling for the pilot
- **Date:** 2026-06-18 · **By:** user
- **Decision:** Keep the existing 10s polling. Do not build WebSocket/Realtime now.
- **Why:** already works, lowest effort, fine for ~20 users.
- **Impact:** revisit WS (Fastify `ws` already a dep) only at >50 concurrent viewers or if sub-5s freshness is demanded.

### D-003 — ETA: traffic-aware (Pro tier)
- **Date:** 2026-06-18 · **By:** user
- **Decision:** The live `/eta` endpoint runs Routes API `TRAFFIC_AWARE` (Pro tier). The cached **route** polyline stays `staticDuration` (Essentials).
- **Why:** accurate, traffic-adjusted ETAs matter more than the marginal cost at pilot scale.
- **Impact:** watch the Pro free cap; if approached, widen `trk:eta` TTL (45s) or fall back to `TRAFFIC_UNAWARE`.

### D-004 — Petrol pumps: top 8 along route
- **Date:** 2026-06-18 · **By:** user
- **Decision:** `GET /api/tracking/pumps/:bookingId` defaults to **8** pumps, trimmed server-side, refreshed once per booking (6h cache).
- **Impact:** overrides the plan's `?limit=10` example. Contract endpoint #4 default = 8.

### D-005 — Alert thresholds (initial)
- **Date:** 2026-06-18 · **By:** user
- **Decision:** off-route **500 m**, idle **15 min**, near-drop **2 km**. Tune after the first real drive (GPS noise may push off-route toward ~750 m).
- **Impact:** these are config constants in tracking-service; expect one revision (log it as a new entry) after the drive test.

### D-006 — Fuel inputs: prefill mileage + editable price
- **Date:** 2026-06-18 · **By:** user
- **Decision:** Auto-fill `mileage_kmpl` from the vehicle class; driver can correct it. Diesel price defaults to `DIESEL_PRICE_INR=90`, editable per request (state-dependent ₹88–95/L).
- **Impact:** `POST /api/tracking/fuel/estimate` accepts optional `mileage_kmpl` + `diesel_price` overrides.

### D-007 — PWA: add a minimal manifest + service worker now
- **Date:** 2026-06-18 · **By:** user
- **Decision:** Add a minimal `manifest.json` + a no-op/registration service worker to both apps now (no offline caching).
- **Why:** home-screen install + reliable Wake Lock during drives; ~1 file; improves the drive test.
- **Impact:** full offline caching deferred to React Native.

### D-008 — `LiveTrackMap`: copy per app
- **Date:** 2026-06-18 · **By:** user
- **Decision:** Copy the `LiveTrackMap` component into each app (driver + shipper are separate Next projects). Guard against drift with `scripts/sync-maps.sh`.
- **Impact:** extract to a shared package only at the React Native stage.

### D-009 — Maps provider: Google Maps Platform
- **Date:** 2026-06-18 · **By:** user
- **Decision:** Use Google Maps Platform (Routes API + Places API New + Maps JS). Initially considered free/open-source to cut cost, then reversed: "we do not have the liberty to make complexities" → ease over cost.
- **Impact:** cost controlled via restricted keys + per-API quota caps (a billing budget only *alerts*).

### D-010 — New service, GPS ingestion stays put
- **Date:** 2026-06-18 · **By:** user + design
- **Decision:** Build a new `bt-tracking-service` (port 3006) for routing/ETA/pumps/fuel/alerts. **Leave** GPS ingestion in `bt-booking-service` untouched; tracking-service is read-only on `loc:*` Redis keys.
- **Impact:** no changes to `bt-booking-service/src/routes/location.ts`.

### D-011 — Navigation: deep-link handoff
- **Date:** 2026-06-18 · **By:** user
- **Decision:** No in-app turn-by-turn. The driver's "Navigate" button deep-links to the phone's Google Maps app (`https://www.google.com/maps/dir/?api=1&...&dir_action=navigate`, Android intent fallback). Free; identical in React Native later.

### D-012 — API field casing: snake_case (resolves the plan's drift)
- **Date:** 2026-06-18 · **By:** design
- **Decision:** All Maps & Tracking API JSON uses **`snake_case`** (e.g. `distance_m`, `eta_s`, `speed_kmh`), and the **`:bookingId` path-param** endpoint style is canonical.
- **Why:** matches the existing `bt-booking-service` location API and the frontend `DriverLocation` type; the PLAN's §5 camelCase query-string form was a convenience sketch and is **not** canonical.
- **Impact:** see [MAPS_TRACKING_CONTRACT.md](MAPS_TRACKING_CONTRACT.md). Build both `api.ts` files to it. If you ever prefer camelCase, that's a contract v2 change — log it and update everything together.

### D-013 — Build orchestration: phase-scoped sequential sessions
- **Date:** 2026-06-18 · **By:** user
- **Decision:** One focused Claude session per roadmap phase (0–6), each a small reviewable PR, sharing PLAN + CONTRACT + this log. Not one long session; not parallel-per-service for now.
- **Impact:** see [MAPS_TRACKING_SESSIONS.md](MAPS_TRACKING_SESSIONS.md) for the per-phase kickoff prompts and the start/end-of-session ritual.

### D-014 — Maps lives in the existing prod GCP project (not a new dedicated one)
- **Date:** 2026-06-20 · **By:** user
- **Decision:** Enable Maps JS + Routes + Places (New) and create both API keys inside the **existing BharatTruck prod project** `project-aa0faf06-c115-438a-a36` (number `752385541585`, also hosts Cloud Run + Google Auth), rather than a separate `bharattruck-maps` project.
- **Why:** gcloud is already authenticated to this project; one project for all BharatTruck infra is simpler at 20-user pilot scale. (Reverses the plan's §6.1 new-project default.)
- **Impact:** Per-API **quota caps** applied here as the hard ceiling — Routes `compute_routes_requests` **500/day + 60/min**, Places `SearchTextRequest` **300/day**, Maps JS `billable_default` **2000/day**. Keys: browser `bt-browser-maps-js` (Maps-JS-only + localhost referrers, public), server `bt-tracking-server` (Routes + Places New only, secret → `bt-tracking-service/.env`, gitignored). Because the project is shared with Cloud Run/auth, a project-wide ₹500 budget would mix Maps with other spend — when creating the budget, prefer a **services filter** (Maps/Routes/Places SKUs). **Budget ₹500 alert still TODO** (billingbudgets API not yet enabled). (Supersedes the new-project recommendation.)

### D-015 — Browser key dev referrers include localhost:3002
- **Date:** 2026-06-20 · **By:** session
- **Decision:** The browser key `bt-browser-maps-js` allows `http://localhost:3000/*`, `:3001/*`, **and `:3002/*`**. The plan listed only 3000/3001.
- **Why:** 3000/3001 were occupied by other local dev servers during the Phase 0 render test, so the shipper app ran on 3002.
- **Impact:** harmless localhost dev origins. **Before launch:** add the real driver/shipper prod domains to this key (and optionally trim 3002). Real prod domains were unknown this session.

### D-016 — Budget alert set at ₹50 (project-scoped), not ₹500
- **Date:** 2026-06-21 · **By:** user
- **Decision:** Created a Cloud Billing budget of **₹50/month** (alert thresholds 50/90/100% → ₹25/₹45/₹50, current-spend basis), scoped to project `752385541585`, emailing the billing-admin (`deltaos1997@gmail.com`) via default IAM recipients. Lower than the plan's §6.5 ₹500.
- **Why:** the user has a tight budget; a budget is an *alert*, not a charge or a cap, so a low threshold gives the earliest possible warning of any real spend (expected spend is ₹0 — pilot usage is 2–13% of the free tier). Project-scoped rather than per-SKU-filtered for simplicity, and it usefully also catches any non-Maps spend (Cloud Run/auth sit near ₹0).
- **Impact:** completes the Phase 0 cost guardrails. The **hard** cost stop remains the per-API quota caps in D-014; this budget only emails. Budget id `8f8f7da8-631a-481a-8e7a-d9f9a9378f48` on `billingAccounts/010E0C-E8C7B2-B83F76`. (Resolves the "budget TODO" noted in D-014.)

### D-017 — bt-tracking-service deployed to Cloud Run; shipper calls it DIRECTLY (gateway redeploy pending)
- **Date:** 2026-06-22 · **By:** user + session
- **Decision:** Deployed `bt-tracking-service` to Cloud Run (asia-south1, `https://bt-tracking-service-752385541585.asia-south1.run.app`, `--allow-unauthenticated` but JWT-protected in-app; shares the prod Upstash Redis + prod Supabase + the same `695d…` JWT secret as booking). The shipper frontend calls it **directly** via `NEXT_PUBLIC_TRACKING_BASE` rather than through the gateway `/api/tracking/`. Frontends deployed to Vercel: shipper `https://shipper-five.vercel.app`, driver `https://driver-kappa-lemon.vercel.app`. Browser-key referrers now include `https://shipper-five.vercel.app/*` and `https://*.vercel.app/*`.
- **Why:** ship real routes onto the deployed shipper without redeploying the prod gateway (it fronts all live traffic — too risky for this step).
- **Impact:** **TEMPORARY** deviation from the contract (frontend should reach tracking via the gateway). **Follow-up:** redeploy `bt-gateway` with the `/api/tracking/` block (already in `nginx.conf.template`) + `TRACKING_SERVICE_URL` env, then drop `NEXT_PUBLIC_TRACKING_BASE` from the frontends so they go via the gateway. Tighten `*.vercel.app` to the real domains before public launch. The Cloud Run service env is set via plain `--set-env-vars` (matches booking-service); consider Secret Manager later.

---

## Template for new entries

```
### D-### — <short title>
- **Date:** YYYY-MM-DD · **By:** user | session | design
- **Decision:** <what was decided>
- **Why:** <rationale>
- **Impact:** <files/contracts/thresholds affected> (Supersedes: D-xxx, if any)
```
