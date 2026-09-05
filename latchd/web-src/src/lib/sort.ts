import type { FileEntry } from "@/lib/api"
import { epochOf } from "@/lib/format"

export type SortKey = "name" | "date" | "size"

export interface SortSpec {
  key: SortKey
  dir: 1 | -1
}

export const DEFAULT_SORT: SortSpec = { key: "name", dir: 1 }

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" })

export function parseSort(s: string | null): SortSpec {
  if (!s) return DEFAULT_SORT
  const [key, dir] = s.split(":")
  if (key !== "name" && key !== "date" && key !== "size") return DEFAULT_SORT
  return { key, dir: dir === "-1" ? -1 : 1 }
}

export function fmtSort(s: SortSpec): string {
  return `${s.key}:${s.dir}`
}

export function sortFiles(files: FileEntry[], sort: SortSpec): FileEntry[] {
  const out = [...files]
  out.sort((a, b) => {
    let r = 0
    if (sort.key === "name") r = collator.compare(a.name, b.name)
    else if (sort.key === "size") r = a.size - b.size
    else r = epochOf(a) - epochOf(b)
    return r * sort.dir
  })
  return out
}

export function nextSort(current: SortSpec, key: SortKey): SortSpec {
  if (current.key === key) return { key, dir: current.dir === 1 ? -1 : 1 }
  return { key, dir: key === "name" ? 1 : -1 }
}
