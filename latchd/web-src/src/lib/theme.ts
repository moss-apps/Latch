import { useSyncExternalStore } from "react"

// id, label, light, dark, lightVariant, darkVariant — AccentColors,
// mirrors lib/models/accent_color.dart. Don't eyeball these.
export const ACCENTS: [string, string, string, string, string, string][] = [
  ["blue", "Ocean Blue", "#1976D2", "#5C9CE6", "#42A5F5", "#7AB3F0"],
  ["purple", "Royal Purple", "#7B1FA2", "#AB47BC", "#9C27B0", "#BA68C8"],
  ["teal", "Emerald Teal", "#00796B", "#26A69A", "#009688", "#4DB6AC"],
  ["green", "Forest Green", "#388E3C", "#66BB6A", "#4CAF50", "#81C784"],
  ["orange", "Sunset Orange", "#E64A19", "#FF7043", "#FF5722", "#FF8A65"],
  ["pink", "Rose Pink", "#C2185B", "#EC407A", "#E91E63", "#F06292"],
  ["red", "Ruby Red", "#D32F2F", "#EF5350", "#F44336", "#E57373"],
  ["indigo", "Deep Indigo", "#303F9F", "#5C6BC0", "#3F51B5", "#7986CB"],
  ["cyan", "Sky Cyan", "#0097A7", "#26C6DA", "#00BCD4", "#4DD0E1"],
  ["amber", "Golden Amber", "#F57C00", "#FFB74D", "#FF9800", "#FFCC80"],
  ["gunmetal", "Gunmetal Gray", "#353E43", "#353E43", "#4A565C", "#4A565C"],
]

export type ThemeName = "light" | "dark"

export interface ThemeState {
  theme: ThemeName
  accentId: string
  accent: string
  accentVariant: string
  dark: boolean
}

const LS_THEME = "latchd-theme"
const LS_ACCENT = "latchd-accent"

function pick(id: string) {
  return ACCENTS.find((a) => a[0] === id) ?? ACCENTS[0]
}

function normalize(theme: string, accentId: string): ThemeState {
  const t: ThemeName = theme === "dark" ? "dark" : "light"
  const a = pick(accentId)
  return {
    theme: t,
    accentId: a[0],
    accent: t === "dark" ? a[3] : a[2],
    accentVariant: t === "dark" ? a[5] : a[4],
    dark: t === "dark",
  }
}

let state: ThemeState = normalize(
  localStorage.getItem(LS_THEME) ?? "light",
  localStorage.getItem(LS_ACCENT) ?? "blue",
)

const listeners = new Set<() => void>()

// Saved theme/accent must land on <html> before first paint.
apply()

function apply() {
  const root = document.documentElement
  root.classList.toggle("dark", state.dark)
  root.style.setProperty("--latch-accent", state.accent)
  root.style.setProperty("--latch-accent-variant", state.accentVariant)
  listeners.forEach((l) => l())
}

export function getThemeState(): ThemeState {
  return state
}

export function setTheme(theme: ThemeName) {
  localStorage.setItem(LS_THEME, theme)
  state = normalize(theme, state.accentId)
  apply()
}

export function setAccent(id: string) {
  localStorage.setItem(LS_ACCENT, id)
  state = normalize(state.theme, id)
  apply()
}

function subscribe(fn: () => void) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

export function useTheme(): ThemeState {
  return useSyncExternalStore(subscribe, getThemeState)
}
