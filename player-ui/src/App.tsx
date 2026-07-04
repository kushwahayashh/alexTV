import { VideoPlayer } from './VideoPlayer'

export function App() {
  return (
    <VideoPlayer
      title="Inception"
      duration={7695}
      onClose={() => console.log('close')}
    />
  )
}
