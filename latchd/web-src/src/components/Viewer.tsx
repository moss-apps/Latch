import { useEffect, useRef, useState } from "react"
import type { ReactNode } from "react"
import type { FileEntry } from "@/lib/api"
import { fileUrl } from "@/lib/api"
import { cap, fileDate, fmtDate, fmtSize } from "@/lib/format"
import { STAR_COLOR, typeColor, typeSpec } from "@/lib/glyphs"
import { useTheme } from "@/lib/theme"
import { Mi } from "@/components/Mi"

const TEXT_CAP = 2 * 1024 * 1024
const MAX_SCALE = 8

type Kind = "image" | "video" | "song" | "pdf" | "text" | "none"

function previewKind(f: FileEntry): Kind {
  const mime = f.mimeType || ""
  const name = f.name.toLowerCase()
  if (f.type === "image" || mime.startsWith("image/")) return "image"
  if (f.type === "video" || mime.startsWith("video/")) return "video"
  if (f.type === "song" || mime.startsWith("audio/")) return "song"
  if (mime === "application/pdf" || name.endsWith(".pdf")) return "pdf"
  if (
    mime.startsWith("text/") ||
    /\.(txt|md|csv|log|json|xml)$/.test(name)
  ) {
    return "text"
  }
  return "none"
}

async function headError(url: string): Promise<string> {
  try {
    const res = await fetch(url, { method: "HEAD" })
    if (res.status === 422) {
      return "This file predates GCM encryption and can't be opened in the browser. Use Export decrypted for it."
    }
    if (res.status === 404) {
      return "The encrypted blob is missing or corrupt. Pair the phone again to re-send it."
    }
    return "Couldn't load this file."
  } catch {
    return "Couldn't load this file."
  }
}

function Spinner() {
  return (
    <span className="size-8 animate-spin rounded-full border-[3px] border-white/25 border-t-white" />
  )
}

function CenterCol({ children }: { children: ReactNode }) {
  return (
    <div className="grid h-full place-items-center p-6">
      <div className="flex max-w-md flex-col items-center gap-4 text-center">{children}</div>
    </div>
  )
}

function DownloadLink({ file, solid }: { file: FileEntry; solid?: boolean }) {
  return (
    <a
      href={fileUrl(file.id, true)}
      download={file.name}
      className={
        solid
          ? "inline-flex h-10 items-center gap-2 rounded-xl bg-white px-5 text-sm font-medium text-[#121212] transition-colors hover:bg-white/85"
          : "inline-flex h-9 items-center gap-2 rounded-lg bg-white/10 px-3.5 text-sm transition-colors hover:bg-white/20"
      }
    >
      <Mi n="save_alt" className="text-[18px]" />
      Download
    </a>
  )
}

function VwError({ message, file }: { message: string; file: FileEntry }) {
  return (
    <CenterCol>
      <Mi n="error_outline" className="text-[56px] text-white/50" />
      <p className="text-sm leading-relaxed text-white/80">{message}</p>
      <DownloadLink file={file} solid />
    </CenterCol>
  )
}

function ZoomableImage({
  url,
  name,
  onLoaded,
  onError,
}: {
  url: string
  name: string
  onLoaded: () => void
  onError: () => void
}) {
  const wrap = useRef<HTMLDivElement>(null)
  const img = useRef<HTMLImageElement>(null)
  const [tf, setTf] = useState({ s: 1, x: 0, y: 0 })
  const [grabbing, setGrabbing] = useState(false)
  const drag = useRef({ active: false, px: 0, py: 0, tx: 0, ty: 0 })

  useEffect(() => {
    setTf({ s: 1, x: 0, y: 0 })
  }, [url])

  // Keep the scaled image inside the stage; smaller-than-stage stays centered.
  const clampT = (s: number, x: number, y: number) => {
    const el = img.current
    const w = wrap.current
    if (!el || !w || s <= 1) return { s, x: 0, y: 0 }
    const cs = getComputedStyle(w)
    const bw = w.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)
    const bh = w.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom)
    const mx = Math.max(0, (el.clientWidth * s - bw) / 2)
    const my = Math.max(0, (el.clientHeight * s - bh) / 2)
    return { s, x: Math.min(mx, Math.max(-mx, x)), y: Math.min(my, Math.max(-my, y)) }
  }

  // Zoom toward the cursor: scaling about the center pushes the cursor
  // point out by (f-1)*dist, so translate the other way to pin it.
  const zoomTo = (
    prev: { s: number; x: number; y: number },
    next: number,
    cx: number,
    cy: number,
  ) => {
    const el = img.current
    if (!el) return prev
    const ns = Math.min(MAX_SCALE, Math.max(1, next))
    if (ns === prev.s) return prev
    const rect = el.getBoundingClientRect()
    const f = ns / prev.s
    const dx = cx - (rect.left + rect.width / 2)
    const dy = cy - (rect.top + rect.height / 2)
    return clampT(ns, prev.x - dx * (f - 1), prev.y - dy * (f - 1))
  }

  const zoomCenter = (factor: number) => {
    const w = wrap.current
    if (!w) return
    const r = w.getBoundingClientRect()
    setTf((prev) =>
      zoomTo(prev, prev.s * factor, r.left + r.width / 2, r.top + r.height / 2),
    )
  }

  // React wheel events are passive; a native listener can preventDefault.
  useEffect(() => {
    const w = wrap.current
    if (!w) return
    const onWheel = (e: WheelEvent) => {
      // Trackpad pinch (ctrl+wheel) is the browser's page zoom, not ours.
      if (e.ctrlKey || e.metaKey) return
      e.preventDefault()
      setTf((prev) => zoomTo(prev, prev.s - e.deltaY * 0.0015, e.clientX, e.clientY))
    }
    w.addEventListener("wheel", onWheel, { passive: false })
    return () => w.removeEventListener("wheel", onWheel)
  }, [])

  const onDown = (e: React.PointerEvent) => {
    if (tf.s <= 1) return
    if ((e.target as HTMLElement).closest("button")) return
    e.currentTarget.setPointerCapture(e.pointerId)
    drag.current = { active: true, px: e.clientX, py: e.clientY, tx: tf.x, ty: tf.y }
    setGrabbing(true)
  }
  const onMove = (e: React.PointerEvent) => {
    const d = drag.current
    if (!d.active) return
    setTf(clampT(tf.s, d.tx + e.clientX - d.px, d.ty + e.clientY - d.py))
  }
  const onUp = () => {
    drag.current = { active: false, px: 0, py: 0, tx: 0, ty: 0 }
    setGrabbing(false)
  }

  return (
    <div
      ref={wrap}
      className={`relative grid h-full place-items-center overflow-hidden p-6 md:p-10 ${
        tf.s > 1 ? "cursor-grab active:cursor-grabbing" : ""
      }`}
      onPointerDown={onDown}
      onPointerMove={onMove}
      onPointerUp={onUp}
      onPointerCancel={onUp}
      onDoubleClick={(e) => {
        if ((e.target as HTMLElement).closest("button")) return
        setTf((prev) =>
          prev.s > 1.01 ? { s: 1, x: 0, y: 0 } : zoomTo(prev, 2.5, e.clientX, e.clientY),
        )
      }}
    >
      <img
        ref={img}
        src={url}
        alt={name}
        onLoad={onLoaded}
        onError={onError}
        draggable={false}
        className="max-h-full max-w-full min-h-0 min-w-0 select-none object-contain"
        style={{
          transform: `translate(${tf.x}px, ${tf.y}px) scale(${tf.s})`,
          transformOrigin: "center center",
          transition: grabbing ? "none" : "transform 160ms ease",
          touchAction: "none",
        }}
      />
      <div className="absolute bottom-4 left-1/2 flex -translate-x-1/2 items-center gap-0.5 rounded-full bg-black/60 px-1.5 py-1 backdrop-blur-sm">
        <button
          type="button"
          aria-label="Zoom out"
          title="Zoom out"
          onClick={() => zoomCenter(0.8)}
          className="grid size-8 place-items-center rounded-full text-white/85 transition-colors hover:bg-white/20"
        >
          <Mi n="zoom_out" className="text-[18px]" />
        </button>
        <button
          type="button"
          aria-label="Reset to fit"
          title="Reset to fit"
          onClick={() => setTf({ s: 1, x: 0, y: 0 })}
          className="min-w-14 rounded-full px-2 py-1 text-center text-xs font-medium text-white/85 tabular-nums transition-colors hover:bg-white/20"
        >
          {Math.round(tf.s * 100)}%
        </button>
        <button
          type="button"
          aria-label="Zoom in"
          title="Zoom in"
          onClick={() => zoomCenter(1.25)}
          className="grid size-8 place-items-center rounded-full text-white/85 transition-colors hover:bg-white/20"
        >
          <Mi n="zoom_in" className="text-[18px]" />
        </button>
      </div>
    </div>
  )
}

function Stage({ file }: { file: FileEntry }) {
  const t = useTheme()
  const kind = previewKind(file)
  const url = fileUrl(file.id)
  const [loaded, setLoaded] = useState(false)
  const [err, setErr] = useState("")
  const [text, setText] = useState<string | null>(null)

  useEffect(() => {
    setLoaded(false)
    setErr("")
    setText(null)
    let alive = true

    if (kind === "text") {
      fetch(url)
        .then(async (res) => {
          if (!res.ok) throw new Error(await headError(url))
          const len = Number(res.headers.get("Content-Length") || 0)
          if (len > TEXT_CAP) throw new Error("Too large to preview (over 2 MB). Download it instead.")
          const body = await res.text()
          if (body.length > TEXT_CAP) {
            throw new Error("Too large to preview (over 2 MB). Download it instead.")
          }
          if (alive) setText(body)
        })
        .catch((e: Error) => {
          if (alive) setErr(e.message || "Couldn't load this file.")
        })
    }

    return () => {
      alive = false
    }
  }, [kind, url])

if (err) return <VwError message={err} file={file} />

  if (kind === "image") {
    return (
      <div className="relative h-full">
        {!loaded && (
          <div className="absolute inset-0 grid place-items-center">
            <Spinner />
          </div>
        )}
        <ZoomableImage
          url={url}
          name={file.name}
          onLoaded={() => setLoaded(true)}
          onError={() => headError(url).then(setErr)}
        />
      </div>
    )
  }

  if (kind === "video") {
    return (
      <div className="grid h-full place-items-center p-6">
        <video
          key={file.id}
          controls
          autoPlay
          playsInline
          src={url}
          onError={() => headError(url).then(setErr)}
          className="max-h-full max-w-full min-h-0 min-w-0"
        />
      </div>
    )
  }

  if (kind === "song") {
    return (
      <CenterCol>
        <div className="grid size-24 place-items-center rounded-2xl bg-white/10">
          <Mi
            n={typeSpec(file.type).icon}
            className="text-[44px]"
            style={{ color: typeColor(file.type, t.dark, t.accent) }}
          />
        </div>
        <p className="font-medium">{file.name}</p>
        <audio key={file.id} controls autoPlay src={url} className="w-full max-w-md" />
      </CenterCol>
    )
  }

  if (kind === "pdf") {
    return (
      <div className="h-full p-4 md:p-8">
        <iframe
          key={file.id}
          src={url}
          title={file.name}
          className="h-full w-full rounded-xl bg-white"
        />
      </div>
    )
  }

  if (kind === "text") {
    if (text === null) return <CenterCol><Spinner /></CenterCol>
    return (
      <div className="grid h-full place-items-center p-4 md:p-8">
        <pre className="max-h-full w-full max-w-4xl overflow-auto rounded-xl bg-surface p-5 font-mono text-[13px] leading-relaxed break-words whitespace-pre-wrap text-text2">
          {text}
        </pre>
      </div>
    )
  }

  return (
    <CenterCol>
      <Mi n="insert_drive_file" className="text-[72px] text-white/50" />
      <p className="font-medium">No preview for this format</p>
      <DownloadLink file={file} solid />
    </CenterCol>
  )
}

export function Viewer({
  list,
  index,
  onClose,
  onIndex,
}: {
  list: FileEntry[]
  index: number
  onClose: () => void
  onIndex: (i: number) => void
}) {
  const file = list[index]
  const closeRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    document.documentElement.classList.add("viewer-open")
    closeRef.current?.focus()
    return () => {
      document.documentElement.classList.remove("viewer-open")
    }
  }, [index])

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
      else if (e.key === "ArrowLeft" && index > 0) onIndex(index - 1)
      else if (e.key === "ArrowRight" && index < list.length - 1) onIndex(index + 1)
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [index, list.length, onClose, onIndex])

  if (!file) return null

  const meta = `${cap(file.type)} · ${fmtSize(file.size)} · ${fmtDate(fileDate(file))}`

  return (
    <div
      className="fixed inset-0 z-50 flex flex-col bg-[rgba(12,12,14,0.86)] text-white select-none"
      role="dialog"
      aria-modal="true"
      aria-label={file.name}
    >
      <header className="flex h-14 shrink-0 items-center gap-3 px-4">
        <Mi n={typeSpec(file.type).icon} className="text-[20px] text-white/60" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium">
            {file.name}
            {file.favorite && (
              <Mi n="star" className="ml-1.5 text-[13px] align-[-2px]" style={{ color: STAR_COLOR }} />
            )}
          </p>
          <p className="truncate text-xs text-white/55">{meta}</p>
        </div>
        <DownloadLink file={file} />
        <button
          ref={closeRef}
          type="button"
          onClick={onClose}
          aria-label="Close viewer"
          className="grid size-9 shrink-0 place-items-center rounded-lg bg-white/10 transition-colors hover:bg-white/20"
        >
          <Mi n="close" className="text-[20px]" />
        </button>
      </header>
      <div className="relative min-h-0 flex-1">
        <Stage file={file} />
        {index > 0 && (
          <button
            type="button"
            aria-label="Previous file"
            onClick={() => onIndex(index - 1)}
            className="absolute top-1/2 left-4 grid size-11 -translate-y-1/2 place-items-center rounded-full bg-white/10 transition-colors hover:bg-white/25"
          >
            <Mi n="chevron_left" className="text-[24px]" />
          </button>
        )}
        {index < list.length - 1 && (
          <button
            type="button"
            aria-label="Next file"
            onClick={() => onIndex(index + 1)}
            className="absolute top-1/2 right-4 grid size-11 -translate-y-1/2 place-items-center rounded-full bg-white/10 transition-colors hover:bg-white/25"
          >
            <Mi n="chevron_right" className="text-[24px]" />
          </button>
        )}
      </div>
    </div>
  )
}
