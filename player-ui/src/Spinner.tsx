/**
 * Apple-style activity spinner: a ring of tapered spokes with a bright leader
 * that steps around the circle, leaving a trailing fade. Mirrors Flutter's
 * CupertinoActivityIndicator and the native player's AppleSpinner so this
 * sandbox, the web prototype and the TV app all show the same loader.
 *
 * Pure CSS — the spokes are 12 static bars at increasing opacity; a stepped
 * rotation of the whole ring produces the classic sequential-fade spin.
 */

const SPOKES = 12

// Trailing fade rendered as a grey→white color ramp (no transparency): the
// leader is pure white, each older spoke steps back toward the grey base.
const BASE_GREY = [139, 139, 148] // #8b8b94
const LEADER_WHITE = [255, 255, 255]

function spokeColor(t: number) {
  const c = BASE_GREY.map((base, i) => Math.round(base + (LEADER_WHITE[i] - base) * t))
  return `rgb(${c[0]}, ${c[1]}, ${c[2]})`
}

export function Spinner({ size = 36 }: { size?: number }) {
  return (
    <div className="spinner" style={{ width: size, height: size }} role="status" aria-label="Loading">
      {Array.from({ length: SPOKES }).map((_, i) => (
        <span
          key={i}
          className="spinner__spoke"
          style={{
            transform: `rotate(${i * (360 / SPOKES)}deg)`,
            // Leader (t=1) is white; older spokes ramp down to grey. Fully opaque.
            background: spokeColor((i + 1) / SPOKES),
          }}
        />
      ))}
    </div>
  )
}
