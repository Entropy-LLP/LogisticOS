import type { Booking, Quote, NegotiationEntry } from './types'
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
  DRIVER_PROFILE_NOT_FOUND: 'Driver profile not found for this user',
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

export function markAsPaid(bookingId: string): Promise<Booking> {
  return request<Booking>(`/bookings/${bookingId}/pay`, { method: 'PATCH' })
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

export function acceptQuote(bookingId: string, quoteId: string): Promise<Quote> {
  return request<Quote>(`/bookings/${bookingId}/quotes/${quoteId}/accept`, { method: 'PATCH' })
}

export function rejectQuote(bookingId: string, quoteId: string): Promise<Quote> {
  return request<Quote>(`/bookings/${bookingId}/quotes/${quoteId}/reject`, { method: 'PATCH' })
}

export function withdrawQuote(bookingId: string, quoteId: string): Promise<Quote> {
  return request<Quote>(`/bookings/${bookingId}/quotes/${quoteId}/withdraw`, { method: 'PATCH' })
}

export interface CreateBookingPayload {
  source_address: string
  source_lat: number
  source_lng: number
  destination_address: string
  dest_lat: number
  dest_lng: number
  load_type: string
  weight_kg: number
  quoted_price: number
  pickup_date: string
  pickup_time_slot?: string
  special_instructions?: string
  booking_type: 'direct' | 'auction'
  target_driver_id?: string
  auction_deadline?: string
}

export function createBooking(payload: CreateBookingPayload): Promise<Booking> {
  const clean = Object.fromEntries(
    Object.entries(payload).filter(([, v]) => v !== undefined && v !== null && v !== '')
  )
  return request<Booking>('/bookings/', { method: 'POST', body: JSON.stringify(clean) })
}

export function cancelBooking(id: string): Promise<Booking> {
  return request<Booking>(`/bookings/${id}/cancel`, { method: 'PATCH' })
}

export function getQuoteHistory(
  bookingId: string,
  quoteId: string
): Promise<NegotiationEntry[]> {
  return request<NegotiationEntry[]>(`/bookings/${bookingId}/quotes/${quoteId}/history`)
}

// ── Location tracking ────────────────────────────────────────

export interface DriverLocation {
  driver_id: string
  lat: number
  lng: number
  heading: number | null
  speed_kmh: number | null
  accuracy_m: number | null
  booking_id: string | null
  updated_at: string
}

export function getBookingLocation(bookingId: string): Promise<DriverLocation | null> {
  return request<DriverLocation | null>(`/location/booking/${bookingId}`)
}
