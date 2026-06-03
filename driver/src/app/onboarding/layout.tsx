'use client'

import { useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import { useAuth } from '@/lib/auth'

const STEPS = [
  { path: '/onboarding/personal', label: 'Profile' },
  { path: '/onboarding/vehicle', label: 'Vehicle' },
  { path: '/onboarding/license', label: 'License' },
  { path: '/onboarding/insurance', label: 'Insurance' },
  { path: '/onboarding/bank-account', label: 'Bank' },
  { path: '/onboarding/review', label: 'Review' },
] as const

export default function OnboardingLayout({ children }: { children: React.ReactNode }) {
  const { token, isReady } = useAuth()
  const router = useRouter()
  const pathname = usePathname()

  useEffect(() => {
    if (isReady && !token) {
      router.replace('/login')
    }
  }, [isReady, token, router])

  if (!isReady) {
    return (
      <div className="h-full flex items-center justify-center">
        <div className="w-8 h-8 border-3 border-blue-600 border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  if (!token) return null

  const currentIndex = STEPS.findIndex(s => pathname.startsWith(s.path))
  const stepNum = currentIndex === -1 ? 0 : currentIndex

  return (
    <div className="h-full flex flex-col bg-gray-50">
      {/* Header */}
      <header className="sticky top-0 z-30 bg-white border-b border-gray-200 px-4">
        <div className="h-14 flex items-center justify-between">
          <h1 className="font-bold text-lg text-gray-900">Driver Setup</h1>
          <span className="text-xs text-gray-400 font-medium">
            Step {stepNum + 1} of {STEPS.length}
          </span>
        </div>

        {/* Progress stepper */}
        <div className="pb-3 flex items-center gap-1">
          {STEPS.map((step, i) => (
            <div key={step.path} className="flex-1 flex flex-col items-center gap-1">
              <div
                className={`h-1.5 w-full rounded-full transition-colors duration-300 ${
                  i < stepNum
                    ? 'bg-green-500'
                    : i === stepNum
                      ? 'bg-blue-600'
                      : 'bg-gray-200'
                }`}
              />
              <span
                className={`text-[10px] font-medium transition-colors duration-300 ${
                  i < stepNum
                    ? 'text-green-600'
                    : i === stepNum
                      ? 'text-blue-600'
                      : 'text-gray-400'
                }`}
              >
                {step.label}
              </span>
            </div>
          ))}
        </div>
      </header>

      {/* Content */}
      <main className="flex-1 overflow-y-auto">
        {children}
      </main>
    </div>
  )
}
