/**
 * Booking Service API Contracts
 */
import { z } from 'zod'

export const VehicleType = z.enum(['mini_truck', 'lcv', 'hcv', 'trailer'])
export const LoadType = z.enum(['general', 'fragile', 'perishable', 'hazardous', 'heavy_machinery'])
export const BookingStatus = z.enum([
  'pending',
  'driver_assigned',
  'pickup_confirmed',
  'in_transit',
  'delivered',
  'cancelled',
])

export const CreateBookingRequest = z.object({
  pickup_address: z.string(),
  pickup_lat: z.number(),
  pickup_lng: z.number(),
  drop_address: z.string(),
  drop_lat: z.number(),
  drop_lng: z.number(),
  vehicle_type: VehicleType,
  load_type: LoadType,
  weight_kg: z.number().positive(),
  scheduled_at: z.string().datetime(),
  notes: z.string().optional(),
})

export const BookingResponse = z.object({
  id: z.string().uuid(),
  shipper_id: z.string().uuid(),
  driver_id: z.string().uuid().nullable(),
  status: BookingStatus,
  pickup_address: z.string(),
  drop_address: z.string(),
  vehicle_type: VehicleType,
  load_type: LoadType,
  weight_kg: z.number(),
  quoted_price: z.number(),
  scheduled_at: z.string(),
  created_at: z.string(),
})

export type CreateBookingRequest = z.infer<typeof CreateBookingRequest>
export type BookingResponse = z.infer<typeof BookingResponse>
export type VehicleType = z.infer<typeof VehicleType>
export type LoadType = z.infer<typeof LoadType>
export type BookingStatus = z.infer<typeof BookingStatus>
