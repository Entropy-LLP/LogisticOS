# BharatTruck — Service Registry

## Services

| Service | Repo | Port | Status | Description |
|---------|------|------|--------|-------------|
| bt-gateway | [bt-gateway](https://github.com/deltaos1997/bt-gateway) | 8080 | Active | Nginx API gateway / reverse proxy |
| bt-auth-service | [bt-auth-service](https://github.com/deltaos1997/bt-auth-service) | 3001 | Active | OTP login, JWT, KYC, user profiles |
| bt-booking-service | [bt-booking-service](https://github.com/deltaos1997/bt-booking-service) | 3002 | Active | Trips, driver matching, GPS tracking, WebSocket |
| bt-pricing-service | [bt-pricing-service](https://github.com/deltaos1997/bt-pricing-service) | 3003 | Active | Fare engine (static v1) |
| bt-payment-service | [bt-payment-service](https://github.com/deltaos1997/bt-payment-service) | 3004 | Active | Razorpay escrow, payouts, invoices |
| bt-cargo-ledger | [bt-cargo-ledger](https://github.com/deltaos1997/bt-cargo-ledger) | 3005 | Active | Multi-leg tracking, checkpoint handshakes, blockchain proof |
| bt-driver-app | [bt-driver-app](https://github.com/deltaos1997/bt-driver-app) | — | Active | Next.js — driver web dashboard |
| bt-shipper-app | [bt-shipper-app](https://github.com/deltaos1997/bt-shipper-app) | — | Active | Next.js — shipper web dashboard |
| bt-ops-web | [bt-ops-web](https://github.com/deltaos1997/bt-ops-web) | 3000 | Active | Next.js — ops/admin panel |

## Local Dev Ports

- 8080 — bt-gateway (Nginx)
- 3000 — bt-ops-web
- 3001 — bt-auth-service
- 3002 — bt-booking-service
- 3003 — bt-pricing-service
- 3004 — bt-payment-service
- 3005 — bt-cargo-ledger

## Deployment

| Service | Platform |
|---------|----------|
| bt-driver-app, bt-shipper-app | Vercel |
| bt-gateway, bt-auth-service, bt-booking-service, bt-pricing-service, bt-payment-service, bt-cargo-ledger | Render |

## Shared Infrastructure

- PostgreSQL (Supabase): shared DB, each service uses its own schema/tables
- Redis (Upstash): sessions, OTP store, real-time location cache
- Cloudflare R2: file storage (KYC docs, ePOD photos)
