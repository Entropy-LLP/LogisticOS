'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth'
import { getSupabaseClient } from '@/lib/supabase'

const APP_ROLE = 'shipper'
const POST_LOGIN_PATH = '/dashboard'

type Tab = 'phone' | 'google' | 'email' | 'magic-link'

const TABS: { id: Tab; label: string }[] = [
  { id: 'phone', label: 'Phone' },
  { id: 'google', label: 'Google' },
  { id: 'email', label: 'Email' },
  { id: 'magic-link', label: 'Magic Link' },
]

export default function LoginPage() {
  const [tab, setTab] = useState<Tab>('phone')
  const [awaitingRegistration, setAwaitingRegistration] = useState(false)
  const { user, isReady } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!isReady || !user || awaitingRegistration) return
    router.replace(POST_LOGIN_PATH)
  }, [isReady, user, awaitingRegistration, router])

  return (
    <div className="flex items-center justify-center min-h-screen px-4">
      <div className="w-full max-w-md">
        <div className="bg-white rounded-2xl shadow-lg p-6">
          <div className="text-center mb-6">
            <div className="w-14 h-14 bg-blue-600 rounded-2xl flex items-center justify-center mx-auto mb-3">
              <svg className="w-7 h-7 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
              </svg>
            </div>
            <h1 className="text-2xl font-bold text-gray-900">BharatTruck</h1>
            <p className="text-gray-500 text-sm mt-1">Shipper Dashboard</p>
          </div>

          <div className="flex border-b border-gray-200 mb-5">
            {TABS.map(t => (
              <button
                key={t.id}
                onClick={() => setTab(t.id)}
                className={`flex-1 pb-2.5 text-sm font-medium border-b-2 transition-colors ${
                  tab === t.id
                    ? 'border-blue-600 text-blue-600'
                    : 'border-transparent text-gray-400 hover:text-gray-600'
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>

          {tab === 'phone' && (
            <PhoneOtpForm
              onAwaitingRegistration={setAwaitingRegistration}
              onRegistered={() => router.push(POST_LOGIN_PATH)}
            />
          )}
          {tab === 'google' && <GoogleSignInForm />}
          {tab === 'email' && <EmailAuthForm />}
          {tab === 'magic-link' && <MagicLinkForm />}
        </div>
      </div>
    </div>
  )
}

// ─── Phone OTP ──────────────────────────────────────────────────

function PhoneOtpForm({
  onAwaitingRegistration,
  onRegistered,
}: {
  onAwaitingRegistration: (v: boolean) => void
  onRegistered: () => void
}) {
  const [phone, setPhone] = useState('')
  const [otp, setOtp] = useState('')
  const [step, setStep] = useState<'phone' | 'otp' | 'register'>('phone')
  const [loading, setLoading] = useState(false)
  const [name, setName] = useState('')

  async function handleSendOtp(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      const { error } = await supabase.auth.signInWithOtp({
        phone: `+91${phone}`,
        options: {
          // Requires Twilio creds in Supabase dashboard to deliver via SMS.
          data: { role: APP_ROLE },
        },
      })
      if (error) throw error
      toast.success('OTP sent to your phone')
      setStep('otp')
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Failed to send OTP')
    } finally {
      setLoading(false)
    }
  }

  async function handleVerifyOtp(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      const { data, error } = await supabase.auth.verifyOtp({
        phone: `+91${phone}`,
        token: otp,
        type: 'sms',
      })
      if (error) throw error

      const isNewUser = !data.user?.user_metadata?.full_name
      if (isNewUser) {
        onAwaitingRegistration(true)
        setStep('register')
      }
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Failed to verify OTP')
    } finally {
      setLoading(false)
    }
  }

  async function handleRegister(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      // Sync full_name into auth metadata so future logins skip this step.
      // The handle_user_metadata_update trigger syncs it to public.users.
      await supabase.auth.updateUser({ data: { full_name: name, role: APP_ROLE } })
      onAwaitingRegistration(false)
      onRegistered()
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Failed to save profile')
    } finally {
      setLoading(false)
    }
  }

  if (step === 'register') {
    return (
      <form onSubmit={handleRegister} className="space-y-4">
        <p className="text-sm text-gray-600">Welcome! Enter your name to continue.</p>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Full Name</label>
          <input
            type="text"
            value={name}
            onChange={e => setName(e.target.value)}
            required
            minLength={2}
            className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Enter your full name"
            autoFocus
          />
        </div>
        <button
          type="submit"
          disabled={loading || !name.trim()}
          className="w-full h-11 bg-blue-600 text-white rounded-lg font-medium text-sm disabled:opacity-40"
        >
          {loading ? 'Saving...' : 'Continue'}
        </button>
      </form>
    )
  }

  if (step === 'otp') {
    return (
      <form onSubmit={handleVerifyOtp} className="space-y-4">
        <p className="text-sm text-gray-600">
          Enter the 6-digit code sent to <strong>+91 {phone}</strong>
        </p>
        <input
          type="text"
          inputMode="numeric"
          maxLength={6}
          value={otp}
          onChange={e => setOtp(e.target.value.replace(/\D/g, ''))}
          className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-center text-lg font-mono tracking-[0.5em] focus:outline-none focus:ring-2 focus:ring-blue-500"
          placeholder="000000"
          autoFocus
        />
        <button
          type="submit"
          disabled={loading || otp.length !== 6}
          className="w-full h-11 bg-blue-600 text-white rounded-lg font-medium text-sm disabled:opacity-40"
        >
          {loading ? 'Verifying...' : 'Verify OTP'}
        </button>
        <button
          type="button"
          onClick={() => { setStep('phone'); setOtp('') }}
          className="w-full text-sm text-gray-500 hover:text-gray-700"
        >
          Change number
        </button>
      </form>
    )
  }

  return (
    <form onSubmit={handleSendOtp} className="space-y-4">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Phone Number</label>
        <div className="flex">
          <span className="inline-flex items-center px-3 rounded-l-lg border border-r-0 border-gray-300 bg-gray-50 text-sm text-gray-500">
            +91
          </span>
          <input
            type="tel"
            inputMode="numeric"
            maxLength={10}
            value={phone}
            onChange={e => setPhone(e.target.value.replace(/\D/g, ''))}
            className="flex-1 rounded-r-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="9876543210"
            autoFocus
          />
        </div>
      </div>
      <button
        type="submit"
        disabled={loading || phone.length !== 10}
        className="w-full h-11 bg-blue-600 text-white rounded-lg font-medium text-sm disabled:opacity-40"
      >
        {loading ? 'Sending...' : 'Send OTP'}
      </button>
    </form>
  )
}

// ─── Google Sign-In ─────────────────────────────────────────────

function GoogleSignInForm() {
  const [loading, setLoading] = useState(false)

  async function handleGoogleSignIn() {
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${window.location.origin}/auth/callback`,
          queryParams: { access_type: 'offline', prompt: 'consent' },
        },
      })
      if (error) throw error
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Google sign-in failed')
      setLoading(false)
    }
  }

  return (
    <div className="space-y-4 py-2">
      <button
        onClick={handleGoogleSignIn}
        disabled={loading}
        className="w-full h-11 flex items-center justify-center gap-3 border border-gray-300 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-40 transition-colors"
      >
        {loading ? (
          <div className="h-4 w-4 border-2 border-gray-400 border-t-transparent rounded-full animate-spin" />
        ) : (
          <svg className="w-5 h-5" viewBox="0 0 24 24">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
          </svg>
        )}
        {loading ? 'Redirecting to Google...' : 'Continue with Google'}
      </button>
      <p className="text-xs text-center text-gray-400">
        Google OAuth must be enabled in the Supabase dashboard.
      </p>
    </div>
  )
}

// ─── Email / Password ───────────────────────────────────────────

function EmailAuthForm() {
  const [mode, setMode] = useState<'login' | 'register' | 'verify'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [otp, setOtp] = useState('')
  const [loading, setLoading] = useState(false)

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) {
        if (error.message.toLowerCase().includes('email not confirmed')) {
          toast.info('Email not confirmed. Check your inbox for a verification code.')
          await supabase.auth.resend({ type: 'signup', email })
          setMode('verify')
        } else {
          throw error
        }
      }
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Login failed')
    } finally {
      setLoading(false)
    }
  }

  async function handleRegister(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      const { error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: { role: APP_ROLE, full_name: name },
          emailRedirectTo: `${window.location.origin}/auth/callback`,
        },
      })
      if (error) throw error
      toast.success('Verification code sent to your email')
      setMode('verify')
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Registration failed')
    } finally {
      setLoading(false)
    }
  }

  async function handleVerify(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      const { error } = await supabase.auth.verifyOtp({ email, token: otp, type: 'signup' })
      if (error) throw error
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Verification failed')
    } finally {
      setLoading(false)
    }
  }

  async function handleResend() {
    try {
      const supabase = getSupabaseClient()
      const { error } = await supabase.auth.resend({ type: 'signup', email })
      if (error) throw error
      toast.success('Verification code resent')
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Failed to resend')
    }
  }

  if (mode === 'verify') {
    return (
      <form onSubmit={handleVerify} className="space-y-4">
        <p className="text-sm text-gray-600">
          Enter the 6-digit code sent to <strong>{email}</strong>
        </p>
        <input
          type="text"
          inputMode="numeric"
          maxLength={6}
          value={otp}
          onChange={e => setOtp(e.target.value.replace(/\D/g, ''))}
          className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-center text-lg font-mono tracking-[0.5em] focus:outline-none focus:ring-2 focus:ring-blue-500"
          placeholder="000000"
          autoFocus
        />
        <button
          type="submit"
          disabled={loading || otp.length !== 6}
          className="w-full h-11 bg-blue-600 text-white rounded-lg font-medium text-sm disabled:opacity-40"
        >
          {loading ? 'Verifying...' : 'Verify Email'}
        </button>
        <button type="button" onClick={handleResend} className="w-full text-sm text-blue-600 hover:text-blue-700">
          Resend code
        </button>
        <button
          type="button"
          onClick={() => { setMode('login'); setOtp('') }}
          className="w-full text-sm text-gray-500 hover:text-gray-700"
        >
          Back to login
        </button>
      </form>
    )
  }

  if (mode === 'register') {
    return (
      <form onSubmit={handleRegister} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Full Name</label>
          <input
            type="text"
            value={name}
            onChange={e => setName(e.target.value)}
            required
            minLength={2}
            className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Your name"
            autoFocus
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
          <input
            type="email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            required
            className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="you@example.com"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
          <input
            type="password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            required
            minLength={8}
            className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Min 8 characters"
          />
        </div>
        <button
          type="submit"
          disabled={loading}
          className="w-full h-11 bg-blue-600 text-white rounded-lg font-medium text-sm disabled:opacity-40"
        >
          {loading ? 'Creating account...' : 'Create Account'}
        </button>
        <button
          type="button"
          onClick={() => setMode('login')}
          className="w-full text-sm text-gray-500 hover:text-gray-700"
        >
          Already have an account? Sign in
        </button>
      </form>
    )
  }

  return (
    <form onSubmit={handleLogin} className="space-y-4">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
        <input
          type="email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          required
          className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
          placeholder="you@example.com"
          autoFocus
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
        <input
          type="password"
          value={password}
          onChange={e => setPassword(e.target.value)}
          required
          className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
          placeholder="Your password"
        />
      </div>
      <button
        type="submit"
        disabled={loading}
        className="w-full h-11 bg-blue-600 text-white rounded-lg font-medium text-sm disabled:opacity-40"
      >
        {loading ? 'Signing in...' : 'Sign In'}
      </button>
      <button
        type="button"
        onClick={() => setMode('register')}
        className="w-full text-sm text-gray-500 hover:text-gray-700"
      >
        New here? Create an account
      </button>
    </form>
  )
}

// ─── Magic Link ─────────────────────────────────────────────────

function MagicLinkForm() {
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(false)
  const [loading, setLoading] = useState(false)

  async function handleSend(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      const supabase = getSupabaseClient()
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: {
          emailRedirectTo: `${window.location.origin}/auth/callback`,
          data: { role: APP_ROLE },
        },
      })
      if (error) throw error
      setSent(true)
      toast.success('Magic link sent!')
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Failed to send')
    } finally {
      setLoading(false)
    }
  }

  if (sent) {
    return (
      <div className="text-center py-4 space-y-3">
        <p className="text-3xl">&#9993;</p>
        <p className="text-sm text-gray-700">
          Sign-in link sent to <strong>{email}</strong>
        </p>
        <p className="text-xs text-gray-400">Click the link in your email to sign in.</p>
        <button
          onClick={() => { setSent(false); setEmail('') }}
          className="text-sm text-blue-600 hover:text-blue-700"
        >
          Try a different email
        </button>
      </div>
    )
  }

  return (
    <form onSubmit={handleSend} className="space-y-4">
      <p className="text-sm text-gray-600">
        We&apos;ll send you a sign-in link — no password needed.
      </p>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
        <input
          type="email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          required
          className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
          placeholder="you@example.com"
          autoFocus
        />
      </div>
      <button
        type="submit"
        disabled={loading || !email}
        className="w-full h-11 bg-blue-600 text-white rounded-lg font-medium text-sm disabled:opacity-40"
      >
        {loading ? 'Sending...' : 'Send Magic Link'}
      </button>
    </form>
  )
}
