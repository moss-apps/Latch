import { useEffect, useRef, useState } from "react"
import type { FormEvent } from "react"
import { Mi } from "@/components/Mi"
import { StatusLine, type StatusKind } from "@/components/StatusLine"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { api, ApiError } from "@/lib/api"

export const DEFAULT_UNLOCK_SUB =
  "Enter your vault password to browse and export the backup on this machine."

export function UnlockPane({
  note,
  onUnlocked,
  onPair,
}: {
  note: string
  onUnlocked: () => void
  onPair: () => void
}) {
  const [credential, setCredential] = useState("")
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [status, setStatus] = useState<{ kind: StatusKind; text: string }>({
    kind: "",
    text: "",
  })
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    inputRef.current?.focus()
  }, [])

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (!credential) {
      setStatus({ kind: "err", text: "Type your vault password first." })
      return
    }
    setBusy(true)
    setStatus({ kind: "busy", text: "Unlocking…" })
    try {
      await api("/api/unlock", { credential })
      setCredential("")
      onUnlocked()
    } catch (err) {
      setBusy(false)
      const msg =
        err instanceof ApiError && err.status === 401
          ? "Wrong vault password. Try your password again."
          : (err as Error).message || "Unlock failed."
      setStatus({ kind: "err", text: msg })
    }
  }

  return (
    <div className="grid h-full place-items-center px-6 py-10">
      <form className="w-full max-w-[400px]" onSubmit={submit} noValidate>
        <div className="mb-6 grid size-14 place-items-center rounded-full bg-bg2">
          <Mi n="lock" className="text-[28px] text-text2" />
        </div>
        <h1 className="text-2xl font-bold tracking-tight">Unlock your backup</h1>
        <p className="mt-2 text-sm leading-relaxed text-text2">{note}</p>
        <div className="mt-6">
          <label htmlFor="credential" className="mb-1.5 block text-sm font-medium">
            Vault password
          </label>
          <div className="relative">
            <Input
              ref={inputRef}
              id="credential"
              type={show ? "text" : "password"}
              autoComplete="off"
              placeholder="Your vault password"
              className="h-11 rounded-xl border-transparent bg-bg2 pl-4 pr-11"
              value={credential}
              onChange={(e) => setCredential(e.target.value)}
            />
            <button
              type="button"
              className="absolute right-1 top-1/2 grid size-9 -translate-y-1/2 place-items-center rounded-lg text-text3 transition-colors hover:text-text"
              aria-label={show ? "Hide password" : "Show password"}
              aria-pressed={show}
              onClick={() => {
                setShow(!show)
                inputRef.current?.focus()
              }}
            >
              <Mi n={show ? "visibility_off" : "visibility"} className="text-[18px]" />
            </button>
          </div>
        </div>
        <Button
          type="submit"
          disabled={busy}
          className="mt-4 h-11 w-full rounded-xl text-[15px]"
        >
          <Mi n="lock_open" className="text-[18px]" />
          Unlock
        </Button>
        <div className="mt-4">
          <StatusLine kind={status.kind} text={status.text} />
        </div>
        <p className="mt-6 text-sm text-text2">
          Want a fresh backup instead?{" "}
          <button
            type="button"
            className="font-medium text-brand underline-offset-4 hover:underline"
            onClick={onPair}
          >
            Pair your phone
          </button>
          .
        </p>
      </form>
    </div>
  )
}
