'use client'

/**
 * THROWAWAY Phase-0 verification page (Maps & Tracking).
 * Proves the referrer-restricted browser key loads the Maps JavaScript API.
 * Safe to delete once Phase 1 ships the real LiveTrackMap.
 * Route: /maps-test
 */

import {
  APIProvider,
  Map,
  AdvancedMarker,
  Pin,
  useApiLoadingStatus,
  APILoadingStatus,
} from '@vis.gl/react-google-maps'

const BROWSER_KEY = process.env.NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY ?? ''
const MAP_ID = process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? 'DEMO_MAP_ID'

// Roughly centers the Indian landmass.
const INDIA_CENTER = { lat: 22.5, lng: 79.0 }
const DELHI = { lat: 28.6139, lng: 77.209 }

function StatusBadge() {
  const status = useApiLoadingStatus()
  const ok = status === APILoadingStatus.LOADED
  const failed =
    status === APILoadingStatus.FAILED ||
    status === APILoadingStatus.AUTH_FAILURE
  return (
    <div
      style={{
        position: 'absolute',
        top: 12,
        left: 12,
        zIndex: 10,
        padding: '8px 12px',
        borderRadius: 8,
        fontFamily: 'system-ui, sans-serif',
        fontSize: 13,
        fontWeight: 600,
        color: '#fff',
        background: ok ? '#16a34a' : failed ? '#dc2626' : '#525252',
        boxShadow: '0 1px 4px rgba(0,0,0,0.3)',
      }}
    >
      Maps JS API: {status}
      {ok ? ' ✓ key works' : failed ? ' ✗ key/referrer/API problem' : ' …'}
    </div>
  )
}

export default function MapsTestPage() {
  if (!BROWSER_KEY) {
    return (
      <div style={{ padding: 24, fontFamily: 'system-ui, sans-serif' }}>
        <h1>Maps test</h1>
        <p style={{ color: '#dc2626' }}>
          NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY is not set. Check
          shipper/.env.local and restart the dev server.
        </p>
      </div>
    )
  }

  return (
    <APIProvider apiKey={BROWSER_KEY}>
      <div style={{ position: 'relative', width: '100vw', height: '100vh' }}>
        <StatusBadge />
        <Map
          defaultCenter={INDIA_CENTER}
          defaultZoom={4.6}
          mapId={MAP_ID}
          gestureHandling="greedy"
          disableDefaultUI={false}
        >
          <AdvancedMarker position={DELHI}>
            <Pin background="#2563eb" borderColor="#1e40af" glyphColor="#fff" />
          </AdvancedMarker>
        </Map>
      </div>
    </APIProvider>
  )
}
