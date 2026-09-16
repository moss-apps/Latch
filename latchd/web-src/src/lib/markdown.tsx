// Minimal markdown renderer for the embedded legal texts: headings,
// bold/italic/code spans, links, lists, rules, quotes. No dependencies —
// the source is trusted (shipped inside the latchd binary) and the docs
// stick to this subset, so a full parser is not worth the weight.
import type { JSX } from "react"

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function inline(s: string): string {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, "$1<em>$2</em>")
    .replace(
      /\[([^\]]+)\]\(([^)\s]+)\)/g,
      '<a href="$2" target="_blank" rel="noreferrer">$1</a>',
    )
}

export function mdToHtml(md: string): string {
  const lines = md.replace(/\r\n/g, "\n").split("\n")
  const out: string[] = []
  let list: "ul" | "ol" | null = null
  let para: string[] = []
  const closePara = () => {
    if (para.length) {
      out.push(`<p>${inline(para.join(" "))}</p>`)
      para = []
    }
  }
  const closeList = () => {
    if (list) {
      out.push(`</${list}>`)
      list = null
    }
  }
  for (const raw of lines) {
    const line = raw.trimEnd()
    if (!line.trim()) {
      closePara()
      closeList()
      continue
    }
    const h = /^(#{1,4})\s+(.*)$/.exec(line)
    if (h) {
      closePara()
      closeList()
      const level = h[1].length
      out.push(`<h${level}>${inline(h[2])}</h${level}>`)
      continue
    }
    if (/^(-{3,}|\*{3,})$/.test(line.trim())) {
      closePara()
      closeList()
      out.push("<hr/>")
      continue
    }
    const q = /^>\s?(.*)$/.exec(line)
    if (q) {
      closePara()
      closeList()
      out.push(`<blockquote>${inline(q[1])}</blockquote>`)
      continue
    }
    const ul = /^[-*]\s+(.*)$/.exec(line)
    if (ul) {
      closePara()
      if (list !== "ul") {
        closeList()
        out.push("<ul>")
        list = "ul"
      }
      out.push(`<li>${inline(ul[1])}</li>`)
      continue
    }
    const ol = /^\d+\.\s+(.*)$/.exec(line)
    if (ol) {
      closePara()
      if (list !== "ol") {
        closeList()
        out.push("<ol>")
        list = "ol"
      }
      out.push(`<li>${inline(ol[1])}</li>`)
      continue
    }
    closeList()
    para.push(line.trim())
  }
  closePara()
  closeList()
  return out.join("\n")
}

export function Markdown({
  source,
  className = "",
}: {
  source: string
  className?: string
}): JSX.Element {
  return (
    <div
      className={`md ${className}`.trim()}
      dangerouslySetInnerHTML={{ __html: mdToHtml(source) }}
    />
  )
}
