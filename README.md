# LogisticOS — BharatTruck Dev Workspace

This repo is the **developer workspace** for BharatTruck. It contains no product code — only the orchestration tooling: `Makefile`, `setup.sh`, `docker-compose.yml`, `k8s/`, and `docs/`.

Running `setup.sh` clones all 8 service repos into this directory, giving you a fully wired local environment.

---

## Prerequisites

Make sure these are installed before you begin:

| Tool | Version | Install |
|---|---|---|
| Node.js | 18+ | [nodejs.org](https://nodejs.org) |
| npm | 9+ | Comes with Node |
| Redis | 7+ | `brew install redis` |
| Git | any | `brew install git` |

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
# github.com → Settings → SSH and GPG keys → New SSH key → Paste
```

**Test it:**
```bash
ssh -T git@github.com
# Expected: Hi <username>! You've successfully authenticated...
```

---

## Step 2 — Clone this repo

Pick a folder where you want your workspace to live (e.g. `~/dev/bharattruck`):

```bash
mkdir -p ~/dev/bharattruck
cd ~/dev/bharattruck
git clone git@github.com:deltaos1997/LogisticOS.git
cd LogisticOS
```

---

## Step 3 — Run setup

This clones all 8 service repos into the current directory:

```bash
./setup.sh
```

After it runs, your directory looks like this:

```
LogisticOS/
├── Makefile
├── setup.sh
├── bt-auth-service/       ← cloned
├── bt-booking-service/    ← cloned
├── bt-pricing-service/    ← cloned
├── bt-payment-service/    ← cloned
├── bt-cargo-ledger/       ← cloned
├── bt-ops-web/            ← cloned
├── bt-driver-app/         ← cloned
└── bt-shipper-app/        ← cloned
```

Each service directory is its own independent git repo — you commit and push from inside them individually.

---

## Step 4 — Environment variables

Each service reads its config from a `.env` file in its own directory. Copy the example and fill in your values:

```bash
cp bt-auth-service/.env.example bt-auth-service/.env
# repeat for other services you'll be running
```

> Ask the team lead for Supabase credentials, Redis URL, and Razorpay keys.

---

## Step 5 — Install dependencies and start

```bash
# Install backend dependencies
make install

# Start Redis
make redis

# Start all 6 web services in the background
make start

# Check everything is up
make status
```

---

## Common commands

| Command | What it does |
|---|---|
| `make start` | Start all services in background |
| `make stop` | Stop all services |
| `make status` | See which services are up/down |
| `make health` | Hit `/health` on all services |
| `make logs` | Tail logs from all services |
| `make logs-auth` | Tail logs for a specific service |
| `make restart-auth` | Restart a specific service |
| `make install` | Install backend deps |
| `make install-all` | Install deps including frontend + mobile |

Run `make help` to see the full list.

---

## Services

| Service | Port | Description |
|---|---|---|
| bt-auth-service | 3001 | OTP login, JWT, KYC, user profiles |
| bt-booking-service | 3002 | Trips, driver matching, GPS tracking |
| bt-pricing-service | 3003 | Fare engine |
| bt-payment-service | 3004 | Razorpay escrow, payouts, invoices |
| bt-cargo-ledger | 3005 | Multi-leg tracking, checkpoint handshakes |
| bt-ops-web | 3000 | Next.js ops/admin panel |
| bt-driver-app | — | React Native (Expo) — driver app |
| bt-shipper-app | — | React Native (Expo) — shipper app |

---

## Shared infrastructure

- **Database** — Supabase (PostgreSQL), each service uses its own schema
- **Cache / Sessions** — Redis (Upstash)
- **File storage** — Cloudflare R2 (KYC docs, ePOD photos)
