import Foundation
import AVFoundation
import CoreGraphics

/// Phase 3 — the render spec of record (blueprint §7.7). Values here are HARD
/// requirements, not suggestions; tests assert against them.
struct RenderSpec: Sendable, Equatable {
    enum Preset: String, Sendable, CaseIterable {
        /// Practical for QR/email/AirDrop — lands the 8–15 MB window for 8–10 s.
        case fastShare
        /// The master the operator keeps.
        case bestQuality

        /// H.264 average bitrate. 1080×1920@30: fastShare ≈ 8 Mbps ⇒ ~10 MB
        /// for 10 s; bestQuality ≈ 14 Mbps.
        var averageBitrate: Int {
            switch self {
            case .fastShare:   8_000_000
            case .bestQuality: 14_000_000
            }
        }
    }

    /// Output size. Default 1080×1920 (9:16 portrait).
    var width: Int = 1080
    var height: Int = 1920
    /// Output frame rate.
    var fps: Int = 30
    var preset: Preset = .fastShare
    /// Hard cap on rendered duration (blueprint: 15 s unless overridden).
    var maxDurationSeconds: Double = 15

    static let `default` = RenderSpec()

    var size: CGSize { CGSize(width: width, height: height) }
    var frameDuration: CMTime { CMTime(value: 1, timescale: CMTimeScale(fps)) }

    /// AVAssetWriter video settings for this spec (H.264 via VideoToolbox).
    var writerVideoSettings: [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: preset.averageBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ]
    }
}

/// Phase 3 timeline: a single full-range 1× segment. Phase 4 replaces this
/// with the real multi-segment model (speed regions, reverse, ramps) — the
/// engine already consumes `RenderTimeline`, so Phase 4 swaps the builder,
/// not the export path.
struct RenderTimeline: Sendable, Equatable {
    struct Segment: Sendable, Equatable {
        /// Source time range within the raw capture.
        var sourceStart: Double
        var sourceDuration: Double
        /// Playback speed multiplier (1 = realtime, 0.25 = 4× slow-mo).
        var speed: Double
        var reversed: Bool = false
    }

    var segments: [Segment]

    /// Whole-clip 1× passthrough of the source.
    static func fullRange(duration: Double) -> RenderTimeline {
        RenderTimeline(segments: [Segment(sourceStart: 0, sourceDuration: duration, speed: 1)])
    }

    /// Output duration implied by the segments (source time ÷ speed).
    var outputDuration: Double {
        segments.reduce(0) { $0 + $1.sourceDuration / max($1.speed, 0.0001) }
    }
}
