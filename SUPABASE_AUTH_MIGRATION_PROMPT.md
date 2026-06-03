# Supabase Auth Migration — Claude Code Session Prompt

> Copy everything below and paste it as your first message in a new Claude Code session opened in the `/LogisticOS` directory.

---

## Task

Migrate LogisticOS from its custom home-coded auth service to **Supabase Auth**. Work on a **new branch** (`feat/supabase-auth`) off `main`. Preserve the existing auth code on `main` — do not delete anything on `main`.

Use whatever is **native to Supabase Auth** (email/password, magic links, Google OAuth). For **Phone OTP (SMS)**, Supabase uses Twilio which costs money — **build the skeleton/wiring for phone OTP but do not require a paid Twilio account**. It should be easy to enable later by just adding Twilio creds in the Supabase dashboard.

## Why we're doing this

The current custom auth (`bt-auth-service/src/routes/auth.ts`) has ongoing reliability issues:
- Magic links break frequently due to self-hosted SMTP/Nodemailer
- No real SMS provider — OTPs are just `console.log`'d
- Manual SMTP wiring per environment
- JWT secret management across services is fragile
- Deployment is complex (10+ auth-related env vars)
- Scalability concerns with Redis-backed OTP/refresh token storage

## Project context

**LogisticOS / BharatTruck** is an Indian freight booking platform. Microservices architecture:

| Service | Port | Purpose |
|---|---|---|
| bt-gateway (nginx) | 8080 | API gateway, rate limiting, CORS |
| bt-auth-service | 3001 | Auth + onboarding + KYC |
| bt-booking-service | 3002 | Bookings, quotes, GPS |
| bt-pricing-service | 3003 | Pricing engine |
| bt-payment-service | 3004 | Razorpay payments |
| bt-cargo-ledger | 3005 | Cargo tracking |
| driver app (Next.js) | 3010 | Driver mobile web |
| shipper app (Next.js) | 3011 | Shipper web |
| bt-ops-web (Next.js) | 3000 | Admin portal (stub auth) |

**Supabase project ID:** `rxbdzbcndpzznvqcbimg` (region: ap-south-1)
**Supabase MCP** is available — use it for SQL and migrations.

## Database state

The `public.users` table already has an `auth_id UUID` column (nullable) designed to link to `auth.users.id`. RLS policies on most tables use `auth.uid()`. The migration must make `auth.uid()` work correctly by populating `auth_id` from Supabase Auth.

Key tables: `users`, `drivers`, `vehicles`, `driver_licenses`, `driver_insurance`, `bank_accounts`, `kyc_documents`. All have RLS enabled.

Roles are an enum: `user_role` = `'shipper' | 'driver'`. The role is stored in `public.users.role` and should be passed as `raw_user_meta_data` during Supabase Auth signup.

## Current auth architecture (what to replace)

### Auth strategies (all in `bt-auth-service/src/routes/auth.ts`, ~480 lines):

1. **Phone OTP** — `POST /auth/send-otp`, `POST /auth/verify-otp`
   - 6-digit OTP stored in Redis, 5-min TTL
   - Phone validation: `/^[6-9]\d{9}$/` (Indian 10-digit, no +91 prefix)
   - Creates user with `role: 'driver'` + `ensureDriverRow()` on first verify
   
2. **Email/Password** — `POST /auth/email/register`, `POST /auth/email/verify`, `POST /auth/email/login`, `POST /auth/email/resend-otp`
   - bcrypt (salt=12), email OTP verification before login allowed
   
3. **Google OAuth** — `POST /auth/google`
   - google-auth-library id_token verification
   - Creates/links user by `google_sub` or email
   
4. **Magic Links** — `POST /auth/magic-link/send`, `GET /auth/magic-link/verify`
   - Crypto-secure 32-byte hex token, Redis, Nodemailer
   
5. **Token management** — `POST /auth/refresh`, `GET /auth/me`, `POST /auth/logout`
   - JWT access tokens (15m, HS256, `JWT_SECRET`)
   - JWT refresh tokens (7d, HS256, `JWT_REFRESH_SECRET`, stored in Redis)
   
6. **Profile completion** — `POST /auth/register`
   - Post-signup profile update (name, role, truck details)

### Supporting files to delete/replace:
- `bt-auth-service/src/lib/jwt.ts` — `signAccessToken()`, `signRefreshToken()`, `verifyAccessToken()`, `verifyRefreshToken()`
- `bt-auth-service/src/lib/otp.ts` — `generateOtp()`, `sendOtp()` (console.log)
- `bt-auth-service/src/lib/password.ts` — bcrypt `hashPassword()`, `verifyPassword()`
- `bt-auth-service/src/lib/email.ts` — Nodemailer `sendEmailOtp()`, `sendMagicLinkEmail()`
- `bt-auth-service/src/lib/google.ts` — `verifyGoogleToken()` via google-auth-library
- `bt-auth-service/src/lib/authenticate.ts` — Bearer token middleware, attaches `request.user`

### Files to KEEP untouched:
- `bt-auth-service/src/routes/onboarding.ts` — 12 endpoints for driver profile, vehicles, license, insurance, bank accounts. Only the auth middleware it uses changes.
- `bt-auth-service/src/routes/kyc.ts` — KYC stubs. Only middleware changes.
- `bt-auth-service/src/plugins/supabase.ts` — service role client stays (used by onboarding)
- `bt-auth-service/src/lib/encryption.ts` — AES-256-GCM for bank account numbers. Untouched.

## Blast radius — every file that touches auth

### bt-auth-service (6 files)
- `src/routes/auth.ts` — **DELETE entirely** (all 14 auth endpoints replaced by Supabase Auth)
- `src/lib/jwt.ts` — **DELETE**
- `src/lib/otp.ts` — **DELETE**
- `src/lib/password.ts` — **DELETE**
- `src/lib/email.ts` — **DELETE**
- `src/lib/google.ts` — **DELETE**
- `src/lib/authenticate.ts` — **REWRITE**: verify Supabase JWT instead of custom JWT. The Supabase JWT secret is available in the Supabase dashboard (Settings > API > JWT Secret). The JWT payload has `sub` (user UUID = `auth.users.id`), and `user_metadata` with custom fields. Map `sub` → look up `public.users` by `auth_id` to get `userId`, `role`, etc.
- `src/index.ts` — **MODIFY**: remove auth routes registration, keep onboarding + kyc
- `src/plugins/redis.ts` — **KEEP** (may still be used for caching outside auth)

### bt-booking-service (2 files)
- `src/plugins/auth.ts` — **REWRITE**: same JWT verification change. Currently verifies with `JWT_SECRET` env var, must verify Supabase JWTs instead. Extracts `userId` from `sub` claim, looks up role from `public.users`.
- `src/lib/supabase.ts` — **KEEP** as-is (service role client)

### bt-gateway (1 file)
- `nginx.conf` — **MODIFY**: remove `/api/auth/*` proxy block (clients talk to Supabase directly). Keep `/api/onboarding/*`, `/api/kyc/*`, `/api/bookings/*` etc.

### driver app — `/driver/src/` (8 files)
- `lib/auth.tsx` — **REWRITE**: Replace localStorage JWT management with Supabase client session. Use `@supabase/ssr` for Next.js. `AuthProvider` listens to `onAuthStateChange`. Delete refresh mutex. Export `useAuth()` with `{ user, session, isReady, signOut }`.
- `lib/api.ts` — **REWRITE**: 
  - Delete all token helpers (`getToken`, `setToken`, `clearToken`, `getRefreshToken`, `setRefreshToken`, `clearRefreshToken`, `tryRefresh` — ~80 lines)
  - `request<T>()` gets session token from Supabase client: `const { data: { session } } = await supabase.auth.getSession(); const token = session?.access_token`
  - Delete ALL auth endpoint wrappers (`sendPhoneOtp`, `verifyPhoneOtp`, `googleSignIn`, `emailLogin`, `emailRegister`, `emailVerify`, `emailResendOtp`, `sendMagicLink`, `verifyMagicLink`, `refreshAccessToken`, `getMe`, `registerProfile`, `authLogout` — ~120 lines)
  - Keep all onboarding API wrappers untouched
  - Add a new `lib/supabase.ts` that creates the browser Supabase client with `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `app/login/page.tsx` — **REWRITE**: Use Supabase auth methods:
  - Phone: `supabase.auth.signInWithOtp({ phone: '+91' + phone })` (Supabase expects E.164 format)
  - Google: `supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo } })`
  - Email register: `supabase.auth.signUp({ email, password, options: { data: { role, full_name } } })`
  - Email login: `supabase.auth.signInWithPassword({ email, password })`
  - Magic link: `supabase.auth.signInWithOtp({ email, options: { emailRedirectTo } })`
  - Keep the same UI/UX (tabs for phone/google/email/magic-link)
- `app/auth/callback/page.tsx` — **REWRITE**: Supabase PKCE callback. Use `supabase.auth.exchangeCodeForSession(code)` from URL params.
- `app/layout.tsx` — **MODIFY**: wrap with new AuthProvider
- `app/page.tsx` — **MODIFY**: check `supabase.auth.getUser()` instead of `getToken()`
- `app/onboarding/layout.tsx` — **MODIFY**: session check instead of token check
- `components/app-shell.tsx` — **MODIFY**: `supabase.auth.signOut()` instead of custom logout

### shipper app — `/shipper/src/` (5 files)
- Nearly identical to driver app. Same changes apply:
- `lib/auth.tsx`, `lib/api.ts`, `app/login/page.tsx`, `app/auth/callback/page.tsx`, `components/Navbar.tsx`
- Note: shipper uses `bt_token` / `bt_refresh_token` localStorage keys (vs driver's `bt_driver_token`). Both go away.

### bt-ops-web (1 file)
- `app/login/page.tsx` — Currently a stub with hardcoded `ops@bharattruck.in` / `password`. Wire up real Supabase email/password auth here too.

## Database migration needed

Apply via Supabase MCP `apply_migration`:

```sql
-- Trigger to sync auth.users → public.users on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.users (auth_id, phone_number, email, role, full_name)
  VALUES (
    NEW.id,
    NEW.phone,
    NEW.email,
    COALESCE((NEW.raw_user_meta_data->>'role')::public.user_role, 'shipper'),
    NEW.raw_user_meta_data->>'full_name'
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- For drivers, also create the drivers row
CREATE OR REPLACE FUNCTION public.handle_new_driver()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NEW.role = 'driver' THEN
    INSERT INTO public.drivers (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_user_created_ensure_driver
  AFTER INSERT ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_driver();
```

Also, for existing users who don't have `auth_id` set, you may need a one-time backfill after they re-authenticate through Supabase Auth.

## Environment variable changes

### Remove from docker-compose.yml:
- `JWT_SECRET`, `JWT_REFRESH_SECRET` (from bt-auth-service, bt-booking-service)
- `ENCRYPTION_KEY` stays (used for bank account encryption, not auth)

### Add to docker-compose.yml:
- For bt-auth-service and bt-booking-service: `SUPABASE_JWT_SECRET` (from Supabase dashboard > Settings > API > JWT Secret) — used to verify Supabase-issued JWTs on the backend
- For driver app, shipper app, bt-ops-web: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`

### Remove from frontends:
- `NEXT_PUBLIC_GOOGLE_CLIENT_ID` (configured in Supabase dashboard instead)

## Execution order

1. **Create branch**: `git checkout -b feat/supabase-auth`
2. **Database migration**: Apply the trigger via Supabase MCP
3. **Create `lib/supabase.ts`** in driver app and shipper app (browser client)
4. **Rewrite `authenticate.ts`** in bt-auth-service to verify Supabase JWTs
5. **Rewrite `auth.ts` plugin** in bt-booking-service for same
6. **Delete auth routes** from bt-auth-service, update `index.ts`
7. **Rewrite driver app auth**: `lib/auth.tsx` → `lib/api.ts` → `app/login/page.tsx` → callback → guards
8. **Rewrite shipper app auth**: same pattern
9. **Wire bt-ops-web** login
10. **Update nginx.conf**: remove `/api/auth/*` proxy
11. **Update docker-compose.yml**: swap env vars
12. **Delete dead code**: jwt.ts, otp.ts, password.ts, email.ts, google.ts
13. **Test every flow**: phone OTP (skeleton), Google OAuth, email/password, magic links, token refresh, logout, onboarding, bookings

## Important constraints

- **Production-ready code only** — no stubs, no TODOs, no placeholder comments. The user expects fully implemented code.
- **Phone OTP skeleton**: Wire `supabase.auth.signInWithOtp({ phone })` in the UI, but note in a comment that Twilio creds must be added in Supabase dashboard to activate. The code should work end-to-end once creds are added.
- **Preserve all onboarding/KYC code** — only the auth middleware changes, not the business logic.
- **This is a Next.js 16 project** — check `node_modules/next/dist/docs/` for any breaking changes before writing code. Heed deprecation notices.
- **Tailwind CSS v4** is used in the frontends.
- **Test in Docker**: run `docker compose up --build` and verify all flows at `localhost:3010` (driver), `localhost:3011` (shipper), `localhost:3000` (ops).
- **Commit incrementally** as you complete each phase — don't batch everything into one commit.

## Files to read first before writing any code

1. `bt-auth-service/src/routes/auth.ts` — understand what you're replacing
2. `bt-auth-service/src/lib/authenticate.ts` — the middleware pattern
3. `bt-auth-service/src/routes/onboarding.ts` — must keep working
4. `bt-booking-service/src/plugins/auth.ts` — the other JWT verifier
5. `driver/src/lib/auth.tsx` — current auth context
6. `driver/src/lib/api.ts` — current token management
7. `driver/src/app/login/page.tsx` — current login UI
8. `shipper/src/lib/api.ts` — shipper's token management
9. `bt-gateway/nginx.conf` — routing rules
10. `docker-compose.yml` — env vars and service topology
