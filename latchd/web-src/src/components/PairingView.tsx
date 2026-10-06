import { useEffect, useRef, useState } from "react"
import { Mi } from "@/components/Mi"
import { Button } from "@/components/ui/button"
import { api, getJSON, type PairInfo } from "@/lib/api"
import { fmtCode, fmtSize } from "@/lib/format"
import type { GlyphName } from "@/lib/glyphs"

const POLL_MS = 1500
type SessionMode = "push" | "restore"
type LiveKind = "waiting" | "busy" | "ok" | "err"
interface QrMaker {
  addData(data: string): void
  make(): void
  getModuleCount(): number
  isDark(row: number, col: number): boolean
}
declare global {
  interface Window { qrcode?: (typeNumber: number, level: string) => QrMaker }
}

function drawQR(canvas: HTMLCanvasElement, text: string) {
  const qr = window.qrcode?.(0, "M")
  if (!qr) throw new Error("QR generator unavailable")
  qr.addData(text)
  qr.make()
  const count = qr.getModuleCount()
  const quiet = 4
  const px = Math.round(200 * (window.devicePixelRatio || 1))
  canvas.width = px
  canvas.height = px
  const ctx = canvas.getContext("2d")!
  ctx.fillStyle = "#FFFFFF"
  ctx.fillRect(0, 0, px, px)
  const cell = px / (count + quiet * 2)
  ctx.fillStyle = "#121212"
  for (let r = 0; r < count; r++) {
    for (let c = 0; c < count; c++) {
      if (qr.isDark(r, c)) ctx.fillRect(Math.floor((quiet + c) * cell), Math.floor((quiet + r) * cell), Math.ceil(cell), Math.ceil(cell))
    }
  }
}

async function copyText(text: string) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return true
    }
  } catch { /* try the browser fallback */ }
  const ta = document.createElement("textarea")
  const focused = document.activeElement as HTMLElement | null
  ta.value = text
  ta.style.position = "fixed"
  ta.style.opacity = "0"
  document.body.appendChild(ta)
  ta.select()
  let copied = false
  try { copied = document.execCommand("copy") } catch { /* show manual-copy feedback */ }
  ta.remove()
  focused?.focus()
  return copied
}

function CopyButton({ value, label, disabled, icon = "link" }: { value: string; label: string; disabled: boolean; icon?: GlyphName }) {
  const [feedback, setFeedback] = useState("")
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current) }, [])
  return <Button variant="outline" className="h-11 px-3" disabled={disabled} aria-label={label} onClick={async () => {
    if (!value) return
    setFeedback(await copyText(value) ? "Copied" : "Select and copy manually")
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => setFeedback(""), 2000)
  }}><Mi n={icon} className="text-[16px]" /><span role="status">{feedback || label}</span></Button>
}

export function PairingView({ hasLocal, unlocked, visible, onEnterMain, backLabel }: {
  hasLocal: boolean
  unlocked: boolean
  visible: boolean
  onEnterMain: (unlocked: boolean, note?: string) => void
  backLabel: string
}) {
  const [session, setSession] = useState<PairInfo | null>(null)
  const [mode, setMode] = useState<SessionMode>("push")
  const [live, setLive] = useState<{ kind: LiveKind; text: string }>({ kind: "waiting", text: "Opening pairing session…" })
  const [changing, setChanging] = useState(false)
  const [qrFailed, setQrFailed] = useState(false)
  const [usbBusy, setUsbBusy] = useState(false)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const completeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const generation = useRef(0)
  const mounted = useRef(true)
  const transitioning = useRef(false)
  const done = useRef(false)
  const modeRef = useRef<SessionMode>("push")
  const callbacks = useRef({ unlocked, onEnterMain })
  useEffect(() => { callbacks.current = { unlocked, onEnterMain } }, [unlocked, onEnterMain])

  function stopPoll() {
    if (pollRef.current) clearInterval(pollRef.current)
    pollRef.current = null
  }

  function clearCompletion() {
    if (completeTimerRef.current) clearTimeout(completeTimerRef.current)
    completeTimerRef.current = null
  }

  function ensurePoll() {
    if (pollRef.current) return
    pollRef.current = setInterval(() => {
      const current = generation.current
      getJSON<PairInfo>("/api/pair/status").then((d) => {
        if (mounted.current && current === generation.current) applySession(d)
      }).catch(() => {
        if (mounted.current && current === generation.current) setLive({ kind: "err", text: "Connection lost. Check that latchd is running; retrying automatically…" })
      })
    }, POLL_MS)
  }

  function applySession(d: PairInfo) {
    setSession(d)
    const nextMode = d.mode === "restore" ? "restore" : "push"
    setMode(nextMode)
    modeRef.current = nextMode
    if (d.active) {
      done.current = false
      if (d.state === "receiving") {
        const files = nextMode === "restore" ? d.served : d.files
        const bytes = nextMode === "restore" ? d.servedBytes : d.bytes
        setLive({ kind: "busy", text: `${nextMode === "restore" ? "Sending to your phone" : "Receiving backup"}: ${files} ${files === 1 ? "file" : "files"} · ${fmtSize(bytes)}` })
      } else if (d.state === "verifying") {
        setLive({ kind: "busy", text: "Verifying the received backup…" })
      } else {
        setLive({ kind: "waiting", text: "Waiting for your phone" })
      }
      ensurePoll()
      return
    }
    stopPoll()
    if (d.state === "complete" && nextMode === "push") {
      setLive({ kind: "ok", text: `Backup received: ${d.files} ${d.files === 1 ? "file" : "files"} · ${fmtSize(d.bytes)}` })
      if (!done.current) {
        done.current = true
        completeTimerRef.current = setTimeout(() => callbacks.current.onEnterMain(callbacks.current.unlocked, "Backup received. Enter your vault password to browse and export it."), 1600)
      }
    } else {
      setLive({ kind: "err", text: d.lastError ? `Session closed: ${d.lastError}. Create a new code to try again.` : "Session closed. Codes expire after five idle minutes. Create a new code and scan again." })
    }
  }

  async function startSession(nextMode: SessionMode, replace: boolean) {
    if (transitioning.current) return
    transitioning.current = true
    setChanging(true)
    const current = ++generation.current
    stopPoll()
    clearCompletion()
    done.current = false
    setSession(null)
    setMode(nextMode)
    modeRef.current = nextMode
    setLive({ kind: "waiting", text: nextMode === "restore" ? "Opening restore session…" : "Opening pairing session…" })
    try {
      if (replace) await api("/api/pair/stop")
      const data = await api<PairInfo>("/api/pair/start", { mode: nextMode })
      if (mounted.current && current === generation.current) applySession(data)
    } catch (err) {
      if (mounted.current && current === generation.current) setLive({ kind: "err", text: `Couldn't open the session: ${(err as Error).message}. Check that latchd is running and try a new code.` })
    } finally {
      transitioning.current = false
      if (mounted.current) setChanging(false)
    }
  }

  useEffect(() => {
    mounted.current = true
    const invalidateRequests = () => { generation.current++ }
    return () => { mounted.current = false; invalidateRequests(); stopPoll(); clearCompletion() }
  }, [])

  useEffect(() => {
    if (!visible) return
    const current = generation.current
    getJSON<PairInfo>("/api/pair/status").then((d) => {
      if (!mounted.current || current !== generation.current || transitioning.current) return
      if (d.active) applySession(d)
      else startSession(modeRef.current, false)
    }).catch(() => {
      if (mounted.current && current === generation.current) startSession(modeRef.current, false)
    })
    // Re-enter adopts the current session; background transfers keep polling.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible])

  const qrUrl = session?.active ? session.url : ""
  useEffect(() => {
    setQrFailed(false)
    if (!qrUrl || !canvasRef.current) return
    try { drawQR(canvasRef.current, qrUrl) } catch { setQrFailed(true) }
  }, [qrUrl])

  async function cancelSession() {
    if (transitioning.current) return
    transitioning.current = true
    setChanging(true)
    ++generation.current
    stopPoll()
    clearCompletion()
    try {
      await api("/api/pair/stop")
      if (!mounted.current) return
      setSession(null)
      setLive({ kind: "waiting", text: "Session cancelled. Create a new code when you're ready." })
      callbacks.current.onEnterMain(callbacks.current.unlocked)
    } catch (err) {
      if (mounted.current) {
        setLive({ kind: "err", text: `Couldn't cancel the session: ${(err as Error).message}. Try again.` })
        ensurePoll()
      }
    } finally {
      transitioning.current = false
      if (mounted.current) setChanging(false)
    }
  }

  async function allowUsb(allow: boolean) {
    setUsbBusy(true)
    const current = generation.current
    try {
      const data = await api<PairInfo>("/api/pair/allow", { allow })
      if (mounted.current && current === generation.current) applySession(data)
    } catch (err) {
      if (mounted.current && current === generation.current) setLive({ kind: "err", text: `Couldn't ${allow ? "approve" : "deny"} the USB connection: ${(err as Error).message}. Try again.` })
    } finally {
      if (mounted.current) setUsbBusy(false)
    }
  }

  const restore = mode === "restore"
  const active = !!session?.active && !changing
  const busy = live.kind === "busy"
  const port = session?.port
  const command = port ? `adb reverse tcp:${port} tcp:${port}` : "adb reverse tcp:<port> tcp:<port>"
  const steps = [<>Open <strong>Latch</strong> on your phone.</>, <>Go to <strong>Settings → Storage → Desktop Backup{restore ? " → Restore from this computer" : ""}</strong>.</>, <><strong>Scan the QR code.</strong> Keep both devices on the same network.</>]

  return <div className="utility-page max-w-[1040px]">
    <Button variant="ghost" className="mb-4 -ml-3 h-11" onClick={() => callbacks.current.onEnterMain(callbacks.current.unlocked)}><Mi n="chevron_left" className="text-[20px]" />{backLabel}</Button>
    <header><h1 className="text-[26px] font-bold tracking-tight">Phone backup</h1><p className="mt-1.5 max-w-[65ch] text-sm leading-relaxed text-text2">{restore ? "Restore the encrypted snapshot on this computer to your phone." : "Keep an encrypted snapshot of your phone vault on this computer."}</p></header>

    <div role="tablist" aria-label="Session mode" className="mt-6 flex border-b border-divider">
      {([["push", "Receive backup"], ["restore", "Restore to phone"]] as const).map(([value, label]) => <button key={value} id={`pair-tab-${value}`} type="button" role="tab" aria-selected={mode === value} aria-controls="pair-session" tabIndex={mode === value ? 0 : -1} disabled={changing || busy || (value === "restore" && !hasLocal)} onClick={() => { if (mode !== value) startSession(value, true) }} onKeyDown={(e) => {
        if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) {
          e.preventDefault()
          const next = e.key === "Home" ? "push" : e.key === "End" ? "restore" : mode === "push" ? "restore" : "push"
          if (next === "restore" && !hasLocal) return
          document.getElementById(`pair-tab-${next}`)?.focus()
          if (mode !== next) startSession(next, true)
        }
      }} className={`relative min-h-12 flex-1 px-2 text-sm transition-colors disabled:opacity-50 sm:flex-none sm:px-5 ${mode === value ? "font-bold text-foreground after:absolute after:inset-x-3 after:bottom-0 after:h-0.5 after:bg-foreground" : "text-text2 hover:bg-bg2"}`}>{label}</button>)}
    </div>
    {!hasLocal && <p className="mt-3 text-xs text-text2">Receive a backup before restoring to your phone.</p>}

    <div id="pair-session" role="tabpanel" aria-labelledby={`pair-tab-${mode}`} className="mt-7 grid gap-8 lg:grid-cols-[280px_minmax(0,1fr)]">
      <div className="min-w-0">
        <h2 className="mb-4 text-base font-bold">Scan with Latch</h2>
        <div className="relative mx-auto grid size-[232px] place-items-center rounded-xl border border-divider bg-white lg:mx-0">
          <canvas ref={canvasRef} width={200} height={200} className="size-[200px]" role="img" aria-label="Pairing QR code, scan with the Latch phone app" />
          {(!active || busy || qrFailed) && <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-xl bg-bg2 p-5 text-center">
            <Mi n={busy ? "sync_alt" : live.kind === "ok" ? "check_circle" : live.kind === "err" ? "error_outline" : qrFailed ? "smartphone" : "schedule"} className={`text-[32px] text-text2 ${busy ? "motion-safe:animate-pulse" : ""}`} />
            <span className="text-sm text-text2">{busy ? session?.state === "verifying" ? "Verifying backup…" : restore ? "Sending backup…" : "Receiving backup…" : qrFailed ? "Use manual connection below" : changing || !session && live.kind === "waiting" ? "Preparing connection" : live.kind === "ok" ? "Backup received" : "No active QR code"}</span>
          </div>}
        </div>
        <div className="mt-4 flex items-start gap-2.5 text-sm leading-relaxed text-text2" role="status" aria-live="polite">
          <span className={`mt-1.5 size-2 shrink-0 rounded-full ${live.kind === "busy" ? "bg-brand motion-safe:animate-pulse" : live.kind === "ok" ? "bg-success" : live.kind === "err" ? "bg-error" : "bg-text3"}`} />{live.text}
        </div>
        {qrFailed && <p className="mt-3 text-sm text-text2">Couldn't draw the QR code. Expand “Connect manually” to use the address and pairing code.</p>}
        <div className="mt-4 flex flex-wrap gap-2"><CopyButton value={session?.url || ""} label="Copy link" disabled={!active || busy} /><Button variant="ghost" className="h-11 px-3" onClick={() => startSession(mode, true)} disabled={changing || busy}><Mi n="sync_alt" className="text-[18px]" />{changing ? "Opening…" : "New code"}</Button></div>
      </div>

      <div className="min-w-0">
        <h2 className="text-base font-bold">On your phone</h2>
        <ol className="mt-5 space-y-5">{steps.map((step, i) => <li key={i} className="flex gap-3"><span className="grid size-6 shrink-0 place-items-center rounded-full bg-bg2 text-xs font-bold text-text2">{i + 1}</span><span className="text-sm leading-relaxed text-text2">{step}</span></li>)}</ol>

        {session?.usbPending && active && <div role="alert" className="mt-6 rounded-xl bg-bg2 p-4">
          <h3 className="text-sm font-bold">{session.usbPending.device} wants to connect over USB</h3><p className="mt-2 text-sm leading-relaxed text-text2">Allow this if you just tapped <strong>Connect via USB</strong> on your phone.</p><div className="mt-3 flex gap-2"><Button className="h-11 px-4" disabled={usbBusy} onClick={() => allowUsb(true)}>Allow once</Button><Button variant="outline" className="h-11 px-4" disabled={usbBusy} onClick={() => allowUsb(false)}>Deny</Button></div>
        </div>}
        {session?.usbApproved && !session.usbPending && active && <p className="mt-5 flex items-center gap-2 text-sm text-text2"><Mi n="check_circle" className="text-[18px]" />USB phone approved. Continue on your phone.</p>}

        <details className="connection-details mt-6 border-t border-divider">
          <summary><span>Connect manually</span><Mi n="chevron_right" className="disclosure-chevron text-[20px]" /></summary>
          <div className="space-y-4 pb-5 text-sm">
            <p className="leading-relaxed text-text2">Enter these in Desktop Backup on your phone. Keep the pairing code private.</p>
            <div><h3 className="mb-2 font-bold">Address</h3><p className="mb-2 break-all rounded-lg bg-bg2 p-3 font-mono text-[13px] select-all">{active ? `${session.host}:${session.port}` : "No active session"}</p><CopyButton value={session ? `${session.host}:${session.port}` : ""} label="Copy address" disabled={!active || busy} /></div>
            <div><h3 className="mb-2 font-bold">Pairing code</h3><p className="mb-2 break-words rounded-lg bg-bg2 p-3 font-mono text-[13px] leading-relaxed select-all">{active ? fmtCode(session.token) : "Create a new code to connect"}</p><CopyButton value={session?.token || ""} label="Copy code" disabled={!active || busy} /></div>
          </div>
        </details>
        <details className="connection-details border-y border-divider">
          <summary><span>Use a USB cable</span><Mi n="chevron_right" className="disclosure-chevron text-[20px]" /></summary>
          <div className="space-y-3 pb-5 text-sm leading-relaxed text-text2">
            <p>Connect your phone with USB debugging enabled, then run this on your computer:</p>
            <code className="block break-all rounded-lg bg-bg2 p-3 font-mono text-[13px] text-foreground select-all">{command}</code>
            <CopyButton value={command} label="Copy command" disabled={!active || busy} />
            <p>On your phone, tap <strong>Connect via USB</strong>. Then choose <strong>Allow once</strong> here.</p>
            <p>If the cable disconnects, reconnect it, run the command again, and tap <strong>Connect via USB</strong>. For manual USB connection, use <code className="break-all">{port ? `127.0.0.1:${port}` : "127.0.0.1:<port>"}</code> with the pairing code above.</p>
          </div>
        </details>
      </div>
    </div>

    <footer className="mt-8 border-t border-divider pt-5">
      <p role="note" className="flex max-w-[75ch] items-start gap-2.5 text-xs leading-relaxed text-text2"><Mi n="warning" className="mt-0.5 shrink-0 text-[16px]" /><span>This session uses plain HTTP on your local network. Files stay encrypted and the pairing token gates access. Only connect on networks you trust. The session closes after five idle minutes{restore ? "." : " or when the backup finishes."}</span></p>
      <Button variant="ghost" className="mt-3 -ml-3 h-11 px-3 text-text2" disabled={!active || changing} onClick={cancelSession}>Cancel session</Button>
    </footer>
  </div>
}
