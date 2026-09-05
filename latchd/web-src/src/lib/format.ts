import type { FileEntry } from "./api"

export function fmtSize(n: number | null | undefined): string {
  if (n === null || n === undefined) return ""
  if (n < 1024) return `${n} B`
  if (n < 1048576) return `${(n / 1024).toFixed(1)} KB`
  if (n < 1073741824) return `${(n / 1048576).toFixed(1)} MB`
  return `${(n / 1073741824).toFixed(2)} GB`
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return "—"
  const d = new Date(iso)
  if (isNaN(d.getTime())) return "—"
  const h = d.getHours()
  const m = d.getMinutes()
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}, ` +
    `${h < 10 ? "0" : ""}${h}:${m < 10 ? "0" : ""}${m}`
}

export function fileDate(f: FileEntry): string | null {
  return f.dateModified ?? f.dateAdded ?? null
}

export function epochOf(f: FileEntry): number {
  const iso = fileDate(f)
  if (!iso) return 0
  const t = new Date(iso).getTime()
  return isNaN(t) ? 0 : t
}

export function fmtCode(token: string): string {
  return (token || "").replace(/(.{4})/g, "$1 ").trim()
}

export function cap(s: string): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s
}
