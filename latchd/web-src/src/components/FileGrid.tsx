import type { FileEntry } from "@/lib/api"
import { Mi } from "@/components/Mi"
import { Thumb } from "@/components/Thumb"
import { STAR_COLOR } from "@/lib/glyphs"

export function FileGrid({
  list,
  shown,
  onOpen,
}: {
  list: FileEntry[]
  shown: number
  onOpen: (index: number) => void
}) {
  return (
    <div className="grid gap-3.5 [grid-template-columns:repeat(auto-fill,minmax(180px,1fr))]">
      {list.slice(0, shown).map((f, i) => (
        <button
          key={f.id}
          type="button"
          className="group flex flex-col overflow-hidden rounded-xl border border-divider bg-background text-left outline-none transition-colors hover:bg-bg2 focus-visible:bg-bg2 focus-visible:ring-2 focus-visible:ring-ring"
          onClick={() => onOpen(i)}
        >
          <Thumb file={f} boxClass="aspect-[4/3] w-full" iconClass="text-[46px]" fit="contain" />
          <span className="flex h-11 shrink-0 items-center gap-1.5 px-3 text-[13px]">
            <span className="truncate">{f.name}</span>
            {f.favorite && (
              <Mi n="star" className="shrink-0 text-[15px]" style={{ color: STAR_COLOR }} />
            )}
          </span>
        </button>
      ))}
    </div>
  )
}
