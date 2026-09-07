import { useMemo, useState } from "react"
import { Mi } from "@/components/Mi"
import { SettingsDialog } from "@/components/SettingsDialog"
import type { FileEntry } from "@/lib/api"
import { VIEWS, viewFilter } from "@/lib/views"

interface SidebarProps {
  files: FileEntry[]
  activeView: string
  onViewChange: (view: string) => void
  stats: { files: number; dir: string; lastBackup: string | null }
  unlocked: boolean
  onPairAgain: () => void
}

export function Sidebar({
  files,
  activeView,
  onViewChange,
  stats,
  unlocked,
  onPairAgain,
}: SidebarProps) {
  const [settingsOpen, setSettingsOpen] = useState(false)
  const counts = useMemo(() => {
    const c: Record<string, number> = { all: files.length }
    for (const v of VIEWS) {
      if (v.id !== "all") c[v.id] = files.filter((f) => viewFilter(v.id, f)).length
    }
    return c
  }, [files])

  return (
    <aside className="flex shrink-0 flex-col border-b border-divider md:w-[264px] md:border-b-0 md:border-r">
      <div className="min-h-0 flex-1 overflow-x-auto p-3 md:overflow-y-auto md:p-4">
        <nav className="flex w-max min-w-full gap-1 md:w-full md:flex-col" aria-label="Views">
          {VIEWS.map((v) => {
            const active = v.id === activeView
            const n = counts[v.id] ?? 0
            return (
              <button
                key={v.id}
                type="button"
                onClick={() => onViewChange(v.id)}
                className={`flex h-10 shrink-0 items-center gap-2.5 rounded-[10px] px-3 text-sm transition-colors md:w-full ${
                  active
                    ? "bg-brand/10 font-medium text-brand"
                    : "text-text2 hover:bg-bg2 hover:text-text"
                }`}
                aria-current={active ? "page" : undefined}
              >
                <Mi n={v.icon} className="text-[18px]" />
                <span className="flex-1 truncate text-left">{v.label}</span>
                {n > 0 && <span className="text-xs text-text3">{n}</span>}
              </button>
            )
          })}
        </nav>
      </div>

      <div className="shrink-0 border-t border-divider p-2 md:p-3">
        <button
          type="button"
          onClick={() => setSettingsOpen(true)}
          className="flex h-10 w-full items-center gap-2.5 rounded-[10px] px-3 text-sm text-text2 transition-colors hover:bg-bg2 hover:text-text"
        >
          <Mi n="settings" className="text-[18px]" />
          <span>Settings</span>
        </button>
      </div>

      <SettingsDialog
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        stats={stats}
        unlocked={unlocked}
        onPairAgain={onPairAgain}
      />
    </aside>
  )
}
