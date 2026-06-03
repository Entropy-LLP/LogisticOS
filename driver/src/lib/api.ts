import type {
  Booking, Quote, NegotiationEntry,
  OnboardingProfile, OnboardingStatus, Vehicle, License, Insurance, BankAccount,
} from './types'
import { getSupabaseClient } from './supabase'

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080'

// ── Error handling ────────────────────────────────────────────

export class ApiError extends Error {
  code: string
  constructor(message: string, code: string) {
    super(message)
    this.code = code
  }
}

const ERROR_MESSAGES: Record<string, string> = {
  AUCTION_CLOSED: 'This booking is no longer accepting quotes',
  DUPLICATE_QUOTE: "You've already submitted a quote for this booking",
  QUOTE_NOT_FOUND: 'Quote not found — it may have been removed',
  ALREADY_AWARDED: 'This booking has already been awarded',
  NOT_FOUND: 'Booking not found',
  DRIVER_PROFILE_NOT_FOUND: 'Complete your driver profile before submitting quotes',
  FORBIDDEN: 'You do not have permission for this action',
}

// ── Authenticated request ─────────────────────────────────────

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const supabase = getSupabaseClient()
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token

  const headers: Record<string, string> = {
    ...(options.body ? { 'Content-Type': 'application/json' } : {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(options.headers as Record<string, string> || {}),
  }

  const res = await fetch(`${API_BASE}/api${path}`, { ...options, headers })

  if (res.status === 401) {
    if (typeof window !== 'undefined') {
      window.location.href = '/login'
    }
    throw new ApiError('Session expired', 'UNAUTHORIZED')
  }

  let json
  try {
    json = await res.json()
  } catch {
    throw new ApiError('Server error — please try again', 'NETWORK_ERROR')
  }

  if (!json.success) {
    const code = json.code || 'UNKNOWN'
    const message = ERROR_MESSAGES[code] || json.message || json.error || 'Something went wrong'
    throw new ApiError(message, code)
  }

  return json.data
}

// ── Bookings ──────────────────────────────────────────────────

export function listBookings(): Promise<Booking[]> {
  return request<Booking[]>('/bookings/')
}

export function getBooking(id: string): Promise<Booking> {
  return request<Booking>(`/bookings/${id}`)
}

// ── Quotes ────────────────────────────────────────────────────

export function getQuotes(bookingId: string): Promise<Quote[]> {
  return request<Quote[]>(`/bookings/${bookingId}/quotes`)
}

export function submitQuote(
  bookingId: string,
  body: { amount: number; message?: string }
): Promise<Quote> {
  return request<Quote>(`/bookings/${bookingId}/quotes`, {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export function counterQuote(
  bookingId: string,
  quoteId: string,
  body: { amount: number; message?: string }
): Promise<Quote> {
  return request<Quote>(`/bookings/${bookingId}/quotes/${quoteId}/counter`, {
    method: 'PATCH',
    body: JSON.stringify(body),
  })
}

export function withdrawQuote(bookingId: string, quoteId: string): Promise<Quote> {
  return request<Quote>(`/bookings/${bookingId}/quotes/${quoteId}/withdraw`, {
    method: 'PATCH',
  })
}

export function getQuoteHistory(
  bookingId: string,
  quoteId: string
): Promise<NegotiationEntry[]> {
  return request<NegotiationEntry[]>(`/bookings/${bookingId}/quotes/${quoteId}/history`)
}

// ── Trip lifecycle ───────────────────────────────────────────

export function startTrip(bookingId: string): Promise<Booking> {
  return request<Booking>(`/bookings/${bookingId}/start`, { method: 'PATCH' })
}

export function completeTrip(bookingId: string): Promise<Booking> {
  return request<Booking>(`/bookings/${bookingId}/complete`, { method: 'PATCH' })
}

// ── Location ─────────────────────────────────────────────────

export interface LocationUpdate {
  lat: number
  lng: number
  heading?: number
  speed_kmh?: number
  accuracy_m?: number
  booking_id?: string
}

export function pushLocation(body: LocationUpdate) {
  return request<{ driver_id: string; lat: number; lng: number; updated_at: string }>(
    '/location/update',
    { method: 'POST', body: JSON.stringify(body) },
  )
}

// ── Onboarding ──────────────────────────────────────────────

export function getOnboardingProfile(): Promise<OnboardingProfile> {
  return request<OnboardingProfile>('/onboarding/profile')
}

export function updateDriverProfile(body: {
  full_name?: string
  photo_url?: string
  languages?: string[]
  home_base_city?: string
  home_base_lat?: number
  home_base_lng?: number
}) {
  return request<{ driver: OnboardingProfile['driver'] }>('/onboarding/profile', {
    method: 'PUT',
    body: JSON.stringify(body),
  })
}

export function getOnboardingStatus(): Promise<OnboardingStatus> {
  return request<OnboardingStatus>('/onboarding/status')
}

// Vehicles

export function createVehicle(body: {
  rc_number: string
  rc_storage_path?: string
  vehicle_photos?: string[]
  capacity_tons?: number
  body_type?: string
  axle_config?: string
  maker_model?: string
  fuel_type?: string
  rc_expiry?: string
}): Promise<{ vehicle: Vehicle }> {
  return request('/onboarding/vehicle', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export function updateVehicle(vehicleId: string, body: Record<string, unknown>): Promise<{ vehicle: Vehicle }> {
  return request(`/onboarding/vehicle/${vehicleId}`, {
    method: 'PUT',
    body: JSON.stringify(body),
  })
}

export function getVehicles(): Promise<{ vehicles: Vehicle[] }> {
  return request('/onboarding/vehicles')
}

// License

export function submitLicense(body: {
  dl_number: string
  dl_storage_path?: string
  vehicle_classes?: string[]
  expiry_date?: string
}): Promise<{ license: License }> {
  return request('/onboarding/license', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export function updateLicense(body: Record<string, unknown>): Promise<{ license: License }> {
  return request('/onboarding/license', {
    method: 'PUT',
    body: JSON.stringify(body),
  })
}

// Insurance

export function submitInsurance(vehicleId: string, body: {
  policy_number: string
  provider?: string
  storage_path?: string
  expiry_date?: string
}): Promise<{ insurance: Insurance }> {
  return request(`/onboarding/vehicle/${vehicleId}/insurance`, {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

// Bank accounts

export function linkBankAccount(body: {
  account_number: string
  ifsc: string
  bank_name?: string
  account_holder_name: string
  is_primary?: boolean
}): Promise<{ bank_account: BankAccount }> {
  return request('/onboarding/bank-account', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export function getBankAccounts(): Promise<{ bank_accounts: BankAccount[] }> {
  return request('/onboarding/bank-accounts')
}

export function deleteBankAccount(accountId: string): Promise<{ message: string }> {
  return request(`/onboarding/bank-account/${accountId}`, { method: 'DELETE' })
}
