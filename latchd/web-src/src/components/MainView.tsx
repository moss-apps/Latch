import { useDeferredValue, useEffect, useMemo, useState } from "react"
import type { FileEntry, StatusInfo } from "@/lib/api"
import { getJSON } from "@/lib/api"
import { BrowserPane } from "@/components/BrowserPane"
import { Sidebar } from "@/components/Sidebar"
import { SettingsView } from "@/components/SettingsView"
import { PairingView } from "@/components/PairingView"
import { DEFAULT_UNLOCK_SUB, UnlockPane } from "@/components/UnlockPane"
import { Viewer } from "@/components/Viewer"
import {
  fmtSort,
  parseSort,
  sortFiles,
  type SortSpec,
} from "@/lib/sort"
import { viewFilter } from "@/lib/views"

const LS_SORT = "latchd-sort"
const LS_LAYOUT = "latchd-layout"

interface MainViewProps {
  unlocked: boolean
  unlockNote: string
  searchTerm: string
  onUnlock: () => void
  screen: "files" | "settings" | "pair"
  onNavigate: (screen: "files" | "settings" | "pair") => void
  hasLocal: boolean
  revision: number
  pairOrigin: "files" | "settings"
  onEnterMain: (unlocked: boolean, note?: string) => void
  navOpen: boolean
  onNavClose: () => void
}

export function MainView({
  unlocked,
  unlockNote,
  searchTerm,
  onUnlock,
  screen, onNavigate, hasLocal, revision, pairOrigin, onEnterMain, navOpen, onNavClose,
}: MainViewProps) {
  const [files, setFiles] = useState<FileEntry[]>([])
  const [stats, setStats] = useState<{ files: number; dir: string; lastBackup: string | null }>(
    { files: 0, dir: "", lastBackup: null },
  )
  const [activeView, setActiveView] = useState("all")
  const [sort, setSort] = useState<SortSpec>(() => parseSort(localStorage.getItem(LS_SORT)))
  const [layouts, setLayouts] = useState<Record<string, "list" | "grid">>(() => {
    try {
      return { ...JSON.parse(localStorage.getItem(LS_LAYOUT) || "{}") }
    } catch {
      return {}
    }
  })
  const [viewerIndex, setViewerIndex] = useState<number | null>(null)
  const [pairVisited, setPairVisited] = useState(screen === "pair")

  if (screen === "pair" && !pairVisited) setPairVisited(true)

  function navigate(next: "files" | "settings" | "pair") {
    setViewerIndex(null)
    onNavigate(next)
  }

  const search = useDeferredValue(searchTerm)
  const searching = search.trim().length > 0

  useEffect(() => {
    let cancelled = false
    getJSON<StatusInfo>("/api/status")
      .then((d) => {
        if (!cancelled) setStats({ files: d.files ?? 0, dir: d.dir ?? "", lastBackup: d.lastBackup ?? null })
      })
      .catch(() => {})
    if (!unlocked) {
      setFiles([])
      setViewerIndex(null)
      return () => { cancelled = true }
    }
    getJSON<{ files?: FileEntry[] }>("/api/browse")
      .then((d) => { if (!cancelled) setFiles(d.files ?? []) })
      .catch(() => {
        /* locked or latchd gone; panes already gated */
      })
    return () => { cancelled = true }
  }, [unlocked, revision])

  const list = useMemo(() => {
    const q = search.trim().toLowerCase()
    const filtered = q
      ? files.filter((f) => f.name.toLowerCase().includes(q))
      : files.filter((f) => viewFilter(activeView, f))
    return sortFiles(filtered, sort)
  }, [files, search, activeView, sort])

  const layout = layouts[activeView] ?? (activeView === "photos" ? "grid" : "list")

  function changeSort(s: SortSpec) {
    setSort(s)
    localStorage.setItem(LS_SORT, fmtSort(s))
  }

  function changeLayout(mode: "list" | "grid") {
    setLayouts((prev) => {
      const next = { ...prev, [activeView]: mode }
      localStorage.setItem(LS_LAYOUT, JSON.stringify(next))
      return next
    })
  }

  return (
    <div className="flex h-full min-h-0 bg-bg2">
      <Sidebar
        files={files}
        activeView={screen === "files" ? activeView : screen}
        onViewChange={(v) => {
          setActiveView(v)
          setViewerIndex(null)
          onNavigate("files")
        }}
        unlocked={unlocked}
        onNavigate={navigate}
        navOpen={navOpen}
        onNavClose={onNavClose}
      />

      <section aria-label="Backup contents" hidden={screen !== "files"} className="min-h-0 min-w-0 flex-1 overflow-y-auto bg-background md:mr-4 md:mb-4 md:rounded-2xl">
        {!unlocked ? (
          <UnlockPane note={unlockNote || DEFAULT_UNLOCK_SUB} onUnlocked={onUnlock} onPair={() => navigate("pair")} />
        ) : (
          <div className="px-4 pb-10 md:px-6">
            <BrowserPane
              list={list}
              totalFiles={files.length}
              view={activeView}
              searching={searching}
              query={search.trim()}
              sort={sort}
              onSortChange={changeSort}
              layout={layout}
              onLayoutChange={changeLayout}
              onOpen={setViewerIndex}
            />
            <p className="mt-10 text-xs leading-relaxed text-text3">
              This page talks to latchd on your own machine only. While pairing, latchd also
              accepts your phone's push on the local network; the session closes itself when
              done or left idle.
            </p>
          </div>
        )}
      </section>

      <section aria-label="Settings" hidden={screen !== "settings"} className="min-h-0 min-w-0 flex-1 overflow-y-auto bg-background md:mr-4 md:mb-4 md:rounded-2xl">
        <SettingsView stats={stats} unlocked={unlocked} hasLocal={hasLocal} onPairAgain={() => navigate("pair")} onUnlock={() => navigate("files")} />
      </section>
      {(pairVisited || screen === "pair") && <section aria-label="Phone backup" hidden={screen !== "pair"} className="min-h-0 min-w-0 flex-1 overflow-y-auto bg-background md:mr-4 md:mb-4 md:rounded-2xl">
        <PairingView hasLocal={hasLocal} unlocked={unlocked} visible={screen === "pair"} onEnterMain={onEnterMain} backLabel={pairOrigin === "settings" ? "Back to Settings" : "Back to files"} />
      </section>}

      {screen === "files" && viewerIndex !== null && list[viewerIndex] && (
        <Viewer
          list={list}
          index={viewerIndex}
          onClose={() => setViewerIndex(null)}
          onIndex={setViewerIndex}
        />
      )}
    </div>
  )
}
