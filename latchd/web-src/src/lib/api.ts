export interface FileEntry {
  id: string
  name: string
  type: string
  size: number
  favorite: boolean
  mimeType: string
  dateAdded: string | null
  dateModified: string | null
}

export interface StatusInfo {
  unlocked: boolean
  files: number
  dir: string
  hasLocal: boolean
  lastBackup: string | null
}

export interface PairInfo {
  active: boolean
  state: string
  host: string
  port: number
  token: string
  url: string
  files: number
  bytes: number
  lastError: string
}

export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

export async function api<T = unknown>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
  })
  const data = await res.json().catch(() => null)
  if (!res.ok) {
    throw new ApiError((data && data.error) || `HTTP ${res.status}`, res.status)
  }
  return data as T
}

export async function getJSON<T>(path: string): Promise<T> {
  const res = await fetch(path)
  return res.json() as Promise<T>
}

export function fileUrl(id: string, download = false): string {
  return `/api/file/${encodeURIComponent(id)}${download ? "?dl=1" : ""}`
}

export function thumbUrl(id: string): string {
  return `/api/thumb/${encodeURIComponent(id)}`
}
