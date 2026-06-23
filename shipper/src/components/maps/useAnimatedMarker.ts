// src/components/maps/useAnimatedMarker.ts  (identical in both apps — decision D-008)
import { useEffect, useRef, useState } from 'react'
import { bearing, lerp, type LatLng } from '@/lib/maps'

const DURATION_MS = 1400

/**
 * Animates a marker from its current position to `target` whenever `target`
 * changes (driver fixes arrive ~every 10s; a raw jump looks broken). Eases over
 * ~1.4s via requestAnimationFrame and exposes the live position + heading.
 */
export function useAnimatedMarker(target: LatLng | null) {
  const [pos, setPos] = useState<LatLng | null>(target)
  const [heading, setHeading] = useState(0)
  const fromRef = useRef<LatLng | null>(target)
  const rafRef = useRef<number | null>(null)

  useEffect(() => {
    if (!target) return
    const from = fromRef.current
    if (!from) {
      // first fix: snap, no animation
      fromRef.current = target
      setPos(target)
      return
    }
    if (from.lat === target.lat && from.lng === target.lng) return

    setHeading(bearing(from, target))
    const start = performance.now()

    const tick = (now: number) => {
      const t = Math.min((now - start) / DURATION_MS, 1)
      const eased = t * (2 - t) // easeOutQuad
      setPos(lerp(from, target, eased))
      if (t < 1) {
        rafRef.current = requestAnimationFrame(tick)
      } else {
        fromRef.current = target
      }
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current)
    }
  }, [target])

  return { pos, heading }
}
