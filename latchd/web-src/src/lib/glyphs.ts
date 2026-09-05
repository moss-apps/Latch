// Material icon codepoints — the exact glyphs Flutter's Icons class uses,
// from Flutter's own MaterialIcons-Regular.otf (the font we ship).
export const GLYPHS = {
  image: 0xe332,
  videocam: 0xe6a8,
  music_note: 0xe415,
  description: 0xe1bf,
  insert_drive_file: 0xe342,
  star: 0xe5f9,
  sync_alt: 0xe630,
  warning: 0xe6cb,
  verified: 0xe699,
  backup: 0xe0c6,
  save_alt: 0xe551,
  dark_mode: 0xe1b0,
  light_mode: 0xe37a,
  smartphone: 0xe5c6,
  folder: 0xe2a3,
  folder_open: 0xe2a4,
  search: 0xe567,
  visibility: 0xe6bd,
  visibility_off: 0xe6be,
  check_circle: 0xe159,
  error_outline: 0xe238,
  link: 0xe380,
  lock: 0xe3ae,
  lock_open: 0xe3b0,
  schedule: 0xe556,
  palette: 0xe46b,
  view_list: 0xe6b5,
  grid_view: 0xe2ea,
  close: 0xe16a,
  chevron_left: 0xe15e,
  chevron_right: 0xe15f,
  arrow_upward: 0xe0a0,
  arrow_downward: 0xe097,
  zoom_in: 0xe6fd,
  zoom_out: 0xe6fe,
} as const

export type GlyphName = keyof typeof GLYPHS

export function miChar(name: GlyphName): string {
  return String.fromCharCode(GLYPHS[name])
}

// FileTypeColors (app_colors.dart): image follows the accent.
export const TYPES: Record<
  string,
  { icon: GlyphName; light: string | null; dark: string | null }
> = {
  image: { icon: "image", light: null, dark: null },
  video: { icon: "videocam", light: "#D32F2F", dark: "#EF5350" },
  song: { icon: "music_note", light: "#9C27B0", dark: "#BA68C8" },
  document: { icon: "description", light: "#EF6C00", dark: "#FFB74D" },
  other: { icon: "insert_drive_file", light: "#757575", dark: "#8A8886" },
}

export const STAR_COLOR = "#FFC107"

export function typeSpec(type: string) {
  return TYPES[type] ?? TYPES.other
}

export function typeColor(type: string, dark: boolean, accent: string): string {
  const spec = typeSpec(type)
  if (spec.light === null) return accent
  return dark ? spec.dark! : spec.light
}
