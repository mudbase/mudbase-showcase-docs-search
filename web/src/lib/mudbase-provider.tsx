"use client"

import React, { createContext, useContext, useEffect, useState, useCallback } from "react"
import { MudbaseClient, initMudbase, type MudbaseConfig, type SessionResponse } from "./mudbase"

interface MudbaseContextValue {
  client: MudbaseClient
  session: SessionResponse | null
  loading: boolean
  refreshSession: () => Promise<void>
}

const MudbaseContext = createContext<MudbaseContextValue | null>(null)

export function MudbaseProvider({
  children,
  config,
}: {
  children: React.ReactNode
  config: MudbaseConfig
}): React.JSX.Element {
  const [client] = useState<MudbaseClient>(() => initMudbase(config))
  const [session, setSession] = useState<SessionResponse | null>(null)
  const [loading, setLoading] = useState<boolean>(true)

  const refreshSession = useCallback(async (): Promise<void> => {
    try {
      const s = await client.getSession()
      setSession(s)
    } catch {
      setSession(null)
      client.clearToken()
    }
  }, [client])

  useEffect(() => {
    const establish = async (): Promise<void> => {
      if (client.getToken()) {
        await refreshSession()
        setLoading(false)
        return
      }
      // Guest browsing: an anonymous session lets the public document library resolve reads
      // (verified live: every collection read 401s with no auth at all, even with the
      // project's own publishable key). Creating/editing/deleting documents and asking AI
      // still require a real, signed-in "customer" account - see useAuth's isAuthenticated.
      try {
        await client.loginAnonymous()
        await refreshSession()
      } catch {
        setSession(null)
      } finally {
        setLoading(false)
      }
    }
    void establish()
  }, [client, refreshSession])

  return (
    <MudbaseContext.Provider value={{ client, session, loading, refreshSession }}>
      {children}
    </MudbaseContext.Provider>
  )
}

export function useMudbase(): MudbaseContextValue {
  const ctx = useContext(MudbaseContext)
  if (!ctx) throw new Error("useMudbase must be used inside <MudbaseProvider>")
  return ctx
}
