import { createClient } from '@supabase/supabase-js'

let instance: ReturnType<typeof createClient> | null = null

export function getSupabaseClient() {
  if (!instance) {
    instance = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )
  }
  return instance
}
