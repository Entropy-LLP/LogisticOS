// src/lib/maps.ts  (identical in driver/ and shipper/ — keep in sync, decision D-008)
import { decode } from '@googlemaps/polyline-codec'

export const MAPS_BROWSER_KEY = process.env.NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY ?? ''

export interface LatLng {
  lat: number
  lng: number
}

/** Routes API encoded polyline -> [{lat,lng}] for path rendering. Empty input -> []. */
export function decodePolyline(encoded: string): LatLng[] {
  if (!encoded) return []
  return decode(encoded, 5).map(([lat, lng]) => ({ lat, lng }))
}

/** Bearing in degrees (0 = North) from a -> b, used to rotate the truck icon. */
export function bearing(a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180
  const y = Math.sin(toRad(b.lng - a.lng)) * Math.cos(toRad(b.lat))
  const x =
    Math.cos(toRad(a.lat)) * Math.sin(toRad(b.lat)) -
    Math.sin(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.cos(toRad(b.lng - a.lng))
  return (Math.atan2(y, x) * 180) / Math.PI
}

/** Linear interpolation for smooth marker movement between two GPS fixes. */
export function lerp(a: LatLng, b: LatLng, t: number): LatLng {
  return { lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t }
}

export function fmtKm(meters: number): string {
  return meters >= 1000 ? `${(meters / 1000).toFixed(1)} km` : `${Math.round(meters)} m`
}

export function fmtEta(seconds: number): string {
  const m = Math.round(seconds / 60)
  if (m < 60) return `${m} min`
  return `${Math.floor(m / 60)}h ${m % 60}m`
}
