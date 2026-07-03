import { useFocusable } from '../focus/FocusEngine'

/**
 * D-pad navigable pill button for the hero header bar. Registered as a
 * focusable header item so it's reached by pressing Up from the hero.
 * Mock for now — selecting it does nothing.
 */
export function HeaderButton({ label }: { label: string }) {
  const { ref, focused } = useFocusable({
    isHeader: true,
    onSelect: () => {},
    onFocus: () => {
      const el = document.querySelector('.home') as HTMLElement | null
      el?.scrollTo({ top: 0, behavior: 'smooth' })
    },
  })

  return (
    <button
      ref={ref as React.RefObject<HTMLButtonElement>}
      className={`header-btn${focused ? ' header-btn--focused' : ''}`}
      type="button"
    >
      {label}
    </button>
  )
}
