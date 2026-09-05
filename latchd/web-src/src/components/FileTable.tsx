import type { FileEntry } from "@/lib/api"
import { Mi } from "@/components/Mi"
import { Thumb } from "@/components/Thumb"
import { fileDate, fmtDate, fmtSize } from "@/lib/format"
import { STAR_COLOR } from "@/lib/glyphs"
import type { SortKey, SortSpec } from "@/lib/sort"

function Th({
  label,
  sortKey,
  sort,
  onSortKey,
  className,
}: {
  label: string
  sortKey: SortKey
  sort: SortSpec
  onSortKey: (k: SortKey) => void
  className?: string
}) {
  const active = sort.key === sortKey
  return (
    <th className={`pb-3 pl-2 font-normal ${className ?? ""}`}>
      <button
        type="button"
        className={`flex items-center gap-1 text-[11px] font-bold tracking-[0.07em] uppercase transition-colors ${
          active ? "text-text2" : "text-text3 hover:text-text2"
        }`}
        onClick={() => onSortKey(sortKey)}
      >
        {label}
        {active && (
          <Mi n={sort.dir === 1 ? "arrow_upward" : "arrow_downward"} className="text-[13px]" />
        )}
      </button>
    </th>
  )
}

export function FileTable({
  list,
  shown,
  sort,
  onSortKey,
  onOpen,
}: {
  list: FileEntry[]
  shown: number
  sort: SortSpec
  onSortKey: (k: SortKey) => void
  onOpen: (index: number) => void
}) {
  return (
    <table className="w-full border-collapse text-sm">
      <thead>
        <tr className="border-b border-divider">
          <Th label="Name" sortKey="name" sort={sort} onSortKey={onSortKey} className="text-left" />
          <Th
            label="Modified"
            sortKey="date"
            sort={sort}
            onSortKey={onSortKey}
            className="hidden text-left sm:table-cell"
          />
          <Th
            label="Size"
            sortKey="size"
            sort={sort}
            onSortKey={onSortKey}
            className="text-right"
          />
        </tr>
      </thead>
      <tbody>
        {list.slice(0, shown).map((f, i) => (
          <tr
            key={f.id}
            tabIndex={0}
            role="button"
            className="cursor-pointer border-b border-divider outline-none transition-colors hover:bg-bg2 focus-visible:bg-bg2"
            onClick={() => onOpen(i)}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault()
                onOpen(i)
              }
            }}
          >
            <td className="py-2 pr-4 pl-2">
              <div className="flex min-w-0 items-center gap-3">
                <Thumb file={f} boxClass="h-8 w-8 shrink-0 rounded-md" iconClass="text-[16px]" fit="contain" />
                <span className="truncate">{f.name}</span>
                {f.favorite && (
                  <Mi n="star" className="shrink-0 text-[15px]" style={{ color: STAR_COLOR }} />
                )}
              </div>
            </td>
            <td className="hidden w-[170px] py-2 text-text2 whitespace-nowrap sm:table-cell">
              {fmtDate(fileDate(f))}
            </td>
            <td className="w-[110px] py-2 pr-2 text-right text-text2 whitespace-nowrap">
              {fmtSize(f.size)}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
