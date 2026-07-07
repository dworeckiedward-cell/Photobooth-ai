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
        uiView.stop()
    }

    final class PlayerContainerView: UIView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var foregroundObserver: NSObjectProtocol?

        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        init(url: URL) {
            super.init(frame: .zero)
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.isMuted = true
            // Ambient decoration must never keep the screen awake — the
            // kiosk keep-awake is KioskManager's job, not this tile's.
            player.preventsDisplaySleepDuringVideoPlayback = false
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

        func stop() {
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
