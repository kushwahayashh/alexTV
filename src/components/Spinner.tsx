/**
 * Apple-style activity spinner: a ring of tapered spokes with a bright leader
 * that steps around the circle, leaving a trailing fade. Mirrors Flutter's
 * CupertinoActivityIndicator (used on the Flutter Home loading state) so the
 * web prototype and the TV app show the same loader.
 *
 * Pure CSS — the spokes are 12 static bars at increasing opacity; a stepped
 * rotation of the whole ring produces the classic sequential-fade spin.
 */

const SPOKES = 12

export function Spinner({ size = 36 }: { size?: number }) {
  return (
    <div className="spinner" style={{ width: size, height: size }} role="status" aria-label="Loading">
      {Array.from({ length: SPOKES }).map((_, i) => (
        <span
          key={i}
          className="spinner__spoke"
          style={{
            transform: `rotate(${i * (360 / SPOKES)}deg)`,
            // Trailing fade: the leader is brightest, each older spoke dimmer.
            opacity: (i + 1) / SPOKES,
          }}
        />
      ))}
    </div>
  )
}
