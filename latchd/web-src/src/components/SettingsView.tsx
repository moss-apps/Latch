import { useState, type ReactNode } from "react"
import { LegalDocTabs } from "@/components/LegalGate"
import { Mi } from "@/components/Mi"
import { StatusLine, type StatusKind } from "@/components/StatusLine"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { api, ApiError, getJSON, type LegalInfo } from "@/lib/api"
import { fmtDate } from "@/lib/format"
import { Markdown } from "@/lib/markdown"
import { ACCENTS, setAccent, setTheme, useTheme } from "@/lib/theme"
import { setShowThumbnails, useShowThumbnails } from "@/lib/display"

function SettingRow({ title, description, children }: { title: string; description?: ReactNode; children: ReactNode }) {
  return <div className="settings-row">
    <div><h3 className="text-sm font-bold">{title}</h3>{description && <p className="mt-1 max-w-[48ch] text-sm leading-relaxed text-text2">{description}</p>}</div>
    <div className="min-w-0">{children}</div>
  </div>
}

export function SettingsView({ stats, unlocked, hasLocal, onPairAgain, onUnlock }: {
  stats: { files: number; dir: string; lastBackup: string | null }
  unlocked: boolean
  hasLocal: boolean
  onPairAgain: () => void
  onUnlock: () => void
}) {
  const t = useTheme()
  const showThumbs = useShowThumbnails()
  const [verify, setVerify] = useState<{ kind: StatusKind; text: string }>({ kind: "", text: "" })
  const [exportState, setExportState] = useState<{ kind: StatusKind; text: string }>({ kind: "", text: "" })
  const [subdir, setSubdir] = useState("latch-export")
  const [legalInfo, setLegalInfo] = useState<LegalInfo | null>(null)
  const [legalDoc, setLegalDoc] = useState<string | null>(null)
  const [legalError, setLegalError] = useState("")

  async function openLegalDoc(id: string) {
    setLegalDoc(id)
    setLegalError("")
    if (legalInfo) return
    try {
      const info = await getJSON<LegalInfo>("/api/legal")
      if (!info.documents?.length) throw new Error("No legal documents returned.")
      setLegalInfo(info)
    } catch {
      setLegalError("Couldn't load this document. Check that latchd is running and try again.")
    }
  }

  async function runVerify() {
    setVerify({ kind: "busy", text: "Checking every file against its stored hash…" })
    try {
      const data = await api<{ ok: boolean; files: number; error?: string }>("/api/verify")
      setVerify(data.ok ? { kind: "ok", text: `All ${data.files} encrypted files match their hashes.` } : { kind: "err", text: `Verification failed: ${data.error || "hash mismatch"}. Back up from your phone again to replace the damaged file.` })
    } catch (err) {
      setVerify({ kind: "err", text: `Couldn't verify the backup: ${(err as Error).message}. Unlock the vault and try again.` })
    }
  }

  async function runExport() {
    const folder = subdir.trim() || "latch-export"
    setExportState({ kind: "busy", text: `Decrypting into ~/latchd-exports/${folder}…` })
    try {
      const data = await api<{ exported: number; out: string; skipped?: number }>("/api/export", { subdir: folder })
      setExportState({ kind: "ok", text: `Exported ${data.exported} files to ${data.out}${data.skipped ? ` (${data.skipped} legacy files skipped)` : ""}.` })
    } catch (err) {
      setExportState({ kind: "err", text: err instanceof ApiError && err.status === 409 ? "The vault is locked. Unlock it, then export again." : `Export failed: ${(err as Error).message}. Check the folder name and try again.` })
    }
  }

  if (legalDoc) {
    const document = legalInfo?.documents.find((d) => d.id === legalDoc)
    return <div className="utility-page max-w-[860px]">
      <Button variant="ghost" className="mb-5 h-11 -ml-3" onClick={() => setLegalDoc(null)}><Mi n="chevron_left" className="text-[20px]" />Back to Settings</Button>
      <h1 className="mb-6 text-2xl font-bold">Legal documents</h1>
      <LegalDocTabs documents={legalInfo?.documents ?? []} activeId={legalDoc} onSelect={setLegalDoc} />
      <div className="mt-6 break-words">
        {document ? <Markdown source={document.markdown} /> : legalError ? <><StatusLine kind="err" text={legalError} /><Button variant="outline" className="mt-4 h-11" onClick={() => openLegalDoc(legalDoc)}>Try again</Button></> : <p role="status" className="text-sm text-text2">Loading document…</p>}
      </div>
    </div>
  }

  return <div className="utility-page max-w-[1040px]">
    <header className="mb-8"><h1 className="text-[26px] font-bold tracking-tight">Settings</h1><p className="mt-1.5 text-sm text-text2">Manage this computer's backup and make Latch your own.</p></header>

    <section aria-labelledby="backup-settings" className="settings-section">
      <h2 id="backup-settings" className="text-lg font-bold">Backup & export</h2>
      <SettingRow title="Local backup" description={hasLocal ? `${stats.files} encrypted files · ${unlocked ? "Vault unlocked" : "Vault locked"}` : "No backup on this computer yet."}>
        <div className="text-sm text-text2"><p className="break-all">{stats.dir || "Backup location unavailable"}</p><p className="mt-1 text-xs">{stats.lastBackup ? `Last backup: ${fmtDate(stats.lastBackup)}` : "No completed backup yet"}</p></div>
      </SettingRow>
      <SettingRow title="Phone backup" description="Receive an encrypted snapshot from your phone, or restore this computer's backup to it.">
        <Button variant="outline" className="h-11 px-4" onClick={onPairAgain}><Mi n="smartphone" className="text-[18px]" />Back up from phone</Button>
      </SettingRow>
      <SettingRow title="Verify backup" description="Check that the encrypted files on disk are intact.">
        <Button variant="outline" className="h-11 px-4" disabled={!unlocked || verify.kind === "busy"} onClick={runVerify}><Mi n="verified" className="text-[18px]" />{verify.kind === "busy" ? "Verifying…" : "Verify backup"}</Button>
        <div className="mt-2 break-words"><StatusLine kind={verify.kind} text={verify.text} /></div>
      </SettingRow>
      <SettingRow title="Export decrypted files" description="Save readable copies on this computer. Decryption happens locally using your unlocked vault.">
        <form onSubmit={(e) => { e.preventDefault(); if (unlocked && exportState.kind !== "busy") runExport() }}>
          <label htmlFor="export-folder" className="mb-2 block text-sm text-text2">Export folder name</label>
          <div className="flex gap-2"><Input id="export-folder" value={subdir} spellCheck={false} autoComplete="off" disabled={!unlocked || exportState.kind === "busy"} className="h-11 min-w-0 text-foreground" onChange={(e) => setSubdir(e.target.value)} /><Button type="submit" variant="outline" className="h-11 px-4" disabled={!unlocked || exportState.kind === "busy"}>{exportState.kind === "busy" ? "Exporting…" : "Export"}</Button></div>
          <p className="mt-2 break-all text-xs leading-relaxed text-text2">Destination: <code>~/latchd-exports/{subdir.trim() || "latch-export"}</code></p>
          <div className="mt-2 break-words"><StatusLine kind={exportState.kind} text={exportState.text} /></div>
        </form>
      </SettingRow>
      {!unlocked && <p className="flex flex-wrap items-center gap-x-2 text-sm text-text2"><Mi n="lock" className="text-[16px]" />Unlock the vault to verify or export files.<button type="button" className="min-h-11 font-bold underline underline-offset-4" onClick={onUnlock}>Go to unlock</button></p>}
    </section>

    <section aria-labelledby="appearance-settings" className="settings-section">
      <h2 id="appearance-settings" className="text-lg font-bold">Appearance</h2>
      <SettingRow title="Dark mode" description="Use a darker interface on this browser."><div className="flex min-h-12 items-center px-3 sm:justify-end"><Switch className="after:-inset-y-3.5" checked={t.dark} onCheckedChange={(checked) => setTheme(checked ? "dark" : "light")} aria-label="Dark mode" /></div></SettingRow>
      <SettingRow title="Image thumbnails" description="Show image previews instead of file-type icons."><div className="flex min-h-12 items-center px-3 sm:justify-end"><Switch className="after:-inset-y-3.5" checked={showThumbs} onCheckedChange={setShowThumbnails} aria-label="Image thumbnails" /></div></SettingRow>
      <SettingRow title="Accent color" description="Used for selected views and primary controls.">
        <fieldset><legend className="mb-2 text-sm text-text2">{ACCENTS.find((a) => a[0] === t.accentId)?.[1]}</legend><div className="flex flex-wrap" >
          {ACCENTS.map((a) => <label key={a[0]} className="relative grid size-11 cursor-pointer place-items-center" title={a[1]}>
            <input type="radio" name="accent-color" value={a[0]} checked={a[0] === t.accentId} onChange={() => setAccent(a[0])} aria-label={a[1]} className="peer sr-only" />
            <span className="grid size-7 place-items-center rounded-full border border-foreground/20 peer-focus-visible:outline-2 peer-focus-visible:outline-offset-4 peer-focus-visible:outline-foreground" style={{ background: t.dark ? a[3] : a[2] }}>
              {a[0] === t.accentId && <span className="grid size-4 place-items-center rounded-full bg-white text-[#121212]"><Mi n="check_circle" className="text-[16px]" /></span>}
            </span>
          </label>)}
        </div></fieldset>
      </SettingRow>
    </section>

    <section aria-labelledby="legal-settings" className="settings-section">
      <h2 id="legal-settings" className="text-lg font-bold">Legal</h2>
      <p className="mt-2 text-sm text-text2">Accepted before first use. Updated versions ask for your agreement again.</p>
      <div className="mt-4 divide-y divide-divider">
        {[["eula", "License Agreement (EULA)"], ["terms", "Terms and Conditions"], ["privacy", "Privacy Policy"]].map(([id, label]) => <button key={id} type="button" onClick={() => openLegalDoc(id)} className="flex min-h-12 w-full items-center justify-between gap-3 py-3 text-left text-sm text-text2 hover:text-foreground">{label}<Mi n="chevron_right" className="text-[20px]" /></button>)}
      </div>
    </section>
  </div>
}
