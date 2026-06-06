import AVFoundation
import Foundation
import Observation

@Observable
final class PreviewAudioPlayer {
    private var player: AVPlayer?

    var isPlaying = false
    var nowPlayingTitle = ""

    func play(url: URL, title: String) {
        configureAudioSession()
        player = AVPlayer(url: url)
        player?.play()
        nowPlayingTitle = title
        isPlaying = true
    }

    func stop() {
        player?.pause()
        player = nil
        nowPlayingTitle = ""
        isPlaying = false
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // The app can still attempt playback; surface errors through AVPlayer state if needed later.
        }
    }
}
