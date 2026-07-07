import SwiftUI
import AVFoundation

/// Muted, seamlessly-looping, aspect-fill video for ambient tile backgrounds
/// (bento "Your booth" tile). Presentation-only: no controls, no audio, no
/// display-sleep prevention. Callers must provide a static fallback for
/// Reduce Motion and for a missing asset — this view assumes a valid URL.
struct AmbientVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerContainerView {
        PlayerContainerView(url: url)
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.detach()
    }

    final class PlayerContainerView: UIView {
        private let player: AVQueuePlayer
        private var foregroundObserver: NSObjectProtocol?

        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        init(url: URL) {
            player = AmbientPlayerCache.player(for: url)
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            player.play()

            // iOS pauses AVPlayer on backgrounding; resume on return.
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.player.play()
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// Tab switched away: pause decode (battery), keep the player and its
        /// position alive in the cache — returning resumes the SAME frame
        /// instantly, with zero load-in.
        func detach() {
            player.pause()
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
            foregroundObserver = nil
        }

        deinit {
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
        }
    }
}

/// App-lifetime cache of ambient loop players. One player per clip URL —
/// screens attach/detach their layers, so switching sections never reloads
/// or restarts the footage.
@MainActor
enum AmbientPlayerCache {
    private static var players: [URL: (player: AVQueuePlayer, looper: AVPlayerLooper)] = [:]

    static func player(for url: URL) -> AVQueuePlayer {
        if let cached = players[url] { return cached.player }
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        // Ambient decoration must never keep the screen awake — the kiosk
        // keep-awake is KioskManager's job, not this loop's.
        player.preventsDisplaySleepDuringVideoPlayback = false
        players[url] = (player, looper)
        return player
    }
}
