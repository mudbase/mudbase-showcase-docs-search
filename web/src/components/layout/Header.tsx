"use client"

import Link from "next/link"
import { LogOut, Sparkles, BookOpen, PlusCircle } from "lucide-react"
import { useAuth } from "@/hooks/useAuth"
import { Button } from "@/components/ui/button"

export function Header(): React.JSX.Element {
  const { user, isAuthenticated, logout } = useAuth()

  return (
    <header className="sticky top-0 z-40 border-b border-border bg-background/95 backdrop-blur">
      <div className="container flex h-16 items-center justify-between">
        <Link href="/" className="flex items-center gap-2 font-display text-xl font-semibold tracking-tight">
          <BookOpen className="h-5 w-5 text-primary" />
          Docs Search
        </Link>

        <nav className="flex items-center gap-2">
          <Button asChild variant="ghost" size="sm">
            <Link href="/ask">
              <Sparkles className="mr-2 h-4 w-4" />
              Ask AI
            </Link>
          </Button>

          {isAuthenticated && (
            <Button asChild variant="ghost" size="sm">
              <Link href="/documents/new">
                <PlusCircle className="mr-2 h-4 w-4" />
                New document
              </Link>
            </Button>
          )}

          {isAuthenticated && user ? (
            <Button variant="outline" size="sm" onClick={() => void logout()}>
              <LogOut className="mr-2 h-4 w-4" />
              Sign out
            </Button>
          ) : (
            <>
              <Button asChild variant="ghost" size="sm">
                <Link href="/login">Sign in</Link>
              </Button>
              <Button asChild size="sm">
                <Link href="/register">Sign up</Link>
              </Button>
            </>
          )}
        </nav>
      </div>
    </header>
  )
}
