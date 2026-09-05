import { useMemo, useState } from "react"
import { Mi } from "@/components/Mi"
import { StatusLine, type StatusKind } from "@/components/StatusLine"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Separator } from "@/components/ui/separator"
import { Switch } from "@/components/ui/switch"
import type { FileEntry } from "@/lib/api"
import { api, ApiError } from "@/lib/api"
import { fmtDate } from "@/lib/format"
import { ACCENTS, setAccent, setTheme, useTheme } from "@/lib/theme"
import { VIEWS, viewFilter } from "@/lib/views"

interface SidebarProps {
  files: FileEntry[]
  activeView: string
  onViewChange: (view: string) => void
  stats: { files: number; dir: string; lastBackup: string | null }
  unlocked: boolean
  onPairAgain: () => void
}

function SectionTitle({ children }: { children: string }) {
  return (
    <h3 className="px-1 pb-1.5 text-[11px] font-bold tracking-[0.07em] text-text3 uppercase">
      {children}
    </h3>
  )
}

export function Sidebar({
  files,
  activeView,
  onViewChange,
  stats,
  unlocked,
  onPairAgain,
}: SidebarProps) {
  const t = useTheme()
  const counts = useMemo(() => {
    const c: Record<string, number> = { all: files.length }
    for (const v of VIEWS) {
      if (v.id !== "all") c[v.id] = files.filter((f) => viewFilter(v.id, f)).length
    }
    return c
  }, [files])

  const [verify, setVerify] = useState<{ kind: StatusKind; text: string }>({
    kind: "",
    text: "",
  })
  const [exportState, setExportState] = useState<{ kind: StatusKind; text: string }>({
    kind: "",
    text: "",
  })
  const [subdir, setSubdir] = useState("latch-export")

  async function runVerify(btn: HTMLButtonElement) {
    btn.disabled = true
    setVerify({ kind: "busy", text: "Verifying every hash on disk…" })
    try {
      const data = await api<{ ok: boolean; files: number; error?: string }>("/api/verify")
      setVerify(
        data.ok
          ? { kind: "ok", text: `Intact: all ${data.files} blobs match their hashes.` }
          : {
              kind: "err",
              text: `Verify failed: ${data.error || "unknown"}. Pair the phone again to re-send the corrupt blob.`,
            },
      )
    } catch (err) {
      setVerify({ kind: "err", text: (err as Error).message || "Verify failed." })
    } finally {
      btn.disabled = false
    }
  }

  async function runExport(btn: HTMLButtonElement) {
    const folder = subdir.trim() || "latch-export"
    btn.disabled = true
    setExportState({ kind: "busy", text: `Decrypting into ~/latchd-exports/${folder}…` })
    try {
      const data = await api<{ exported: number; out: string; skipped?: number }>(
        "/api/export",
        { subdir: folder },
      )
      setExportState({
        kind: "ok",
        text: `Exported ${data.exported} files to ${data.out}${data.skipped ? ` (${data.skipped} legacy skipped)` : ""}.`,
      })
    } catch (err) {
      setExportState({
        kind: "err",
        text:
          err instanceof ApiError && err.status === 409
            ? "Locked. Unlock first, then export."
            : `Export failed: ${(err as Error).message || err}`,
      })
    } finally {
      btn.disabled = false
    }
  }

  return (
    <aside className="flex shrink-0 flex-col gap-6 overflow-y-auto border-b border-divider p-3 md:w-[264px] md:border-b-0 md:border-r md:p-4">
      <nav className="flex gap-1 overflow-x-auto md:flex-col" aria-label="Views">
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

      <div className="hidden md:block">
        <SectionTitle>Backup</SectionTitle>
        <div className="space-y-1">
          <div className="flex items-center justify-between gap-3 py-1 text-sm">
            <span className="flex shrink-0 items-center gap-2 text-text3">
              <Mi n="folder" className="text-[16px]" />
              Folder
            </span>
            <span className="truncate text-right" title={stats.dir}>
              {stats.dir || "—"}
            </span>
          </div>
          <div className="flex items-center justify-between gap-3 py-1 text-sm">
            <span className="flex shrink-0 items-center gap-2 text-text3">
              <Mi n="schedule" className="text-[16px]" />
              Last backup
            </span>
            <span className="truncate text-right">
              {stats.lastBackup ? fmtDate(stats.lastBackup) : "—"}
            </span>
          </div>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          <Button size="sm" className="h-8" onClick={onPairAgain}>
            <Mi n="smartphone" className="text-[16px]" />
            Back up from phone
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-8"
            disabled={!unlocked}
            onClick={(e) => runVerify(e.currentTarget)}
          >
            <Mi n="verified" className="text-[16px]" />
            Verify
          </Button>
        </div>
        <div className="mt-2">
          <StatusLine kind={verify.kind} text={verify.text} />
        </div>
      </div>

      <div className="hidden md:block">
        <SectionTitle>Export decrypted</SectionTitle>
        <p className="px-1 pb-2 text-xs leading-relaxed text-text3">
          Writes readable files to <code>~/latchd-exports/&lt;folder&gt;</code>. Decryption
          happens locally with the key already in latchd's memory.
        </p>
        <div className="flex gap-2">
          <Input
            value={subdir}
            spellCheck={false}
            autoComplete="off"
            placeholder="latch-export"
            className="h-9"
            disabled={!unlocked}
            onChange={(e) => setSubdir(e.target.value)}
          />
          <Button
            size="sm"
            className="h-9 shrink-0"
            disabled={!unlocked}
            onClick={(e) => runExport(e.currentTarget)}
          >
            <Mi n="save_alt" className="text-[16px]" />
            Export
          </Button>
        </div>
        <div className="mt-2">
          <StatusLine kind={exportState.kind} text={exportState.text} />
        </div>
      </div>

      <div className="hidden md:block">
        <Separator className="mb-4" />
        <SectionTitle>Appearance</SectionTitle>
        <div className="flex items-center justify-between gap-3 px-1 py-1.5">
          <span className="text-sm text-text2">Dark mode</span>
          <Switch
            checked={t.dark}
            onCheckedChange={(checked) => setTheme(checked ? "dark" : "light")}
            aria-label="Dark mode"
          />
        </div>
        <div className="mt-2 flex flex-wrap gap-2.5 px-1 pb-2" role="radiogroup" aria-label="Accent color">
          {ACCENTS.map((a) => {
            const selected = a[0] === t.accentId
            return (
              <button
                key={a[0]}
                type="button"
                title={a[1]}
                role="radio"
                aria-checked={selected}
                aria-label={a[1]}
                className="size-9 rounded-full transition-transform hover:scale-105"
                style={{
                  background: t.dark ? a[3] : a[2],
                  boxShadow: selected ? "inset 0 0 0 2.5px var(--text)" : undefined,
                }}
                onClick={() => setAccent(a[0])}
              />
            )
          })}
        </div>
      </div>
    </aside>
  )
}
