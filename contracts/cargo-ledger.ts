/**
 * Cargo Ledger API Contracts
 * Defines multi-leg journey, checkpoint handshake, and proof-of-delivery shapes.
 */
import { z } from 'zod'

export const CheckpointType = z.enum([
  'pickup',        // cargo loaded at origin
  'handoff',       // transferred between trucks/drivers
  'waypoint',      // intermediate stop, no transfer
  'delivery',      // final delivery to consignee
])

export const CreateShipmentRequest = z.object({
  booking_id: z.string().uuid(),
  origin_address: z.string(),
  destination_address: z.string(),
  cargo_description: z.string(),
  total_weight_kg: z.number().positive(),
  total_pieces: z.number().int().positive(),
  legs: z.array(z.object({
    sequence: z.number().int(),
    from_address: z.string(),
    to_address: z.string(),
    assigned_driver_id: z.string().uuid().optional(),
  })),
})

export const CheckpointHandshakeRequest = z.object({
  shipment_id: z.string().uuid(),
  leg_id: z.string().uuid(),
  checkpoint_type: CheckpointType,
  lat: z.number(),
  lng: z.number(),
  address: z.string(),
  pieces_count: z.number().int(),
  weight_kg: z.number(),
  notes: z.string().optional(),
  photo_urls: z.array(z.string()).optional(), // uploaded to Cloudflare R2
  outgoing_driver_id: z.string().uuid().optional(),
  incoming_party_id: z.string().uuid().optional(),  // driver or warehouse
})

export const CheckpointResponse = z.object({
  id: z.string().uuid(),
  shipment_id: z.string().uuid(),
  leg_id: z.string().uuid(),
  checkpoint_type: CheckpointType,
  sequence: z.number(),
  lat: z.number(),
  lng: z.number(),
  address: z.string(),
  pieces_count: z.number(),
  weight_kg: z.number(),
  merkle_hash: z.string(),          // SHA-256 hash of this checkpoint's data
  blockchain_tx_hash: z.string().nullable(), // Polygon tx hash (null until confirmed)
  signed_at: z.string(),
})

export const ShipmentProofResponse = z.object({
  shipment_id: z.string().uuid(),
  booking_id: z.string().uuid(),
  is_complete: z.boolean(),
  root_hash: z.string(),            // Merkle root of all checkpoints
  blockchain_tx_hash: z.string().nullable(),
  checkpoints: z.array(CheckpointResponse),
  verification_url: z.string(),     // public URL to verify on-chain
})

export type CreateShipmentRequest = z.infer<typeof CreateShipmentRequest>
export type CheckpointHandshakeRequest = z.infer<typeof CheckpointHandshakeRequest>
export type CheckpointResponse = z.infer<typeof CheckpointResponse>
export type ShipmentProofResponse = z.infer<typeof ShipmentProofResponse>
export type CheckpointType = z.infer<typeof CheckpointType>
