import { useSyncExternalStore } from "react"

const LS_SHOW_THUMBS = "latchd-show-thumbs"

function read(): boolean {
  // Thumbnails on by default; "false" means file-type icons everywhere.
  try {
    return localStorage.getItem(LS_SHOW_THUMBS) !== "false"
  } catch {
    return true
  }
}

let show = read()

const listeners = new Set<() => void>()

function notify() {
  listeners.forEach((l) => l())
}

export function getShowThumbnails(): boolean {
  return show
}

export function setShowThumbnails(next: boolean) {
  show = next
  try {
    localStorage.setItem(LS_SHOW_THUMBS, next ? "true" : "false")
  } catch {
    // private mode or whatever, keep the in-memory value
  }
  notify()
}

function subscribe(fn: () => void) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

export function useShowThumbnails(): boolean {
  return useSyncExternalStore(subscribe, getShowThumbnails)
}
