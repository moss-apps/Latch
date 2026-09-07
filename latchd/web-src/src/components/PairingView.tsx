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
type SessionMode = "push" | "restore"

const STEPS_PUSH = [
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

const STEPS_RESTORE = [
  <>
    Open <strong>Latch</strong> on your phone.
  </>,
  <>
    Go to <strong>Settings&nbsp;→&nbsp;Storage&nbsp;→&nbsp;Desktop Backup&nbsp;→&nbsp;Restore from this computer</strong>.
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
  const [creds, setCreds] = useState<{
    host: string
    port: number
    token: string
    url: string
  } | null>(null)
  const [veil, setVeil] = useState<Veil>(null)
  const [mode, setMode] = useState<SessionMode>("push")
  const [live, setLive] = useState<{ kind: LiveKind; text: string }>({
    kind: "waiting",
    text: "Opening pairing session…",
  })
  const [chipsEnabled, setChipsEnabled] = useState(false)
  const [cancelDisabled, setCancelDisabled] = useState(false)
  const [usbPending, setUsbPending] = useState<{ device: string } | null>(null)
  const [usbApproved, setUsbApproved] = useState(false)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const completeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const startedRef = useRef(false)
  const doneRef = useRef(false)
  const modeRef = useRef<SessionMode>("push")
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
    const m: SessionMode = d.mode === "restore" ? "restore" : "push"
    if (d.active) {
      startedRef.current = true
      setChipsEnabled(true)
      setCreds({ host: `${d.host}:${d.port}`, port: d.port, token: fmtCode(d.token), url: d.url })
      setUsbPending(d.usbPending ? { device: d.usbPending.device } : null)
      setUsbApproved(d.usbApproved === true)
      if (m === "restore") {
        if (d.state === "receiving") {
          const served =
            d.served > 0
              ? `: ${d.served} ${d.served === 1 ? "file" : "files"} · ${fmtSize(d.servedBytes)}`
              : ""
          setLive({ kind: "busy", text: `Serving your phone${served}` })
          setVeil({ icon: "sync_alt", text: "Serving…" })
        } else {
          setLive({
            kind: "waiting",
            text: "Waiting for your phone. Start the restore in the Latch app and scan the code.",
          })
          setVeil(null)
        }
      } else {
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
      }
      ensurePoll()
      return
    }

    stopPoll()
    setUsbPending(null)
    setUsbApproved(false)
    if (m === "restore") {
      // Restore sessions have no completion signal; closed = stopped/error.
      if (startedRef.current) {
        setChipsEnabled(true)
        setCancelDisabled(true)
        setVeil(null)
        setLive({
          kind: "err",
          text: d.lastError
            ? `Restore session closed: ${d.lastError}`
            : "Restore session closed. Codes expire after five idle minutes; start a new code and scan again.",
        })
      }
      return
    }
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

  function startPairing(m: SessionMode) {
    modeRef.current = m
    setMode(m)
    startedRef.current = false
    doneRef.current = false
    setCancelDisabled(false)
    setLive({
      kind: "waiting",
      text: m === "restore" ? "Opening restore session…" : "Opening pairing session…",
    })
    setVeil(null)
    setChipsEnabled(false)
    setUsbPending(null)
    setUsbApproved(false)
    api<PairInfo>("/api/pair/start", { mode: m })
      .then(pairApply)
      .catch((err: Error) => {
        setVeil({ icon: "error_outline", text: "Failed" })
        setLive({
          kind: "err",
          text: `Couldn't open the ${m === "restore" ? "restore" : "pairing"} session: ${
            err.message || "is latchd healthy?"
          } Try again.`,
        })
        setChipsEnabled(true)
        setCancelDisabled(true)
      })
  }

  function switchMode(m: SessionMode) {
    if (m === modeRef.current) return
    stopPoll()
    api("/api/pair/stop").catch(() => {
      /* already gone */
    })
    startPairing(m)
  }

  useEffect(() => {
    startPairing("push")
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

  // Back leaves the screen but keeps the session alive: re-entering
  // re-adopts the same code (pair/start returns the active session).
  function goBack() {
    onEnterMain(unlockedRef.current)
  }

  function cancelPairing() {    setCancelDisabled(true)
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
    startPairing(modeRef.current)
  }

  function allowUsb(allow: boolean) {
    setUsbPending(null)
    api<PairInfo>("/api/pair/allow", { allow })
      .then(pairApply)
      .catch(() => {
        /* poll will re-show the prompt */
      })
  }

  const restore = mode === "restore"
  const steps = restore ? STEPS_RESTORE : STEPS_PUSH
  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto w-full max-w-[1100px] px-6 py-10 lg:py-16">
        {hasLocal && (
          <button
            type="button"
            onClick={goBack}
            aria-label="Back to files"
            className="mb-6 inline-flex h-9 items-center gap-0.5 rounded-lg pr-3 pl-1.5 text-sm text-text2 transition-colors hover:bg-bg2 hover:text-text"
          >
            <Mi n="chevron_left" className="text-[20px]" />
            Back
          </button>
        )}
        <div className="grid gap-14 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div className="flex flex-col gap-6">
          <Logomark className="h-16 text-logo" />
          <div>
            <h1 className="text-4xl font-bold tracking-tight">
              {restore ? "Restore to your phone" : "Pair your phone"}
            </h1>
            <p className="mt-3 max-w-md text-lg leading-relaxed text-text2">
              {restore ? (
                <>
                  This screen serves the backup stored on this computer. Your
                  phone pulls the encrypted snapshot over the session; nothing
                  on this computer is changed.
                </>
              ) : (
                <>
                  This screen creates the pairing credentials. Your phone pushes
                  the encrypted backup here; the vault itself never leaves
                  either device unlocked.
                </>
              )}
            </p>
          </div>
          <ol className="flex max-w-md flex-col gap-3.5">
            {steps.map((s, i) => (
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
              {restore
                ? "The restore session opens latchd to your local network over plain HTTP. The token only admits your phone, the backup stays exactly as it is, and the session closes itself after five idle minutes. Restore on networks you trust."
                : "Pairing opens latchd to your local network over plain HTTP. The token only admits your phone, files arrive already encrypted, and the session closes itself after five idle minutes. Pair on networks you trust."}
            </p>
          </div>
        </div>

        <div className="h-fit w-full rounded-2xl border border-divider bg-card p-6 shadow-lg shadow-black/5">
          <div
            className="mb-5 grid grid-cols-2 gap-1 rounded-lg bg-background p-1"
            role="tablist"
            aria-label="Session mode"
          >
            {(
              [
                ["push", "Receive backup"],
                ["restore", "Restore to phone"],
              ] as const
            ).map(([value, label]) => (
              <button
                key={value}
                type="button"
                role="tab"
                aria-selected={mode === value}
                onClick={() => switchMode(value)}
                className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                  mode === value
                    ? "bg-card text-text1 shadow-sm"
                    : "text-text3 hover:text-text2"
                }`}
              >
                {label}
              </button>
            ))}
          </div>
          {usbPending && (
            <div
              className="mb-4 rounded-xl border border-brand/30 bg-brand/10 p-4"
              role="alert"
            >
              <p className="flex items-center gap-2 text-sm font-semibold text-text">
                <Mi n="smartphone" className="text-[18px]" />
                {usbPending.device} wants to connect over USB
              </p>
              <p className="mt-1 text-[13px] leading-relaxed text-text2">
                Only allow this if you just tapped{" "}
                <strong>Connect via USB</strong> on your phone.
              </p>
              <div className="mt-3 flex gap-2">
                <Button
                  size="sm"
                  className="h-8"
                  onClick={() => allowUsb(true)}
                >
                  Allow once
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="h-8"
                  onClick={() => allowUsb(false)}
                >
                  Deny
                </Button>
              </div>
            </div>
          )}
          {usbApproved && !usbPending && (
            <p className="mb-4 flex items-center gap-2 rounded-xl bg-background p-3 text-[13px] text-text2">
              <Mi n="check_circle" className="text-[16px]" />
              USB phone approved — continue on your phone.
            </p>
          )}
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

          <details className="group mt-4 rounded-xl bg-background p-3">
            <summary className="cursor-pointer list-none text-sm font-medium text-text2 transition-colors hover:text-text [&::-webkit-details-marker]:hidden">
              <span className="inline-flex items-center gap-1.5">
                <Mi n="smartphone" className="text-[16px]" />
                On a USB cable instead of Wi-Fi?
                <span className="rounded-full border border-divider bg-card px-2 py-0.5 text-[12px] font-semibold text-brand group-open:hidden">
                  Click here
                </span>
                <span className="hidden rounded-full border border-divider bg-card px-2 py-0.5 text-[12px] font-semibold text-brand group-open:inline">
                  Hide
                </span>
              </span>
            </summary>
            <div className="mt-2 space-y-2 text-sm leading-relaxed text-text2">
              <p>
                Plug the phone in with USB debugging on, then run this on
                this computer:
              </p>
              <div className="flex items-center justify-between gap-2 rounded-lg bg-card px-2.5 py-1.5">
                <code className="truncate font-mono text-[13px] text-text">
                  {creds
                    ? `adb reverse tcp:${creds.port} tcp:${creds.port}`
                    : "adb reverse tcp:<port> tcp:<port>"}
                </code>
                <CopyButton
                  getValue={() =>
                    getJSON<PairInfo>("/api/pair/status").then((d) =>
                      d.active
                        ? `adb reverse tcp:${d.port} tcp:${d.port}`
                        : "",
                    )
                  }
                  icon="link"
                  label="Copy"
                  disabled={!chipsEnabled}
                />
              </div>
              <p>
                Then on the phone tap <strong>Connect via USB</strong> and
                tap <strong>Allow once</strong> here — no address, no code
                to type.
              </p>
              <p>
                Cable come loose mid-transfer? Plug back in, check{" "}
                <span className="font-mono text-[13px] text-text">
                  adb reverse --list
                </span>{" "}
                still shows the port (re-run the command if not), and tap{" "}
                <strong>Connect via USB</strong> again. Typing the address
                and code by hand still works as a fallback:{" "}
                <span className="font-mono text-[13px] text-text">
                  {creds ? `127.0.0.1:${creds.port}` : "127.0.0.1:<port>"}
                </span>
                .
              </p>
            </div>
          </details>

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
            {restore ? "Cancel restore session" : "Cancel pairing"}
          </button>
        </div>
        </div>
      </div>
    </div>
  )
}

