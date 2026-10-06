import { useEffect, useRef, useState } from "react"
import { LegalGate } from "@/components/LegalGate"
import { Logomark } from "@/components/Logomark"
import { MainView } from "@/components/MainView"
import { Mi } from "@/components/Mi"
import { DEFAULT_UNLOCK_SUB } from "@/components/UnlockPane"
import { api, getJSON, type StatusInfo } from "@/lib/api"
import { setTheme, useTheme } from "@/lib/theme"

function App() {
  const t = useTheme()
  const [booted, setBooted] = useState(false)
  const [legalOk, setLegalOk] = useState(true)
  const [view, setView] = useState<"files" | "settings" | "pair">("files")
  const [pairOrigin, setPairOrigin] = useState<"files" | "settings">("files")
  const [navOpen, setNavOpen] = useState(false)
  const [revision, setRevision] = useState(0)
  const viewRef = useRef(view)
  useEffect(() => { viewRef.current = view }, [view])
  const [unlocked, setUnlocked] = useState(false)
  const [hasLocal, setHasLocal] = useState(false)
  const [unlockNote, setUnlockNote] = useState(DEFAULT_UNLOCK_SUB)
  const [search, setSearch] = useState("")
  const searchRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    getJSON<StatusInfo>("/api/status")
      .then((d) => {
        setHasLocal(!!d.hasLocal)
        setLegalOk(d.legalAccepted !== false)
        if (d.unlocked) {
          setUnlocked(true)
           setView("files")
        } else if (d.hasLocal) {
          setUnlocked(false)
           setView("files")
        } else {
          setView("pair")
        }
        setBooted(true)
      })
      .catch(() => {
        setView("pair")
        setBooted(true)
      })
  }, [])

  // "/" focuses search, Drive-style.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== "/" || !unlocked || view !== "files") return
      const el = e.target as HTMLElement
      if (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT") return
      e.preventDefault()
      searchRef.current?.focus()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [unlocked, view])

  function lock() {
    api("/api/lock").then(() => {
      setUnlocked(false)
      setSearch("")
    })
  }

  function enterMain(u: boolean, note?: string) {
    if (!u && note) setUnlockNote(note)
    if (viewRef.current === "pair") setView(note ? "files" : pairOrigin)
    setRevision((r) => r + 1)
    getJSON<StatusInfo>("/api/status")
      .then((d) => {
        setHasLocal(!!d.hasLocal)
        setUnlocked(!!d.unlocked)
        setLegalOk(d.legalAccepted !== false)
      })
      .catch(() => {})
  }

  const showChrome = view === "files" && unlocked

  function navigate(next: "files" | "settings" | "pair") {
    if (next === "pair" && view !== "pair") setPairOrigin(view === "settings" ? "settings" : "files")
    setView(next)
    setNavOpen(false)
  }

  return (
    <div className="flex h-dvh flex-col">
      <header className="z-20 flex min-h-16 shrink-0 flex-wrap items-center gap-2 border-b border-divider bg-bg2 px-3 py-2 md:px-5">
        {booted && legalOk && <button id="navigation-toggle" type="button" aria-label="Open navigation" aria-expanded={navOpen} aria-controls="mobile-navigation" onClick={() => setNavOpen(true)} className="grid size-11 place-items-center rounded-lg text-text2 hover:bg-surface md:hidden"><Mi n="menu" className="text-[22px]" /></button>}
        <div className="flex shrink-0 items-center gap-2.5">
          <Logomark className="h-7 text-logo" />
          <span className="text-lg font-bold">Latch</span>
        </div>

        {showChrome && (
          <div className="order-last w-full min-w-0 md:order-none md:mx-auto md:w-auto md:max-w-[720px] md:flex-1 md:px-6">
            <div className="relative">
              <Mi
                n="search"
                className="absolute top-1/2 left-3 -translate-y-1/2 text-[18px] text-text3"
              />
              <input
                ref={searchRef}
                type="search"
                value={search}
                placeholder="Search files…  (press /)"
                aria-label="Search backup contents"
                className="h-10 w-full rounded-xl border border-transparent bg-bg2 pr-4 pl-10 text-sm outline-none transition-colors placeholder:text-text3 focus:border-line focus:bg-background"
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Escape") (e.target as HTMLInputElement).blur()
                }}
              />
            </div>
          </div>
        )}

        <div className="ml-auto flex shrink-0 items-center gap-1">
          {showChrome && (
            <button
              type="button"
              onClick={lock}
              title="Lock now"
              aria-label="Lock now"
              className="grid size-11 place-items-center rounded-lg text-text2 transition-colors hover:bg-surface hover:text-foreground"
            >
              <Mi n="lock" className="text-[20px]" />
            </button>
          )}
          <button
            type="button"
            onClick={() => setTheme(t.dark ? "light" : "dark")}
            aria-label="Toggle dark mode"
            className="grid size-11 place-items-center rounded-lg text-text2 transition-colors hover:bg-surface hover:text-foreground"
          >
            <Mi n={t.dark ? "light_mode" : "dark_mode"} className="text-[20px]" />
          </button>
        </div>
      </header>

      <main className="min-h-0 flex-1">
        {!booted ? (
          <div className="grid h-full place-items-center">
            <span className="size-8 animate-spin rounded-full border-[3px] border-divider border-t-brand" />
          </div>
        ) : !legalOk ? (
          <LegalGate
            onAccepted={() => {
              setLegalOk(true)
              getJSON<StatusInfo>("/api/status")
                .then((d) => {
                  setHasLocal(!!d.hasLocal)
                  if (d.unlocked) {
                    setUnlocked(true)
                    setView("files")
                  } else if (d.hasLocal) {
                    setUnlocked(false)
                    setView("files")
                  } else {
                    setView("pair")
                  }
                })
                .catch(() => {})
            }}
          />
        ) : (
          <MainView
            unlocked={unlocked}
            unlockNote={unlockNote}
            searchTerm={search}
            onUnlock={() => setUnlocked(true)}
            screen={view}
            onNavigate={navigate}
            hasLocal={hasLocal}
            revision={revision}
            pairOrigin={pairOrigin}
            onEnterMain={enterMain}
            navOpen={navOpen}
            onNavClose={() => setNavOpen(false)}
          />
        )}
      </main>
    </div>
  )
}

export default App
