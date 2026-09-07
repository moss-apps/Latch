import { useEffect, type ReactNode } from "react"
import { createPortal } from "react-dom"
import { Mi } from "@/components/Mi"

interface DialogProps {
  open: boolean
  onClose: () => void
  title: string
  children: ReactNode
}

export function Dialog({ open, onClose, title, children }: DialogProps) {
  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      window.removeEventListener("keydown", onKey)
      document.body.style.overflow = prev
    }
  }, [open, onClose])

  if (!open) return null

  return createPortal(
    <div
      className="fixed inset-0 z-50 grid place-items-center p-4"
      role="dialog"
      aria-modal="true"
      aria-label={title}
    >
      <div
        className="absolute inset-0 bg-black/40"
        onClick={onClose}
        aria-hidden="true"
      />
      <div className="relative flex max-h-[min(640px,85dvh)] w-full max-w-[440px] flex-col rounded-2xl border border-divider bg-background shadow-2xl">
        <header className="flex h-14 shrink-0 items-center justify-between border-b border-divider px-5">
          <h2 className="text-base font-bold">{title}</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close settings"
            className="grid size-9 place-items-center rounded-lg text-text2 transition-colors hover:bg-bg2 hover:text-text"
          >
            <Mi n="close" className="text-[20px]" />
          </button>
        </header>
        <div className="overflow-y-auto p-5">{children}</div>
      </div>
    </div>,
    document.body,
  )
}
