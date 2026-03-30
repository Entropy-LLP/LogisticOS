/**
 * Auth Service API Contracts
 * Source of truth for request/response shapes across all services.
 * Import this in any service that calls bt-auth-service.
 */
import { z } from 'zod'

export const SendOtpRequest = z.object({
  phone: z.string().regex(/^[6-9]\d{9}$/, 'Invalid Indian mobile number'),
})

export const VerifyOtpRequest = z.object({
  phone: z.string().regex(/^[6-9]\d{9}$/),
  otp: z.string().length(6),
})

export const RegisterRequest = z.object({
  name: z.string().min(2).max(100),
  role: z.enum(['shipper', 'driver', 'fleet_owner']),
  email: z.string().email().optional(),
  company_name: z.string().optional(),
  gst_number: z.string().optional(),
  vehicle_type: z.enum(['mini_truck', 'lcv', 'hcv', 'trailer']).optional(),
  vehicle_number: z.string().optional(),
})

export const UserResponse = z.object({
  id: z.string().uuid(),
  phone: z.string(),
  role: z.enum(['shipper', 'driver', 'fleet_owner', 'admin']),
  is_verified: z.boolean(),
  kyc_status: z.enum(['pending', 'submitted', 'approved', 'rejected']),
})

export type SendOtpRequest = z.infer<typeof SendOtpRequest>
export type VerifyOtpRequest = z.infer<typeof VerifyOtpRequest>
export type RegisterRequest = z.infer<typeof RegisterRequest>
export type UserResponse = z.infer<typeof UserResponse>
