import type { CSSProperties } from "react"
import { miChar, type GlyphName } from "@/lib/glyphs"

export function Mi({
  n,
  className,
  style,
}: {
  n: GlyphName
  className?: string
  style?: CSSProperties
}) {
  return (
    <span className={`mi ${className ?? ""}`} style={style} aria-hidden="true">
      {miChar(n)}
    </span>
  )
}
