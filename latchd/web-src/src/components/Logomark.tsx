// The Latch dot-matrix L, currentColor so it follows the theme.
const DOTS = [
  [31.36, 527.1], [31.36, 422.57], [31.36, 318.03], [31.36, 620.34],
  [80.88, 224.8], [80.88, 120.26], [397.52, 224.8], [397.52, 120.26],
  [135.6, 31.36], [345.4, 31.36], [241.15, 31.36], [449.64, 527.1],
  [449.64, 422.57], [449.64, 318.03], [449.64, 620.34], [135.6, 318.03],
  [240.14, 318.03], [344.68, 318.03], [135.6, 620.34], [240.14, 620.34],
  [344.68, 620.34],
]

export function Logomark({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 481 652" aria-hidden="true" focusable="false">
      {DOTS.map(([cx, cy]) => (
        <circle key={`${cx}-${cy}`} cx={cx} cy={cy} r="31.36" fill="currentColor" />
      ))}
    </svg>
  )
}
