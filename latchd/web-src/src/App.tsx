import { useEffect, useRef, useState } from "react"
import { Logomark } from "@/components/Logomark"
import { MainView } from "@/components/MainView"
import { Mi } from "@/components/Mi"
import { PairingView } from "@/components/PairingView"
import { DEFAULT_UNLOCK_SUB } from "@/components/UnlockPane"
import { api, getJSON, type StatusInfo } from "@/lib/api"
import { setTheme, useTheme } from "@/lib/theme"

function App() {
  const t = useTheme()
  const [booted, setBooted] = useState(false)
  const [view, setView] = useState<"main" | "pair">("main")
  const [unlocked, setUnlocked] = useState(false)
  const [hasLocal, setHasLocal] = useState(false)
  const [unlockNote, setUnlockNote] = useState(DEFAULT_UNLOCK_SUB)
  const [search, setSearch] = useState("")
  const searchRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    getJSON<StatusInfo>("/api/status")
      .then((d) => {
        setHasLocal(!!d.hasLocal)
        if (d.unlocked) {
          setUnlocked(true)
          setView("main")
        } else if (d.hasLocal) {
          setUnlocked(false)
          setView("main")
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
      if (e.key !== "/" || !unlocked || view !== "main") return
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
    setView("main")
    getJSON<StatusInfo>("/api/status")
      .then((d) => setHasLocal(!!d.hasLocal))
      .catch(() => {})
  }

  const showChrome = view === "main" && unlocked

  return (
    <div className="flex h-dvh flex-col">
      <header className="z-20 flex h-14 shrink-0 items-center gap-2 border-b border-divider bg-background px-3 md:px-4">
        <div className="flex shrink-0 items-center gap-2.5">
          <Logomark className="h-7 text-logo" />
          <span className="text-lg font-bold">Latch</span>
        </div>

        {showChrome && (
          <div className="mx-auto hidden w-full max-w-[560px] min-w-0 sm:block">
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
              className="grid size-9 place-items-center rounded-lg text-text2 transition-colors hover:bg-bg2 hover:text-text"
            >
              <Mi n="lock" className="text-[20px]" />
            </button>
          )}
          <button
            type="button"
            onClick={() => setTheme(t.dark ? "light" : "dark")}
            aria-label="Toggle dark mode"
            className="grid size-9 place-items-center rounded-lg text-text2 transition-colors hover:bg-bg2 hover:text-text"
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
        ) : view === "pair" ? (
          <PairingView hasLocal={hasLocal} unlocked={unlocked} onEnterMain={enterMain} />
        ) : (
          <MainView
            unlocked={unlocked}
            unlockNote={unlockNote}
            searchTerm={search}
            onUnlock={() => setUnlocked(true)}
            onPairAgain={() => setView("pair")}
          />
        )}
      </main>
    </div>
  )
}

export default App
