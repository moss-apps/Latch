import { Mi } from "@/components/Mi"

export type StatusKind = "" | "busy" | "ok" | "err"

export function StatusLine({
  kind,
  text,
  className,
}: {
  kind: StatusKind
  text: string
  className?: string
}) {
  if (!kind && !text) return null
  return (
    <p
      className={`flex items-center gap-2 text-sm ${kind === "ok" ? "text-ok-text" : kind === "err" ? "text-err-text" : "text-text2"} ${className ?? ""}`}
      role="status"
      aria-live="polite"
    >
      {kind === "busy" && (
        <span className="h-4 w-4 shrink-0 animate-spin rounded-full border-2 border-text3 border-t-transparent" />
      )}
      {kind === "ok" && <Mi n="check_circle" className="text-[18px]" />}
      {kind === "err" && <Mi n="error_outline" className="text-[18px]" />}
      {text}
    </p>
  )
}
