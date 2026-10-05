import { useMemo } from "react"
import { Dialog as Drawer } from "radix-ui"
import { Mi } from "@/components/Mi"
import type { FileEntry } from "@/lib/api"
import { VIEWS, viewFilter } from "@/lib/views"

interface SidebarProps {
  files: FileEntry[]
  activeView: string
  onViewChange: (view: string) => void
  unlocked: boolean
  onNavigate: (screen: "files" | "settings" | "pair") => void
  navOpen: boolean
  onNavClose: () => void
}

export function Sidebar({ files, activeView, onViewChange, unlocked, onNavigate, navOpen, onNavClose }: SidebarProps) {
  const counts = useMemo(() => Object.fromEntries(VIEWS.map((v) => [v.id, files.filter((f) => viewFilter(v.id, f)).length])), [files])

  const navigation = <nav aria-label="Backup navigation" className="flex flex-col gap-1 p-3">
    {VIEWS.map((v) => <button key={v.id} type="button" onClick={() => onViewChange(v.id)} aria-current={activeView === v.id ? "page" : undefined} className="nav-row">
      <Mi n={v.icon} className="text-[20px]" />
      <span className="flex-1 text-left">{v.label}</span>
      {unlocked && counts[v.id] > 0 && <span className="text-xs tabular-nums opacity-80">{counts[v.id]}</span>}
    </button>)}
    <div className="mx-3 my-3 border-t border-divider" />
    <button type="button" className="nav-row" aria-current={activeView === "pair" ? "page" : undefined} onClick={() => onNavigate("pair")}>
      <Mi n="smartphone" className="text-[20px]" />Phone backup
    </button>
    <button type="button" className="nav-row" aria-current={activeView === "settings" ? "page" : undefined} onClick={() => onNavigate("settings")}>
      <Mi n="settings" className="text-[20px]" />Settings
    </button>
  </nav>

  return <>
    <aside className="hidden w-[232px] shrink-0 flex-col overflow-y-auto md:flex">
      {navigation}
      <p className="mt-auto flex items-center gap-2 px-6 py-6 text-xs text-text2"><Mi n="lock" className="text-[16px]" />Stored on this computer</p>
    </aside>
    <Drawer.Root open={navOpen} onOpenChange={(open) => { if (!open) onNavClose() }}>
      <Drawer.Portal>
        <Drawer.Overlay className="fixed inset-0 z-40 bg-black/40" />
        <Drawer.Content id="mobile-navigation" aria-describedby={undefined} onCloseAutoFocus={(e) => { e.preventDefault(); document.getElementById("navigation-toggle")?.focus() }} className="navigation-drawer fixed inset-y-0 left-0 z-50 w-[min(300px,calc(100vw-40px))] overflow-y-auto bg-bg2">
          <div className="flex h-16 items-center justify-between px-6">
            <Drawer.Title className="text-lg font-bold">Latch</Drawer.Title>
            <Drawer.Close aria-label="Close navigation" className="grid size-11 place-items-center rounded-lg text-text2 hover:bg-surface"><Mi n="close" className="text-[22px]" /></Drawer.Close>
          </div>
          {navigation}
          <p className="px-6 py-6 text-xs text-text2">Stored on this computer</p>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  </>
}
