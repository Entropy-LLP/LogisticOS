'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { getSupabaseClient } from '@/lib/supabase'

export default function AuthCallbackPage() {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const supabase = getSupabaseClient()
    const params = new URLSearchParams(window.location.search)
    const code = params.get('code')

    if (code) {
      supabase.auth.exchangeCodeForSession(code).then(({ error }) => {
        if (error) {
          setError(error.message)
        } else {
          router.replace('/available')
        }
      })
    } else {
      // Implicit flow (hash fragment) — check for an active session
      supabase.auth.getSession().then(({ data: { session } }) => {
        if (session) {
          router.replace('/available')
        } else {
          setError('Authentication failed — no session found.')
        }
      })
    }
  }, [router])

  if (error) {
    return (
      <div className="flex items-center justify-center min-h-screen px-4">
        <div className="text-center">
          <p className="text-red-600 font-medium mb-4">{error}</p>
          <a href="/login" className="text-sm text-blue-600 hover:text-blue-700">
            Back to login
          </a>
        </div>
      </div>
    )
  }

  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="text-center">
        <div className="animate-spin h-8 w-8 border-4 border-blue-600 border-t-transparent rounded-full mx-auto" />
        <p className="text-sm text-gray-500 mt-4">Signing you in…</p>
      </div>
    </div>
  )
}
