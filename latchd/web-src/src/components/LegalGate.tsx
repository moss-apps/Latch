import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Markdown } from "@/lib/markdown"
import { api, getJSON, type LegalDoc, type LegalInfo } from "@/lib/api"

interface LegalGateProps {
  onAccepted: () => void
}

// LegalDocTabs is the underline tab bar shared by the first-run gate and
// the Settings → Legal reader.
export function LegalDocTabs({
  documents,
  activeId,
  onSelect,
  className = "",
}: {
  documents: LegalDoc[]
  activeId: string
  onSelect: (id: string) => void
  className?: string
}) {
  return (
    <nav
      className={`flex gap-1 overflow-x-auto border-b border-divider ${className}`.trim()}
      role="tablist"
      aria-label="Legal documents"
    >
      {documents.map((d) => (
        <button
          key={d.id}
          type="button"
          role="tab"
          aria-selected={d.id === activeId}
          onClick={() => onSelect(d.id)}
          className={`shrink-0 border-b-2 px-3 pt-2.5 pb-2 text-sm font-semibold transition-colors ${
            d.id === activeId
              ? "border-brand text-text"
              : "border-transparent text-text3 hover:text-text2"
          }`}
        >
          {d.title}
        </button>
      ))}
    </nav>
  )
}

export function LegalGate({ onAccepted }: LegalGateProps) {
  const [info, setInfo] = useState<LegalInfo | null>(null)
  const [activeId, setActiveId] = useState("eula")
  const [accepting, setAccepting] = useState(false)
  const [error, setError] = useState("")

  useEffect(() => {
    getJSON<LegalInfo>("/api/legal")
      .then((d) => {
        if (d.accepted) {
          onAccepted()
          return
        }
        setInfo(d)
        if (d.documents.length > 0) setActiveId(d.documents[0].id)
      })
      .catch(() => setError("Could not reach latchd. Is it running?"))
    // onAccepted is stable (App passes an inline refresh; run once on mount).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

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

  const doc = info?.documents.find((d) => d.id === activeId)

  return (
    <div
      className="flex h-full min-h-0 flex-col"
      role="dialog"
      aria-modal="true"
      aria-label="License agreement"
    >
      <header className="flex shrink-0 flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-divider px-4 py-4 md:px-8">
        <h2 className="text-xl font-bold tracking-tight">Before you use Latch</h2>
        <p className="min-w-0 text-sm text-text2">
          Read and accept the License Agreement, Terms and Privacy Policy to
          continue. No accounts, no tracking — the app is local-first.
        </p>
        <span className="ml-auto shrink-0 text-xs text-text3">
          {info ? `Version ${info.version} · asked again if the terms change` : ""}
        </span>
      </header>

      <LegalDocTabs
        className="shrink-0 px-4 md:px-8"
        documents={info?.documents ?? []}
        activeId={activeId}
        onSelect={setActiveId}
      />

      <div className="min-h-0 flex-1 overflow-y-auto px-4 py-6 md:px-8">
        {doc ? (
          <Markdown source={doc.markdown} />
        ) : (
          <p className="text-sm text-text3">{error || "Loading…"}</p>
        )}
      </div>

      <footer className="flex shrink-0 flex-wrap items-center gap-3 border-t border-divider px-4 py-3 md:px-8">
        {error && doc && (
          <p className="text-sm text-red-600" role="alert">
            {error}
          </p>
        )}
        <Button
          onClick={accept}
          disabled={!info || accepting}
          className="ml-auto h-9"
        >
          {accepting ? "Accepting…" : "I accept"}
        </Button>
      </footer>
    </div>
  )
}
