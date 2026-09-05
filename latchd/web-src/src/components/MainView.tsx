import { useDeferredValue, useEffect, useMemo, useState } from "react"
import type { FileEntry, StatusInfo } from "@/lib/api"
import { getJSON } from "@/lib/api"
import { BrowserPane } from "@/components/BrowserPane"
import { Sidebar } from "@/components/Sidebar"
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
  onPairAgain: () => void
}

export function MainView({
  unlocked,
  unlockNote,
  searchTerm,
  onUnlock,
  onPairAgain,
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

  const search = useDeferredValue(searchTerm)
  const searching = search.trim().length > 0

  useEffect(() => {
    if (!unlocked) {
      setFiles([])
      setViewerIndex(null)
      return
    }
    getJSON<{ files?: FileEntry[] }>("/api/browse")
      .then((d) => setFiles(d.files ?? []))
      .catch(() => {
        /* locked or latchd gone; panes already gated */
      })
    getJSON<StatusInfo>("/api/status")
      .then((d) =>
        setStats({ files: d.files ?? 0, dir: d.dir ?? "", lastBackup: d.lastBackup ?? null }),
      )
      .catch(() => {
        /* keep last known */
      })
  }, [unlocked])

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
    <div className="flex h-full min-h-0 flex-col md:flex-row">
      <Sidebar
        files={files}
        activeView={activeView}
        onViewChange={(v) => {
          setActiveView(v)
          setViewerIndex(null)
        }}
        stats={stats}
        unlocked={unlocked}
        onPairAgain={onPairAgain}
      />

      <section className="min-h-0 min-w-0 flex-1 overflow-y-auto">
        {!unlocked ? (
          <UnlockPane note={unlockNote || DEFAULT_UNLOCK_SUB} onUnlocked={onUnlock} onPair={onPairAgain} />
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

      {viewerIndex !== null && list[viewerIndex] && (
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
