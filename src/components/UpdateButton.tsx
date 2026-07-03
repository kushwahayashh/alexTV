import { useFocusable } from '../focus/FocusEngine'

/**
 * D-pad navigable update button, ported from the Flutter UpdateButton widget.
 * Overlaid on the hero's top-right corner. Registered as a focusable so arrow
 * keys can reach it, but selecting it does nothing in the React prototype.
 */
export function UpdateButton() {
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
      className={`update-btn${focused ? ' update-btn--focused' : ''}`}
      type="button"
    >
      Update
    </button>
  )
}
