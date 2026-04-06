# BharatTruck — Service Registry

| Service | Repo | Port | Status | Description |
|---|---|---|---|---|
| bt-auth-service | bt-auth-service/ | 3001 | Active | OTP login, JWT, KYC, user profiles |
| bt-booking-service | bt-booking-service/ | 3002 | Active | Trips, driver matching, GPS tracking |
| bt-pricing-service | bt-pricing-service/ | 3003 | Active | Fare engine (static v1 → ML v2) |
| bt-payment-service | bt-payment-service/ | 3004 | Active | Razorpay escrow, payouts, invoices |
| bt-cargo-ledger | bt-cargo-ledger/ | 3005 | Active | Multi-leg tracking, checkpoint handshakes, blockchain proof |
| bt-driver-app | bt-driver-app/ | — | Active | React Native (Expo) — driver-facing |
| bt-shipper-app | bt-shipper-app/ | — | Active | React Native (Expo) — shipper/customer-facing |
| bt-ops-web | bt-ops-web/ | 3000 | Active | Next.js — ops/admin panel |

## Local Dev Ports
- 3000 — bt-ops-web
- 3001 — bt-auth-service
- 3002 — bt-booking-service
- 3003 — bt-pricing-service
- 3004 — bt-payment-service
- 3005 — bt-cargo-ledger

## Shared Infrastructure
- PostgreSQL (Supabase): shared DB, each service uses its own schema/tables
- Redis (Upstash): sessions, OTP store, real-time location cache
- Cloudflare R2: file storage (KYC docs, ePOD photos)
- AWS Mumbai: deployment target
