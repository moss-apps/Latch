import { useEffect, useRef, useState } from "react"
import { Logomark } from "@/components/Logomark"
import { Mi } from "@/components/Mi"
import { Button } from "@/components/ui/button"
import { api, getJSON, type PairInfo } from "@/lib/api"
import { fmtCode, fmtSize } from "@/lib/format"
import type { GlyphName } from "@/lib/glyphs"

const POLL_MS = 1500

interface QrMaker {
  addData(data: string): void
  make(): void
  getModuleCount(): number
  isDark(row: number, col: number): boolean
}

declare global {
  interface Window {
    qrcode?: (typeNumber: number, level: string) => QrMaker
  }
}

type LiveKind = "waiting" | "busy" | "ok" | "err"
type Veil = { icon: GlyphName; text: string } | null

const STEPS = [
  <>
    Open <strong>Latch</strong> on your phone.
  </>,
  <>
    Go to <strong>Settings&nbsp;→&nbsp;Storage&nbsp;→&nbsp;Desktop Backup</strong>.
  </>,
  <>
    <strong>Scan this code</strong>, or type the address and pairing code by hand.
  </>,
]

function drawQR(canvas: HTMLCanvasElement, text: string): boolean {
  try {
    const qr = window.qrcode?.(0, "M")
    if (!qr) return false
    qr.addData(text)
    qr.make()
    const count = qr.getModuleCount()
    const quiet = 4
    const dpr = window.devicePixelRatio || 1
    const px = Math.round(200 * dpr)
    canvas.width = px
    canvas.height = px
    canvas.style.width = "200px"
    canvas.style.height = "200px"
    const ctx = canvas.getContext("2d")!
    ctx.fillStyle = "#FFFFFF"
    ctx.fillRect(0, 0, px, px)
    const cell = px / (count + quiet * 2)
    ctx.fillStyle = "#121212"
    for (let r = 0; r < count; r++) {
      for (let c = 0; c < count; c++) {
        if (qr.isDark(r, c)) {
          ctx.fillRect(
            Math.floor((quiet + c) * cell),
            Math.floor((quiet + r) * cell),
            Math.ceil(cell),
            Math.ceil(cell),
          )
        }
      }
    }
    return true
  } catch {
    return false
  }
}

function copyText(text: string, onCopied: () => void) {
  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(text).then(onCopied, () => fallbackCopy(text, onCopied))
  } else {
    fallbackCopy(text, onCopied)
  }
}

function fallbackCopy(text: string, onCopied: () => void) {
  const ta = document.createElement("textarea")
  ta.value = text
  ta.style.position = "fixed"
  ta.style.opacity = "0"
  document.body.appendChild(ta)
  ta.select()
  try {
    document.execCommand("copy")
    onCopied()
  } catch {
    /* clipboard unavailable */
  }
  document.body.removeChild(ta)
}

function CopyButton({
  getValue,
  icon,
  label,
  disabled,
}: {
  getValue: () => string | Promise<string>
  icon: GlyphName
  label: string
  disabled: boolean
}) {
  const [copied, setCopied] = useState(false)
  return (
    <Button
      variant="outline"
      size="sm"
      className="h-8"
      disabled={disabled}
      onClick={() => {
        Promise.resolve(getValue()).then((value) => {
          if (!value) return
          copyText(value, () => {
            setCopied(true)
            setTimeout(() => setCopied(false), 1300)
          })
        })
      }}
    >
      <Mi n={icon} className="text-[16px]" />
      {copied ? "Copied" : label}
    </Button>
  )
}

export function PairingView({
  hasLocal,
  unlocked,
  onEnterMain,
}: {
  hasLocal: boolean
  unlocked: boolean
  onEnterMain: (unlocked: boolean, note?: string) => void
}) {
  const [creds, setCreds] = useState<{ host: string; token: string; url: string } | null>(null)
  const [veil, setVeil] = useState<Veil>(null)
  const [live, setLive] = useState<{ kind: LiveKind; text: string }>({
    kind: "waiting",
    text: "Opening pairing session…",
  })
  const [chipsEnabled, setChipsEnabled] = useState(false)
  const [cancelDisabled, setCancelDisabled] = useState(false)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const completeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const startedRef = useRef(false)
  const doneRef = useRef(false)
  const hasLocalRef = useRef(hasLocal)
  const unlockedRef = useRef(unlocked)
  hasLocalRef.current = hasLocal
  unlockedRef.current = unlocked

  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
      if (completeTimerRef.current) clearTimeout(completeTimerRef.current)
    }
  }, [])

  function stopPoll() {
    if (pollRef.current) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
  }

  function ensurePoll() {
    if (pollRef.current) return
    pollRef.current = setInterval(() => {
      getJSON<PairInfo>("/api/pair/status")
        .then(pairApply)
        .catch(() => {
          /* transient */
        })
    }, POLL_MS)
  }

  function pairApply(d: PairInfo) {
    if (d.active) {
      startedRef.current = true
      setChipsEnabled(true)
      setCreds({ host: `${d.host}:${d.port}`, token: fmtCode(d.token), url: d.url })
      const got = `${d.files} ${d.files === 1 ? "file" : "files"} · ${fmtSize(d.bytes)}`
      if (d.state === "receiving") {
        setLive({ kind: "busy", text: `Receiving: ${got}` })
        setVeil({ icon: "sync_alt", text: "Receiving…" })
      } else if (d.state === "verifying") {
        setLive({ kind: "busy", text: "Verifying the received backup…" })
        setVeil({ icon: "verified", text: "Verifying…" })
      } else {
        setLive({
          kind: "waiting",
          text: "Waiting for your phone. Scan the code in the Latch app.",
        })
        setVeil(null)
      }
      ensurePoll()
      return
    }

    stopPoll()
    if (d.state === "complete" && !doneRef.current) {
      doneRef.current = true
      setChipsEnabled(false)
      setVeil({ icon: "check_circle", text: "Backup received" })
      setLive({
        kind: "ok",
        text: `Backup received: ${d.files} ${d.files === 1 ? "file" : "files"} · ${fmtSize(d.bytes)}.`,
      })
      completeTimerRef.current = setTimeout(() => {
        onEnterMain(
          unlockedRef.current,
          "Backup received. Enter your vault password to browse and export it.",
        )
      }, 1600)
      return
    }
    if (d.state === "error") {
      setChipsEnabled(true)
      setCancelDisabled(true)
      setVeil({ icon: "error_outline", text: "Failed" })
      setLive({
        kind: "err",
        text: `Pairing failed: ${
          d.lastError ||
          "the phone's push didn't verify. Nothing was changed; start a new code and scan again."
        }`,
      })
      return
    }
    if (startedRef.current) {
      setChipsEnabled(true)
      setCancelDisabled(true)
      setVeil(null)
      setLive({
        kind: "err",
        text: d.lastError
          ? `Pairing closed: ${d.lastError}`
          : "Pairing closed. Codes expire after five idle minutes; start a new code and scan again.",
      })
    }
  }

  function startPairing() {
    startedRef.current = false
    doneRef.current = false
    setCancelDisabled(false)
    setLive({ kind: "waiting", text: "Opening pairing session…" })
    setVeil(null)
    setChipsEnabled(false)
    api<PairInfo>("/api/pair/start")
      .then(pairApply)
      .catch((err: Error) => {
        setVeil({ icon: "error_outline", text: "Failed" })
        setLive({
          kind: "err",
          text: `Couldn't open the pairing session: ${
            err.message || "is latchd healthy?"
          } Try again.`,
        })
        setChipsEnabled(true)
        setCancelDisabled(true)
      })
  }

  useEffect(() => {
    startPairing()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (creds && canvasRef.current) {
      if (!drawQR(canvasRef.current, creds.url)) {
        setLive({
          kind: "err",
          text: "Couldn't render the QR code. Pair by typing the address and code instead.",
        })
      }
    }
  }, [creds])

  function cancelPairing() {
    setCancelDisabled(true)
    api("/api/pair/stop")
      .then(() => getJSON<PairInfo>("/api/pair/status"))
      .then((d) => {
        if (hasLocalRef.current) {
          onEnterMain(unlockedRef.current)
        } else {
          pairApply(d)
        }
      })
      .catch(() => {
        /* keep card as-is */
      })
  }

  function newCode() {
    api("/api/pair/stop").catch(() => {
      /* already gone */
    })
    startPairing()
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto grid w-full max-w-[1100px] gap-14 px-6 py-10 lg:grid-cols-[minmax(0,1fr)_380px] lg:py-16">
        <div className="flex flex-col gap-6">
          <Logomark className="h-16 text-logo" />
          <div>
            <h1 className="text-4xl font-bold tracking-tight">Pair your phone</h1>
            <p className="mt-3 max-w-md text-lg leading-relaxed text-text2">
              This screen creates the pairing credentials. Your phone pushes the encrypted
              backup here; the vault itself never leaves either device unlocked.
            </p>
          </div>
          <ol className="flex max-w-md flex-col gap-3.5">
            {STEPS.map((s, i) => (
              <li key={i} className="flex items-start gap-3">
                <span className="grid size-6 shrink-0 place-items-center rounded-full bg-brand/10 text-xs font-bold text-brand">
                  {i + 1}
                </span>
                <span className="text-text2">{s}</span>
              </li>
            ))}
          </ol>
          <div
            className="flex max-w-md gap-3 rounded-xl bg-error/10 p-4"
            role="note"
          >
            <Mi n="warning" className="mt-0.5 shrink-0 text-[18px] text-error" />
            <p className="text-sm leading-relaxed text-text2">
              Pairing opens latchd to your local network over plain HTTP. The token only
              admits your phone, files arrive already encrypted, and the session closes
              itself after five idle minutes. Pair on networks you trust.
            </p>
          </div>
        </div>

        <div className="h-fit w-full rounded-2xl border border-divider bg-card p-6 shadow-lg shadow-black/5">
          <div className="relative">
            <div className="grid place-items-center rounded-xl bg-white p-4">
              <canvas ref={canvasRef} width={200} height={200} role="img"
                aria-label="Pairing QR code, scan it with the Latch phone app" />
            </div>
            {veil && (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 rounded-xl bg-background/85 px-4 text-center backdrop-blur-sm">
                <Mi n={veil.icon} className="text-[32px] text-text2" />
                <span className="text-sm text-text2">{veil.text}</span>
              </div>
            )}
          </div>

          <div className="mt-5 space-y-2.5">
            <div className="flex items-center justify-between gap-3">
              <span className="text-xs font-bold tracking-[0.07em] text-text3 uppercase">
                Address
              </span>
              <button
                type="button"
                title="Copy address"
                disabled={!chipsEnabled}
                className="truncate text-sm font-medium transition-colors hover:text-brand disabled:text-text3"
                onClick={() => copyText(creds?.host ?? "", () => {})}
              >
                {creds?.host ?? "—"}
              </button>
            </div>
            <div className="flex items-center justify-between gap-3">
              <span className="text-xs font-bold tracking-[0.07em] text-text3 uppercase">
                Pairing code
              </span>
              <button
                type="button"
                title="Copy pairing code"
                disabled={!chipsEnabled}
                className="truncate font-mono text-sm font-medium transition-colors hover:text-brand disabled:text-text3"
                onClick={() => copyText((creds?.token ?? "").replace(/\s+/g, ""), () => {})}
              >
                {creds?.token ?? "—"}
              </button>
            </div>
          </div>

          <div className="mt-4 flex flex-wrap gap-2">
            <CopyButton
              getValue={() =>
                getJSON<PairInfo>("/api/pair/status").then((d) =>
                  d.active ? d.url : "",
                )
              }
              icon="link"
              label="Copy link"
              disabled={!chipsEnabled}
            />
            <Button
              variant="outline"
              size="sm"
              className="h-8"
              disabled={!chipsEnabled}
              onClick={newCode}
            >
              <Mi n="sync_alt" className="text-[16px]" />
              New code
            </Button>
          </div>

          <p className="mt-4 flex items-center gap-2 text-sm text-text2" role="status" aria-live="polite">
            <span
              className={`size-2 shrink-0 rounded-full ${
                live.kind === "waiting"
                  ? "bg-text3"
                  : live.kind === "busy"
                    ? "animate-pulse bg-brand"
                    : live.kind === "ok"
                      ? "bg-success"
                      : "bg-error"
              }`}
            />
            {live.text}
          </p>

          <button
            type="button"
            disabled={cancelDisabled}
            onClick={cancelPairing}
            className="mt-3 text-xs text-text3 underline-offset-2 transition-colors hover:text-text2 hover:underline disabled:opacity-60"
          >
            Cancel pairing
          </button>
        </div>
      </div>
    </div>
  )
}

