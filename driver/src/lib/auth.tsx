'use client'

import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import { getToken, setToken as saveToken, clearToken } from './api'

type AuthContextType = {
  token: string | null
  isReady: boolean
  login: (token: string) => void
  logout: () => void
}

const AuthContext = createContext<AuthContextType>({
  token: null,
  isReady: false,
  login: () => {},
  logout: () => {},
})

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setTokenState] = useState<string | null>(null)
  const [isReady, setIsReady] = useState(false)

  useEffect(() => {
    setTokenState(getToken())
    setIsReady(true)
  }, [])

  function login(t: string) {
    saveToken(t)
    setTokenState(t)
  }

  function logout() {
    clearToken()
    setTokenState(null)
  }

  return (
    <AuthContext.Provider value={{ token, isReady, login, logout }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  return useContext(AuthContext)
}
