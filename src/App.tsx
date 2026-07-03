import { FocusProvider } from './focus/FocusEngine'
import { Home } from './screens/Home'

export default function App() {
  return (
    <FocusProvider onBack={() => console.log('BACK pressed')}>
      <Home />
    </FocusProvider>
  )
}
