# BharatTruck — Architecture Overview

## Service Map

```
                        ┌─────────────────┐
                        │  bt-ops-web   │  Next.js ops panel
                        └────────┬────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
    ┌─────────▼──────┐  ┌───────▼──────┐  ┌───────▼──────┐
    │bt-driver-app   │  │bt-shipper-app│  │  API calls   │
    │(React Native)  │  │(React Native)│  │  (external)  │
    └─────────┬──────┘  └───────┬──────┘  └───────┬──────┘
              │                  │                  │
              └──────────────────┼──────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │    (future API gateway) │
                    └────────────┬────────────┘
                                 │
        ┌────────────┬───────────┼───────────┬────────────┐
        │            │           │           │            │
   ┌────▼────┐ ┌─────▼────┐ ┌───▼───┐ ┌────▼────┐ ┌─────▼──────┐
   │  auth   │ │ booking  │ │pricing│ │payment  │ │cargo-ledger│
   │  :3001  │ │  :3002   │ │ :3003 │ │  :3004  │ │   :3005    │
   └────┬────┘ └─────┬────┘ └───────┘ └─────────┘ └─────┬──────┘
        │            │                                    │
        └────────────┼────────────────────────────────────┘
                     │
            ┌────────▼────────┐
            │   PostgreSQL    │  (Supabase)
            │   Redis         │  (Upstash)
            │   Cloudflare R2 │  (file storage)
            └─────────────────┘
```

## Key Decisions

### Why separate repos?
Each service is independently deployable, versioned, and can have its own CI/CD pipeline.
No service needs to know about another's internals — only the contracts (see `/contracts`).

### Why bt-cargo-ledger?
Multi-leg freight doesn't go A→B directly. It goes A→B→C→D across multiple trucks.
At each handoff, both parties sign. The signed data is hashed and written to Polygon blockchain.
This creates a tamper-proof chain of custody usable in dispute resolution / court.

### Notifications
Not a separate service. Booking-service and payment-service emit notifications directly
via MSG91 (SMS) and Firebase FCM (push). Simple, no queue overhead for MVP.

### Blockchain strategy
- PostgreSQL is source of truth (actual checkpoint data)
- SHA-256 Merkle hash of checkpoint data written to Polygon (cheap: ~$0.001/tx)
- Anyone can verify: hash the DB record → compare to on-chain hash
- Smart contract in Phase 2 can automate escrow release on final delivery hash

## Phase 1 MVP Scope
- bt-auth-service: full OTP → JWT → KYC flow
- bt-booking-service: create booking → match driver → GPS track → ePOD
- bt-pricing-service: static fare calculation
- bt-payment-service: Razorpay escrow → release on delivery
- bt-cargo-ledger: checkpoint recording + Merkle hash (blockchain write = Phase 2)
- bt-driver-app: load notifications, accept, navigate, OTP confirm, ePOD
- bt-shipper-app: book truck, track, pay, rate
