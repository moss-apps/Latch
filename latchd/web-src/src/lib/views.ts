import type { FileEntry } from "@/lib/api"
import type { GlyphName } from "@/lib/glyphs"

export interface ViewDef {
  id: string
  label: string
  icon: GlyphName
}

export const VIEWS: ViewDef[] = [
  { id: "all", label: "All files", icon: "folder" },
  { id: "photos", label: "Photos", icon: "image" },
  { id: "videos", label: "Videos", icon: "videocam" },
  { id: "songs", label: "Songs", icon: "music_note" },
  { id: "documents", label: "Documents", icon: "description" },
  { id: "favorites", label: "Favorites", icon: "star" },
]

export function viewFilter(view: string, f: FileEntry): boolean {
  switch (view) {
    case "photos":
      return f.type === "image"
    case "videos":
      return f.type === "video"
    case "songs":
      return f.type === "song"
    case "documents":
      return f.type === "document"
    case "favorites":
      return !!f.favorite
    default:
      return true
  }
}
