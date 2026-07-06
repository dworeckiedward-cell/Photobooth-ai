import XCTest
import AVFoundation
@testable import Photobooth_ai

/// PHASE 3 GATE A (blueprint): composition-assembly + export-settings tests;
/// synthetic-input export produces a valid, spec-correct MP4 in the simulator
/// (no camera, no mock); fps-fallback policy; responsiveness under render.
final class RenderEngineTests: XCTestCase {

    // MARK: - Export settings (spec of record)

    func testWriterSettingsMatchSpec() {
        let fast = RenderSpec(preset: .fastShare)
        let settings = fast.writerVideoSettings
        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .h264)
        XCTAssertEqual(settings[AVVideoWidthKey] as? Int, 1080)
        XCTAssertEqual(settings[AVVideoHeightKey] as? Int, 1920)
        let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoAverageBitRateKey] as? Int, 8_000_000)

        let best = RenderSpec(preset: .bestQuality)
        let bestCompression = best.writerVideoSettings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(bestCompression?[AVVideoAverageBitRateKey] as? Int, 14_000_000)
    }

    // MARK: - Frame-rate fallback policy (pure)

    func testFrameRateFallbackPolicy() {
        XCTAssertEqual(CameraController.bestFrameRate(supportedMaxRates: [30, 60, 120, 240], target: 120), 120)
        XCTAssertEqual(CameraController.bestFrameRate(supportedMaxRates: [30, 60], target: 120), 60,
                       "no rate reaches target → honest highest-available fallback")
        XCTAssertEqual(CameraController.bestFrameRate(supportedMaxRates: [240], target: 120), 240)
        XCTAssertNil(CameraController.bestFrameRate(supportedMaxRates: [], target: 120))
    }

    // MARK: - Composition assembly

    func testCompositionAssemblyFullRange() async throws {
        let input = try await TestVideoFactory.makeClip(seconds: 2.0)
        defer { try? FileManager.default.removeItem(at: input) }
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds

        let spec = RenderSpec.default
        let (composition, videoComposition) = try await Booth360RenderEngine.buildComposition(
            asset: asset, timeline: .fullRange(duration: duration), spec: spec
        )

        XCTAssertEqual(composition.duration.seconds, duration, accuracy: 0.1)
        XCTAssertEqual(composition.tracks(withMediaType: .video).count, 1)
        XCTAssertEqual(videoComposition.renderSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(videoComposition.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(videoComposition.instructions.count, 1)
    }

    func testCompositionHardDurationCap() async throws {
        let input = try await TestVideoFactory.makeClip(seconds: 2.0)
        defer { try? FileManager.default.removeItem(at: input) }
        let asset = AVURLAsset(url: input)

        var spec = RenderSpec.default
        spec.maxDurationSeconds = 1.0
        let (composition, _) = try await Booth360RenderEngine.buildComposition(
            asset: asset, timeline: .fullRange(duration: 2.0), spec: spec
        )
        XCTAssertLessThanOrEqual(composition.duration.seconds, 1.05,
                                 "15s-style hard cap must trim the composition")
    }

    func testTimelineOutputDurationMath() {
        let timeline = RenderTimeline(segments: [
            .init(sourceStart: 0, sourceDuration: 1.0, speed: 1),
            .init(sourceStart: 1.0, sourceDuration: 1.0, speed: 0.25), // 4× slow-mo → 4 s
        ])
        XCTAssertEqual(timeline.outputDuration, 5.0, accuracy: 0.001)
    }

    // MARK: - End-to-end synthetic export (THE Phase 3 DoD)

    func testEndToEndSyntheticExportProducesSpecCorrectMP4() async throws {
        let input = try await TestVideoFactory.makeClip(seconds: 2.0)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-e2e-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        try await Booth360RenderEngine.render(input: input, spec: .default, to: output)

        // File exists and is non-trivial. NOTE: solid-color synthetic frames
        // compress far below the 8 Mbps average (encoder doesn't pad trivial
        // content) — the real 8–15 MB window is asserted in Phase 7 against
        // realistic footage. Here we only prove "valid, non-empty, capped".
        let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 20_000, "output suspiciously small — likely empty/corrupt")
        XCTAssertLessThan(size, 8_000_000, "output far above the Fast Share budget")

        // Spec-correct: duration, dimensions, fps, codec.
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2.0, accuracy: 0.25)

        let track = try await asset.loadTracks(withMediaType: .video).first
        let unwrapped = try XCTUnwrap(track)
        let naturalSize = try await unwrapped.load(.naturalSize)
        XCTAssertEqual(naturalSize, CGSize(width: 1080, height: 1920))

        let fps = try await unwrapped.load(.nominalFrameRate)
        XCTAssertEqual(Double(fps), 30, accuracy: 2)

        let descriptions = try await unwrapped.load(.formatDescriptions)
        let codec = descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) }
        XCTAssertEqual(codec, kCMVideoCodecType_H264)
    }

    // MARK: - Responsiveness under concurrent renders (enqueue-N)

    func testMainActorStaysResponsiveDuringConcurrentRenders() async throws {
        // 3 concurrent renders of synthetic clips…
        var inputs: [URL] = []
        for _ in 0..<3 { inputs.append(try await TestVideoFactory.makeClip(seconds: 1.0)) }
        let outputs = inputs.map { _ in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("concurrent-\(UUID().uuidString).mp4")
        }
        defer {
            inputs.forEach { try? FileManager.default.removeItem(at: $0) }
            outputs.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        let renders = zip(inputs, outputs).map { input, output in
            Task { try await Booth360RenderEngine.render(input: input, spec: .default, to: output) }
        }

        // …while the MainActor keeps servicing hops promptly (kiosk stays alive).
        var worstHop: TimeInterval = 0
        for _ in 0..<20 {
            let start = Date()
            await MainActor.run { _ = start }
            worstHop = max(worstHop, Date().timeIntervalSince(start))
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertLessThan(worstHop, 0.5, "MainActor starved during renders — kiosk would freeze")

        for render in renders { _ = try await render.value }
        for output in outputs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "a concurrent render was dropped")
        }
    }
}
