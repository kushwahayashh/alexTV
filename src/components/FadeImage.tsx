import { useState, type ImgHTMLAttributes } from 'react'

/**
 * Image that stays invisible until fully loaded, then fades in smoothly.
 * Avoids the "half-loaded" flash seen on slow connections.
 */
export function FadeImage({
  className,
  ...props
}: ImgHTMLAttributes<HTMLImageElement>) {
  const [loaded, setLoaded] = useState(false)

  return (
    <img
      {...props}
      className={`${className ?? ''}${loaded ? ' fade-img--loaded' : ''}`}
      style={{ opacity: loaded ? undefined : 0 }}
      onLoad={() => setLoaded(true)}
    />
  )
}
