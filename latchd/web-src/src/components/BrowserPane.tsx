import { useEffect, useRef, useState } from "react"
import type { ReactNode } from "react"
import type { FileEntry } from "@/lib/api"
import { FileGrid } from "@/components/FileGrid"
import { FileTable } from "@/components/FileTable"
import { Mi } from "@/components/Mi"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { fmtSort, nextSort, parseSort, type SortKey, type SortSpec } from "@/lib/sort"
import { VIEWS } from "@/lib/views"

const CHUNK = 200

const SORT_OPTIONS: [string, string][] = [
  ["name:1", "Name A–Z"],
  ["name:-1", "Name Z–A"],
  ["date:-1", "Newest first"],
  ["date:1", "Oldest first"],
  ["size:-1", "Largest first"],
  ["size:1", "Smallest first"],
]

function Empty({
  icon,
  title,
  sub,
}: {
  icon: "folder_open" | "search"
  title: string
  sub: string
}) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-24 text-center">
      <Mi n={icon} className="text-[44px] text-text3" />
      <p className="font-medium">{title}</p>
      <p className="max-w-sm text-sm text-text2">{sub}</p>
    </div>
  )
}

export function BrowserPane({
  list,
  totalFiles,
  view,
  searching,
  query,
  sort,
  onSortChange,
  layout,
  onLayoutChange,
  onOpen,
}: {
  list: FileEntry[]
  totalFiles: number
  view: string
  searching: boolean
  query: string
  sort: SortSpec
  onSortChange: (s: SortSpec) => void
  layout: "list" | "grid"
  onLayoutChange: (l: "list" | "grid") => void
  onOpen: (index: number) => void
}) {
  const [shown, setShown] = useState(CHUNK)
  const sentinelRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    setShown(CHUNK)
  }, [list])

  useEffect(() => {
    const el = sentinelRef.current
    if (!el) return
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((en) => en.isIntersecting)) {
          setShown((s) => (s < list.length ? s + CHUNK : s))
        }
      },
      { rootMargin: "600px" },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [list.length])

  const viewDef = VIEWS.find((v) => v.id === view)
  const title = searching ? "Search results" : (viewDef?.label ?? "All files")
  const countText = searching
    ? `${list.length} match${list.length === 1 ? "" : "es"}`
    : view === "all"
      ? `${totalFiles.toLocaleString()} file${totalFiles === 1 ? "" : "s"}`
      : `${list.length} of ${totalFiles}`

  let empty: ReactNode = null
  if (list.length === 0) {
    if (totalFiles === 0) {
      empty = (
        <Empty
          icon="folder_open"
          title="Nothing here yet"
          sub="Back up from your phone to fill this folder."
        />
      )
    } else if (searching) {
      empty = (
        <Empty
          icon="search"
          title="No matches"
          sub={`No backed-up file names contain “${query}”.`}
        />
      )
    } else {
      const label = (viewDef?.label ?? "files").toLowerCase()
      empty = (
        <Empty
          icon="folder_open"
          title={`No ${label}`}
          sub={`No ${label} in this backup.`}
        />
      )
    }
  }

  return (
    <div>
      <div className="sticky top-0 z-10 -mx-4 flex flex-wrap items-center gap-3 bg-background/95 px-4 pt-4 pb-3 backdrop-blur md:-mx-6 md:px-6">
        <h2 className="text-xl font-bold tracking-tight">{title}</h2>
        <span className="text-sm text-text3">{countText}</span>
        <div className="ml-auto flex items-center gap-2">
          <Select
            value={fmtSort(sort)}
            onValueChange={(v) => onSortChange(parseSort(v))}
          >
            <SelectTrigger size="sm" className="h-8 w-[150px]" aria-label="Sort files">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SORT_OPTIONS.map(([v, label]) => (
                <SelectItem key={v} value={v}>
                  {label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <div
            className="flex rounded-[10px] border border-divider p-0.5"
            role="group"
            aria-label="Layout"
          >
            <button
              type="button"
              aria-label="List layout"
              aria-pressed={layout === "list"}
              className={`grid size-8 place-items-center rounded-lg transition-colors ${
                layout === "list" ? "bg-bg2 text-text" : "text-text3 hover:text-text2"
              }`}
              onClick={() => onLayoutChange("list")}
            >
              <Mi n="view_list" className="text-[18px]" />
            </button>
            <button
              type="button"
              aria-label="Grid layout"
              aria-pressed={layout === "grid"}
              className={`grid size-8 place-items-center rounded-lg transition-colors ${
                layout === "grid" ? "bg-bg2 text-text" : "text-text3 hover:text-text2"
              }`}
              onClick={() => onLayoutChange("grid")}
            >
              <Mi n="grid_view" className="text-[18px]" />
            </button>
          </div>
        </div>
      </div>

      {empty ??
        (layout === "grid" ? (
          <FileGrid list={list} shown={shown} onOpen={onOpen} />
        ) : (
          <FileTable
            list={list}
            shown={shown}
            sort={sort}
            onSortKey={(k: SortKey) => onSortChange(nextSort(sort, k))}
            onOpen={onOpen}
          />
        ))}

      {shown < list.length && <div ref={sentinelRef} className="h-px" aria-hidden="true" />}
    </div>
  )
}
