export type BookingStatus = 'pending' | 'accepted' | 'negotiating' | 'in_transit' | 'completed' | 'cancelled' | 'paid'
export type BookingType = 'direct' | 'auction'
export type QuoteStatus = 'submitted' | 'countered' | 'accepted' | 'rejected' | 'withdrawn' | 'expired'

export interface Booking {
  id: string
  shipper_id: string
  driver_id: string | null
  shipper_name: string
  shipper_contact: string
  source_address: string
  source_lat: number
  source_lng: number
  destination_address: string
  dest_lat: number
  dest_lng: number
  load_type: string
  weight_kg: number
  quoted_price: number
  final_price: number | null
  pickup_date: string
  pickup_time_slot: string | null
  status: BookingStatus
  special_instructions: string | null
  booking_type: BookingType
  target_driver_id: string | null
  auction_deadline: string | null
  awarded_quote_id: string | null
  in_transit_at: string | null
  completed_at: string | null
  created_at: string
  updated_at: string
}

export interface Quote {
  id: string
  booking_id: string
  driver_id: string
  amount: number
  message: string | null
  status: QuoteStatus
  submitted_at: string
  expires_at: string | null
  updated_at: string
}

export interface NegotiationEntry {
  id: string
  quote_id: string
  booking_id: string
  actor_id: string
  actor_role: 'shipper' | 'driver'
  amount: number
  message: string | null
  created_at: string
}

// ── Onboarding types ────────────────────────────────────────

export type VerificationBadge = 'pending' | 'verified' | 'premium'
export type DocStatus = 'pending' | 'verified' | 'rejected'

export interface DriverProfile {
  id: string
  user_id: string
  is_available: boolean
  truck_number: string | null
  truck_type: string | null
  truck_capacity_kg: number | null
  photo_url: string | null
  languages: string[]
  home_base_city: string | null
  home_base_lat: number | null
  home_base_lng: number | null
  verification_badge: VerificationBadge
  average_rating: number
  total_trips: number
  total_earnings: number
  created_at: string
  updated_at: string
}

export interface Vehicle {
  id: string
  driver_id: string
  rc_number: string
  rc_storage_path: string | null
  vehicle_photos: string[]
  capacity_tons: number | null
  body_type: string | null
  axle_config: string | null
  maker_model: string | null
  fuel_type: string | null
  rc_status: DocStatus
  rc_expiry: string | null
  is_active: boolean
  created_at: string
  updated_at: string
  driver_insurance?: Insurance[]
}

export interface License {
  id: string
  driver_id: string
  dl_number: string
  dl_storage_path: string | null
  vehicle_classes: string[]
  expiry_date: string | null
  status: DocStatus
  created_at: string
  updated_at: string
}

export interface Insurance {
  id: string
  driver_id: string
  vehicle_id: string
  policy_number: string | null
  provider: string | null
  storage_path: string | null
  expiry_date: string | null
  status: DocStatus
  created_at: string
  updated_at: string
}

export interface BankAccount {
  id: string
  account_number_last4: string
  ifsc: string
  bank_name: string | null
  account_holder_name: string
  is_primary: boolean
  verification_status: DocStatus
  created_at: string
}

export interface OnboardingStatus {
  verification_badge: VerificationBadge
  checklist: {
    profile_complete: boolean
    license_submitted: boolean
    license_verified: boolean
    vehicle_registered: boolean
    vehicle_verified: boolean
    insurance_uploaded: boolean
    bank_linked: boolean
  }
}

export interface OnboardingProfile {
  user: {
    id: string
    full_name: string | null
    phone_number: string | null
    email: string | null
    avatar_url: string | null
    city: string | null
    state: string | null
    kyc_status: string
  }
  driver: DriverProfile | null
  license: License | null
  vehicles: Vehicle[]
  bank_accounts: BankAccount[]
}
