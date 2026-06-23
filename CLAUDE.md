# LogisticOS / BharatTruck — working agreement

India freight marketplace on a microservice backend (`bt-auth/booking/pricing/payment/cargo-ledger` + nginx `bt-gateway`) with Next.js driver + shipper PWAs. Backend: Node 20 + TypeScript + Fastify + Supabase (service-role) + Redis. Deployed on GCP Cloud Run (asia-south1).

- Architecture: [docs/architecture.md](docs/architecture.md)
- How to scope sessions / MD-first workflow: [docs/dev-workflow.md](docs/dev-workflow.md)
- API responses everywhere use `{ success, data?, error?, code? }`; auth is JWT `Bearer` with `{ userId, role }`.

## Maps & Tracking work — read these FIRST

When the task touches Maps, Tracking, navigation, ETA, petrol pumps, fuel, route alerts, or `bt-tracking-service`:

1. Read [docs/MAPS_TRACKING_CONTRACT.md](docs/MAPS_TRACKING_CONTRACT.md) — the **frozen interface** (endpoints, env keys, schema, `snake_case`). Build to it exactly; it wins over the plan narrative.
2. Read [docs/MAPS_TRACKING_DECISIONS.md](docs/MAPS_TRACKING_DECISIONS.md) — **append-only** decision log. Read before building; **append any cross-service/threshold/cost/scope decision before finishing**. For a genuine product fork, ask the user, then log the answer.
3. Design detail is in [docs/MAPS_TRACKING_PLAN.md](docs/MAPS_TRACKING_PLAN.md); run the build **one phase per session** using the prompts + ritual in [docs/MAPS_TRACKING_SESSIONS.md](docs/MAPS_TRACKING_SESSIONS.md).

Do **not** modify GPS ingestion (`bt-booking-service/src/routes/location.ts`) — it is frozen. The new `bt-tracking-service` is read-only on the `loc:*` Redis keys.

## General

- Verify changes actually run before claiming done (use `/verify` or `/run`). Report failures honestly.
- One phase / one concern per branch + PR. Keep the contract frozen unless you follow its change protocol.
