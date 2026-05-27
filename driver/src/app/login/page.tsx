'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/lib/auth'
import { toast } from 'sonner'

export default function LoginPage() {
  const [token, setToken] = useState('')
  const { login } = useAuth()
  const router = useRouter()

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const trimmed = token.trim()
    if (!trimmed) {
      toast.error('Please paste a JWT token')
      return
    }
    login(trimmed)
    toast.success('Signed in')
    router.push('/available')
  }

  return (
    <div className="flex items-center justify-center min-h-screen px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-2xl shadow-lg p-8">
          <div className="text-center mb-8">
            <div className="w-16 h-16 bg-blue-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 17a2 2 0 11-4 0 2 2 0 014 0zM19 17a2 2 0 11-4 0 2 2 0 014 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10m10 0h-3m3 0h4a1 1 0 001-1v-5a1 1 0 00-.8-.97l-3.2-.64A1 1 0 0013 9.37V16" />
              </svg>
            </div>
            <h1 className="text-2xl font-bold text-gray-900">BharatTruck</h1>
            <p className="text-gray-500 mt-1">Driver App</p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="token" className="block text-sm font-medium text-gray-700 mb-1">
                JWT Token
              </label>
              <textarea
                id="token"
                rows={4}
                value={token}
                onChange={e => setToken(e.target.value)}
                placeholder="Paste your driver JWT token here..."
                className="w-full rounded-xl border border-gray-300 px-4 py-3 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
                autoFocus
              />
            </div>

            <button
              type="submit"
              disabled={!token.trim()}
              className="w-full h-12 bg-blue-600 text-white rounded-xl font-semibold text-base disabled:opacity-40 disabled:cursor-not-allowed active:scale-[0.98] transition-transform"
            >
              Sign In
            </button>
          </form>

          <p className="text-xs text-gray-400 text-center mt-6">
            For testing: paste a valid driver JWT token
          </p>
        </div>
      </div>
    </div>
  )
}
