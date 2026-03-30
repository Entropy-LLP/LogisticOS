-- ============================================================
-- LogisticOS / BharatTruck — Initial Schema
-- Run this in your Supabase SQL editor or via supabase db push
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ─── Users ───────────────────────────────────────────────────────────────────

create table if not exists users (
  id           uuid primary key default gen_random_uuid(),
  phone        varchar(15) unique not null,
  role         text not null default 'shipper'
                 check (role in ('shipper', 'driver', 'fleet_owner', 'admin')),
  is_verified  boolean not null default false,
  kyc_status   text not null default 'pending'
                 check (kyc_status in ('pending', 'submitted', 'approved', 'rejected')),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ─── Shipper Profiles ─────────────────────────────────────────────────────────

create table if not exists shipper_profiles (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  name           varchar(100) not null,
  email          varchar(150),
  company_name   varchar(200),
  gst_number     varchar(20),
  aadhaar_last4  varchar(4),
  created_at     timestamptz not null default now(),
  unique (user_id)
);

-- ─── Driver Profiles ──────────────────────────────────────────────────────────

create table if not exists driver_profiles (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users(id) on delete cascade,
  name             varchar(100) not null,
  license_number   varchar(30),
  vehicle_type     text check (vehicle_type in ('mini_truck', 'lcv', 'hcv', 'trailer')),
  vehicle_number   varchar(20),
  is_available     boolean not null default false,
  current_lat      decimal(10, 8),
  current_lng      decimal(11, 8),
  rating           decimal(3, 2) not null default 5.00,
  total_trips      integer not null default 0,
  created_at       timestamptz not null default now(),
  unique (user_id)
);

-- ─── KYC Documents ────────────────────────────────────────────────────────────
-- Stores references to files uploaded to Supabase Storage

create table if not exists kyc_documents (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id) on delete cascade,
  doc_type     text not null check (doc_type in ('aadhaar', 'pan', 'license', 'rc', 'permit')),
  storage_path text not null,           -- Supabase Storage path
  status       text not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected')),
  rejection_reason text,
  uploaded_at  timestamptz not null default now()
);

-- ─── Indexes ──────────────────────────────────────────────────────────────────

create index if not exists idx_users_phone on users(phone);
create index if not exists idx_driver_profiles_available on driver_profiles(is_available);
create index if not exists idx_driver_profiles_location on driver_profiles(current_lat, current_lng)
  where is_available = true;
create index if not exists idx_kyc_documents_user_id on kyc_documents(user_id);

-- ─── updated_at trigger ───────────────────────────────────────────────────────

create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger users_updated_at
  before update on users
  for each row execute function update_updated_at();

-- ─── Row Level Security ───────────────────────────────────────────────────────
-- Services use service_role key (bypasses RLS), but set up for future mobile direct access

alter table users enable row level security;
alter table shipper_profiles enable row level security;
alter table driver_profiles enable row level security;
alter table kyc_documents enable row level security;

-- Service role bypasses RLS — no policies needed for server-side usage
-- Add policies here when using Supabase client directly from mobile app
