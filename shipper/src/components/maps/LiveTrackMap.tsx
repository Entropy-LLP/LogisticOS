'use client'
// src/components/maps/LiveTrackMap.tsx  (identical in both apps — decision D-008)
//
// The one reusable live map. Renders origin/dest pins, an optional route
// polyline, and a smoothly-animated, heading-rotated truck marker.
// Phase 1 passes origin/dest/driver only (no route line); Phase 2 adds
// `encodedPolyline` from bt-tracking-service.

import { useEffect, useMemo } from 'react'
import { APIProvider, Map, AdvancedMarker, Pin, useMap } from '@vis.gl/react-google-maps'
import { MAPS_BROWSER_KEY, decodePolyline, type LatLng } from '@/lib/maps'
import { useAnimatedMarker } from './useAnimatedMarker'

const MAP_ID = process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? 'DEMO_MAP_ID'

export interface LiveTrackMapProps {
  origin: LatLng
  dest: LatLng
  /** Routes API encoded polyline (Phase 2). Omit in Phase 1. */
  encodedPolyline?: string
  /** Live driver position; null = not sharing yet / delivered (no truck shown). */
  driver?: LatLng | null
  className?: string
}

export default function LiveTrackMap(props: LiveTrackMapProps) {
  if (!MAPS_BROWSER_KEY) {
    return (
      <div className="flex items-center justify-center h-72 w-full bg-gray-100 text-sm text-gray-500 rounded-2xl">
        Map unavailable
      </div>
    )
  }
  return (
    <APIProvider apiKey={MAPS_BROWSER_KEY}>
      <div className={props.className ?? 'h-72 w-full rounded-2xl overflow-hidden'}>
        <Map
          mapId={MAP_ID}
          defaultCenter={props.origin}
          defaultZoom={9}
          gestureHandling="greedy"
          disableDefaultUI
          zoomControl
        >
          <MapContent {...props} />
        </Map>
      </div>
    </APIProvider>
  )
}

function MapContent({ origin, dest, encodedPolyline, driver }: LiveTrackMapProps) {
  const map = useMap()
  const path = useMemo(() => decodePolyline(encodedPolyline ?? ''), [encodedPolyline])
  const { pos, heading } = useAnimatedMarker(driver ?? null)

  // Fit to origin + dest (+ route, when present). Runs only when the route or
  // endpoints change — NOT on every driver fix, which would make the map jump.
  useEffect(() => {
    if (!map) return
    const bounds = new google.maps.LatLngBounds()
    bounds.extend(origin)
    bounds.extend(dest)
    path.forEach((p) => bounds.extend(p))
    map.fitBounds(bounds, 48)
  }, [map, path, origin, dest])

  // Draw the route polyline imperatively (Phase 2). No-op in Phase 1.
  useEffect(() => {
    if (!map || path.length === 0) return
    const line = new google.maps.Polyline({
      path,
      geodesic: true,
      strokeColor: '#2563eb',
      strokeOpacity: 0.9,
      strokeWeight: 5,
    })
    line.setMap(map)
    return () => line.setMap(null)
  }, [map, path])

  return (
    <>
      <AdvancedMarker position={origin} title="Pickup">
        <Pin background="#16a34a" borderColor="#15803d" glyphColor="#fff" />
      </AdvancedMarker>
      <AdvancedMarker position={dest} title="Drop">
        <Pin background="#dc2626" borderColor="#b91c1c" glyphColor="#fff" />
      </AdvancedMarker>
      {pos && (
        <AdvancedMarker position={pos} title="Driver">
          <div
            data-testid="driver-marker"
            style={{ transform: `rotate(${heading}deg)` }}
            className="text-2xl leading-none drop-shadow"
          >
            🚚
          </div>
        </AdvancedMarker>
      )}
    </>
  )
}
