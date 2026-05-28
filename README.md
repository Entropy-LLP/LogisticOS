# LogisticOS — BharatTruck Dev Workspace

This repo is the **developer workspace** for BharatTruck. It contains no product code — only the orchestration tooling: `Makefile`, `setup.sh`, `docker-compose.yml`, `k8s/`, and `docs/`.

Running `setup.sh` clones all service repos into this directory, giving you a fully wired local environment.

> **This repo is for local development setup only.** All product code lives in individual service repos listed below. Do not add application code here.

---

## Service Repos

| Service | Repo | Type | Port | Description |
|---------|------|------|------|-------------|
| bt-gateway | [deltaos1997/bt-gateway](https://github.com/deltaos1997/bt-gateway) | Nginx | 8080 | API gateway / reverse proxy |
| bt-auth-service | [deltaos1997/bt-auth-service](https://github.com/deltaos1997/bt-auth-service) | Node.js | 3001 | OTP login, JWT, KYC, user profiles |
| bt-booking-service | [deltaos1997/bt-booking-service](https://github.com/deltaos1997/bt-booking-service) | Node.js | 3002 | Trips, driver matching, GPS tracking, WebSocket |
| bt-pricing-service | [deltaos1997/bt-pricing-service](https://github.com/deltaos1997/bt-pricing-service) | Node.js | 3003 | Fare engine |
| bt-payment-service | [deltaos1997/bt-payment-service](https://github.com/deltaos1997/bt-payment-service) | Node.js | 3004 | Razorpay escrow, payouts, invoices |
| bt-cargo-ledger | [deltaos1997/bt-cargo-ledger](https://github.com/deltaos1997/bt-cargo-ledger) | Node.js | 3005 | Multi-leg tracking, blockchain proof |
| bt-ops-web | [deltaos1997/bt-ops-web](https://github.com/deltaos1997/bt-ops-web) | Next.js | 3000 | Ops/admin panel |
| bt-driver-app | [deltaos1997/bt-driver-app](https://github.com/deltaos1997/bt-driver-app) | Next.js | — | Driver web dashboard |
| bt-shipper-app | [deltaos1997/bt-shipper-app](https://github.com/deltaos1997/bt-shipper-app) | Next.js | — | Shipper web dashboard |

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 18+ | [nodejs.org](https://nodejs.org) |
| npm | 9+ | Comes with Node |
| Redis | 7+ | `brew install redis` |
| Git | any | `brew install git` |
| Docker | 20+ | [docker.com](https://docker.com) (optional, for containerized dev) |

---

## Step 1 — SSH access

All repos are on GitHub under `deltaos1997`. You need an SSH key linked to that account (or your own account if you've been given collaborator access).

**Check if you already have one:**
```bash
ls ~/.ssh/id_ed25519.pub
```

**If not, generate one:**
```bash
ssh-keygen -t ed25519 -C "your-name"
# Press Enter 3 times to accept defaults
```

**Add the public key to GitHub:**
```bash
cat ~/.ssh/id_ed25519.pub
# Copy the output, then go to:
# github.com -> Settings -> SSH and GPG keys -> New SSH key -> Paste
```

**Test it:**
```bash
ssh -T git@github.com
# Expected: Hi <username>! You've successfully authenticated...
```

---

## Step 2 — Clone this repo

```bash
git clone git@github.com:deltaos1997/LogisticOS.git
cd LogisticOS
```

---

## Step 3 — Run setup

This clones all 9 service repos into the current directory:

```bash
./setup.sh
```

After it runs, your directory looks like this:

```
LogisticOS/
├── Makefile
├── setup.sh
├── docker-compose.yml
├── docker-compose.prod.yml
├── bt-gateway/            <- cloned
├── bt-auth-service/       <- cloned
├── bt-booking-service/    <- cloned
├── bt-pricing-service/    <- cloned
├── bt-payment-service/    <- cloned
├── bt-cargo-ledger/       <- cloned
├── bt-ops-web/            <- cloned
├── bt-driver-app/         <- cloned
└── bt-shipper-app/        <- cloned
```

Each service directory is its own independent git repo — you commit and push from inside them individually.

---

## Step 4 — Environment variables

Each service reads its config from a `.env` file in its own directory. Copy the example and fill in your values:

```bash
cp infra/env.template .env
# Edit .env with your Supabase, Redis, Razorpay credentials
```

> Ask the team lead for Supabase credentials, Redis URL, and Razorpay keys.

---

## Step 5 — Install dependencies and start

```bash
# Install backend dependencies
make install

# Start Redis
make redis

# Start all services in the background
make start

# Check everything is up
make status
```

---

## Common commands

| Command | What it does |
|---------|-------------|
| `make start` | Start all services in background |
| `make stop` | Stop all services |
| `make status` | See which services are up/down |
| `make health` | Hit `/health` on all services |
| `make logs` | Tail logs from all services |
| `make logs-auth` | Tail logs for a specific service |
| `make restart-auth` | Restart a specific service |
| `make install` | Install backend deps |
| `make install-all` | Install deps including frontends |

Run `make help` to see the full list.

---

## Docker Compose

For containerized local development:

```bash
docker compose up --build -d
```

For production-like builds:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
```

---

## Deployment

| Service | Platform |
|---------|----------|
| bt-driver-app, bt-shipper-app | Vercel |
| bt-gateway, bt-auth-service, bt-booking-service, bt-pricing-service, bt-payment-service, bt-cargo-ledger | Render |

---

## Shared Infrastructure

- **Database** — Supabase (PostgreSQL), each service uses its own schema
- **Cache / Sessions** — Redis (Upstash)
- **File storage** — Cloudflare R2 (KYC docs, ePOD photos)
