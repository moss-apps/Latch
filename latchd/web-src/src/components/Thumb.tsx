import { useState } from "react"
import type { FileEntry } from "@/lib/api"
import { thumbUrl } from "@/lib/api"
import { Mi } from "@/components/Mi"
import { typeSpec, typeColor } from "@/lib/glyphs"
import { useTheme } from "@/lib/theme"

// A tile shows either the server thumbnail (images) or the type glyph.
// Nothing is cropped: images use object-contain so a portrait shows in full,
// letterboxed on a fixed-aspect tile instead of being sliced to a square.
export function Thumb({
  file,
  boxClass,
  iconClass,
  aspect = "aspect-square",
  fit = "cover",
}: {
  file: FileEntry
  boxClass?: string
  iconClass?: string
  aspect?: string
  fit?: "cover" | "contain"
}) {
  const t = useTheme()
  const isImage =
    file.type === "image" || (file.mimeType || "").startsWith("image/")
  const [glyph, setGlyph] = useState(!isImage)

  if (glyph) {
    const st = typeSpec(file.type)
    return (
      <div
        className={`relative shrink-0 overflow-hidden ${boxClass ?? ""} ${aspect} grid place-items-center bg-bg2`}
      >
        <Mi
          n={st.icon}
          className={iconClass ?? "text-[46px]"}
          style={{ color: typeColor(file.type, t.dark, t.accent) }}
        />
      </div>
    )
  }

  return (
    <div
      className={`relative shrink-0 overflow-hidden ${boxClass ?? ""} ${aspect} bg-bg2`}
    >
      <img
        src={thumbUrl(file.id)}
        alt=""
        loading="lazy"
        decoding="async"
        className={`absolute inset-0 h-full w-full ${
          fit === "contain" ? "object-contain" : "object-cover"
        }`}
        onError={() => setGlyph(true)}
      />
    </div>
  )
}