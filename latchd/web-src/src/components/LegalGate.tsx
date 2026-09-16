import { useEffect, useState } from "react"
import { Mi } from "@/components/Mi"
import { Button } from "@/components/ui/button"
import { api, getJSON, type LegalDoc, type LegalInfo } from "@/lib/api"

interface LegalGateProps {
  onAccepted: () => void
}

export function LegalGate({ onAccepted }: LegalGateProps) {
  const [info, setInfo] = useState<LegalInfo | null>(null)
  const [activeId, setActiveId] = useState<string>("eula")
  const [body, setBody] = useState<string>("Loading…")
  const [accepting, setAccepting] = useState(false)
  const [error, setError] = useState("")

  useEffect(() => {
    getJSON<LegalInfo>("/api/legal")
      .then((d) => {
        setInfo(d)
        if (d.accepted) {
          onAccepted()
          return
        }
        if (d.documents.length > 0) setActiveId(d.documents[0].id)
      })
      .catch(() => setError("Could not reach latchd. Is it running?"))
    // onAccepted is stable (App passes an inline refresh; run once on mount).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (!info) return
    const doc: LegalDoc | undefined = info.documents.find((d) => d.id === activeId)
    if (!doc) return
    setBody("Loading…")
    fetch(doc.path)
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.text()
      })
      .then(setBody)
      .catch(() => setBody("Could not load this document. It is also in the repo under legal/."))
  }, [info, activeId])

  async function accept() {
    if (!info) return
    setAccepting(true)
    setError("")
    try {
      await api("/api/legal/accept", { version: info.version })
      onAccepted()
    } catch (err) {
      setError((err as Error).message || "Accept failed. Reload and try again.")
    } finally {
      setAccepting(false)
    }
  }

  return (
    <div
      className="grid h-full place-items-center overflow-y-auto p-4"
      role="dialog"
      aria-modal="true"
      aria-label="License agreement"
    >
      <div className="flex max-h-full w-full max-w-[560px] flex-col rounded-2xl border border-divider bg-background shadow-2xl">
        <header className="flex shrink-0 items-center gap-2 px-5 pt-5">
          <Mi n="verified" className="text-[22px] text-brand" />
          <h2 className="text-base font-bold">Before you use Latch</h2>
        </header>
        <p className="shrink-0 px-5 pt-1 text-sm leading-relaxed text-text2">
          Latch is local-first encrypted storage. Read the terms, then accept to
          continue. No accounts, no tracking — see the Privacy Policy.
        </p>

        {info && (
          <div className="flex shrink-0 gap-1.5 overflow-x-auto px-5 pt-3" role="tablist" aria-label="Legal documents">
            {info.documents.map((d) => (
              <button
                key={d.id}
                type="button"
                role="tab"
                aria-selected={d.id === activeId}
                onClick={() => setActiveId(d.id)}
                className={`shrink-0 rounded-full border px-3 py-1.5 text-xs font-semibold transition-colors ${
                  d.id === activeId
                    ? "border-brand bg-brand text-white"
                    : "border-divider text-text2 hover:bg-bg2"
                }`}
              >
                {d.title}
              </button>
            ))}
          </div>
        )}

        <pre className="mx-5 mt-3 min-h-[220px] flex-1 overflow-y-auto rounded-xl border border-divider bg-bg2 p-4 font-sans text-[13px] leading-relaxed whitespace-pre-wrap text-text2">
          {body}
        </pre>

        {error && (
          <p className="shrink-0 px-5 pt-2 text-sm text-red-600" role="alert">
            {error}
          </p>
        )}

        <div className="flex shrink-0 items-center justify-between gap-3 px-5 py-4">
          <span className="text-xs text-text3">
            {info ? `Version ${info.version} · stored locally, re-asked on change` : ""}
          </span>
          <Button onClick={accept} disabled={!info || accepting} className="h-9">
            {accepting ? "Accepting…" : "I accept"}
          </Button>
        </div>
      </div>
    </div>
  )
}
