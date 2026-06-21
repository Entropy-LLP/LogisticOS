# Maps & Tracking — Phase 0 Completion Report

**Phase:** 0 — Google Maps Platform setup + cost guardrails + hello-map
**Status:** ✅ **COMPLETE** (all "done-when" criteria met)
**Date:** 2026-06-21
**GCP project:** `project-aa0faf06-c115-438a-a36` (number `752385541585`) — the existing BharatTruck prod project (see decision **D-014**)
**Billing account:** `010E0C-E8C7B2-B83F76` (billing enabled)

---

## 1. What was set up

### APIs enabled (exactly three, no legacy)
| API | Service | Purpose |
|---|---|---|
| Maps JavaScript API | `maps-backend.googleapis.com` | Draw map tiles in the browser |
| Routes API | `routes.googleapis.com` | Routes + traffic-aware ETA (server-side) |
| Places API (New) | `places.googleapis.com` | Petrol-pump search along route (server-side) |

Legacy Directions / Distance Matrix / old Places were **not** enabled.

### API keys (two, least-privilege)
| Key (display name) | Restriction | Where it lives |
|---|---|---|
| `bt-browser-maps-js` | Application = HTTP referrers (`localhost:3000/3001/3002`); API = **Maps JavaScript API only** | `NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY` in `driver/.env.local` + `shipper/.env.local` (public by design, gitignored) |
| `bt-tracking-server` | API = **Routes API + Places API (New) only**; no referrer (server-to-server) | `GOOGLE_MAPS_SERVER_KEY` in `bt-tracking-service/.env` (**secret**, gitignored) |

> Raw key strings are intentionally omitted from this report. They live only in gitignored `.env*` files.

### Cost guardrails
**Per-API quota caps (the hard ceiling — Google returns "quota exceeded" and bills nothing further):**
| API | Quota | Cap set |
|---|---|---|
| Routes (`compute_routes_requests`) | per day | **500** |
| Routes (`compute_routes_requests`) | per minute | **60** |
| Places (`SearchTextRequest`) | per day | **300** |
| Maps JS (`billable_default`, map loads) | per day | **2,000** |

**Budget alert (soft layer — email only, never a charge):** ₹50/month, thresholds 50/90/100% (₹25/₹45/₹50), project-scoped, emailing the billing admin. Budget id `8f8f7da8-631a-481a-8e7a-d9f9a9378f48` (see **D-016**).

> Expected real spend at pilot scale (~110 trips/mo) is **₹0** — usage is 2–13% of the per-API monthly free tier.

---

## 2. Verification evidence

| Check | Method | Result |
|---|---|---|
| Routes API + server key + billing | `curl` ComputeRoutes (Mumbai→Pune) | `HTTP 200`, distance 141,247 m ✅ |
| Server key restricted correctly | `curl` Places (New) SearchText | `HTTP 200`, real pumps returned ✅ |
| Browser key can't call paid APIs | `curl` Routes with browser key | `HTTP 403 PERMISSION_DENIED` ✅ |
| Quota caps applied | Service Usage API read-back | 500 / 60 / 300 / 2,000 confirmed ✅ |
| Budget created | `gcloud billing budgets describe` | ₹50 INR, 50/90/100% confirmed ✅ |
| **Bare map renders** | `shipper` app at `/maps-test` | India map + Delhi pin + green "LOADED ✓" badge, **confirmed by user** ✅ |

---

## 3. Files changed (this phase)

- `shipper/.env.local`, `driver/.env.local` — browser key + `NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID=DEMO_MAP_ID` *(gitignored — not committed)*
- `bt-tracking-service/.env` — server key *(gitignored — not committed)*
- `shipper/.env.example`, `driver/.env.example`, `bt-tracking-service/.env.example` — committed templates
- `shipper/.gitignore`, `driver/.gitignore` — added `!.env.example` so templates commit while real env stays ignored
- `shipper/package.json` + lockfile — added `@vis.gl/react-google-maps`, `@googlemaps/polyline-codec`
- `shipper/src/app/maps-test/page.tsx` — throwaway hello-map (delete in Phase 1)
- `docs/MAPS_TRACKING_DECISIONS.md` — appended D-014, D-015, D-016

---

## 4. Decisions logged
- **D-014** — Maps lives in the existing prod GCP project (not a new one); quota caps applied there.
- **D-015** — Browser key dev referrers include `localhost:3002`.
- **D-016** — Budget alert set at ₹50 (project-scoped), not ₹500.

---

## 5. Follow-ups (not blocking Phase 1)
- [ ] Replace `DEMO_MAP_ID` with a real Map ID (Google Maps Platform → Map Management → Create Map ID → JavaScript/Vector) before launch.
- [ ] Add real driver/shipper prod domains to the `bt-browser-maps-js` referrer allow-list before launch (optionally trim `localhost:3002`).
- [ ] Budget is project-scoped; narrow to Maps SKUs later if Cloud Run spend ever becomes noticeable.

---

## 6. What's NOT done yet (next phases)
- **`bt-tracking-service` is not built** — it has only a staged `.env`/`.env.example`. The actual Fastify app, routes, migration 009, gateway wiring, Dockerfile, and **Cloud Run deploy** are **Phase 2**.
- **Next up — Phase 1:** shipper live map over the existing `getBookingLocation()` poll (zero backend change). See the Phase 1 kickoff prompt in `MAPS_TRACKING_SESSIONS.md`.
