/**
 * Pricing Service API Contracts
 */
import { z } from 'zod'

export const PriceQuoteRequest = z.object({
  distance_km: z.number().positive(),
  vehicle_type: z.enum(['mini_truck', 'lcv', 'hcv', 'trailer']),
  load_type: z.enum(['general', 'fragile', 'perishable', 'hazardous', 'heavy_machinery']),
  weight_kg: z.number().positive(),
  scheduled_at: z.string().datetime().optional(), // for demand-based surge
})

export const PriceQuoteResponse = z.object({
  base_price: z.number(),
  weight_surcharge: z.number(),
  total_price: z.number(),
  platform_fee: z.number(),
  shipper_pays: z.number(),
  driver_receives: z.number(),
  currency: z.literal('INR'),
  version: z.string(),             // 'v1-static' | 'v2-ml'
})

export type PriceQuoteRequest = z.infer<typeof PriceQuoteRequest>
export type PriceQuoteResponse = z.infer<typeof PriceQuoteResponse>
