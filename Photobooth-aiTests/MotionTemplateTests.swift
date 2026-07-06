import XCTest
import AVFoundation
import CoreImage
@testable import Photobooth_ai

/// PHASE 4 GATE A: timeline-model tests (segment math, speed→duration mapping,
/// reverse frame ordering, sub-segment step resolution, interpolation clamp);
/// each factory template yields its expected structure.
final class MotionTemplateTests: XCTestCase {

    // MARK: - Interpolation clamp (flag, don't fake)

    func testHeroSpeedClampedWhenCaptureFPSTooLow() {
        // 30 fps capture, 30 fps output → slowest honest speed is 1.0.
        let result = MotionTemplate.heroSlow.timeline(captureDuration: 3, captureFPS: 30, outputFPS: 30)
        XCTAssertTrue(result.clamped, "0.25 hero on a 30fps capture MUST clamp")
        XCTAssertEqual(result.heroSpeed, 1.0, accuracy: 0.001)
        // No segment may be slower than the honest floor.
        XCTAssertGreaterThanOrEqual(result.timeline.segments.map(\.speed).min() ?? 1, 1.0 - 0.001)
    }

    func testHeroSpeedHonestAt120FPS() {
        let result = MotionTemplate.heroSlow.timeline(captureDuration: 3, captureFPS: 120, outputFPS: 30)
        XCTAssertFalse(result.clamped)
        XCTAssertEqual(result.heroSpeed, 0.25, accuracy: 0.001)
        XCTAssertEqual(result.timeline.segments.map(\.speed).min() ?? 1, 0.25, accuracy: 0.02)
    }

    // MARK: - Template structure

    func testHeroSlowStructure() {
        let result = MotionTemplate.heroSlow.timeline(captureDuration: 3, captureFPS: 120)
        let segments = result.timeline.segments
        // lead + ramp steps + hero + ramp steps + tail — a real multi-segment timeline
        XCTAssertGreaterThanOrEqual(segments.count, 5)
        XCTAssertEqual(segments.first?.speed ?? 0, 1.0, accuracy: 0.001, "lead-in is realtime")
        XCTAssertEqual(segments.last?.speed ?? 0, 1.0, accuracy: 0.001, "exit is realtime")
        // Exactly ONE hero plateau (blueprint: one clear hero beat).
        let heroSegments = segments.filter { abs($0.speed - result.heroSpeed) < 0.001 && $0.sourceDuration > 0.5 }
        XCTAssertEqual(heroSegments.count, 1)
        // Source coverage is contiguous and inside the capture.
        var cursor = 0.0
        for segment in segments {
            XCTAssertEqual(segment.sourceStart, cursor, accuracy: 0.01, "segments must tile the source")
            cursor += segment.sourceDuration
        }
        XCTAssertEqual(cursor, 3.0, accuracy: 0.05)
    }

    func testReverseBounceStructure() {
        let result = MotionTemplate.reverseBounce.timeline(captureDuration: 2.5, captureFPS: 120)
        let segments = result.timeline.segments
        XCTAssertEqual(segments.count, 2)
        XCTAssertFalse(segments[0].reversed)
        XCTAssertTrue(segments[1].reversed)
        XCTAssertEqual(segments[0].sourceDuration, 2.5, accuracy: 0.001)
        XCTAssertEqual(segments[1].sourceDuration, 2.5, accuracy: 0.001)
    }

    func testLoopPromoEndsMatchForLooping() {
        let result = MotionTemplate.loopPromo.timeline(captureDuration: 3, captureFPS: 120)
        let segments = result.timeline.segments
        XCTAssertEqual(segments.first?.speed ?? 0, segments.last?.speed ?? -1, accuracy: 0.001,
                       "intro/outro speeds must match so the clip loops cleanly")
    }

    // MARK: - Ramp stepping (sub-segment resolution + monotonic easing)

    func testRampStepResolutionAndMonotonicity() {
        let ramp = MotionTemplate.rampSegments(
            from: 1.0, to: 0.25, sourceStart: 0, sourceDuration: 0.6, curve: .gentle
        )
        XCTAssertEqual(ramp.count, 6, "0.6s ramp at 0.1s steps = 6 sub-segments")
        // Speeds strictly decrease toward the hero and stay within bounds.
        for (a, b) in zip(ramp, ramp.dropFirst()) {
            XCTAssertGreaterThan(a.speed, b.speed)
        }
        XCTAssertLessThanOrEqual(ramp.map(\.speed).max() ?? 2, 1.0 + 0.001)
        XCTAssertGreaterThanOrEqual(ramp.map(\.speed).min() ?? 0, 0.25 - 0.001)
    }

    func testCurvesDiffer() {
        // The three presets must actually produce different mid-ramp speeds.
        let mid: (RampCurve) -> Double = { curve in
            MotionTemplate.rampSegments(from: 1, to: 0.25, sourceStart: 0, sourceDuration: 0.6, curve: curve)[2].speed
        }
        XCTAssertNotEqual(mid(.gentle), mid(.punchy), accuracy: 0.01)
        XCTAssertNotEqual(mid(.gentle), mid(.dramatic), accuracy: 0.01)
    }

    // MARK: - Speed → duration mapping through the real engine

    func testSlowMoSegmentStretchesOutputDuration() async throws {
        let input = try await TestVideoFactory.makeClip(seconds: 2.0)
        defer { try? FileManager.default.removeItem(at: input) }
        // 1s @1× + 1s @0.5 (2× slow) → 3s output.
        let timeline = RenderTimeline(segments: [
            .init(sourceStart: 0, sourceDuration: 1, speed: 1),
            .init(sourceStart: 1, sourceDuration: 1, speed: 0.5),
        ])
        let (composition, _) = try await Booth360RenderEngine.buildComposition(
            asset: AVURLAsset(url: input), timeline: timeline, spec: .default
        )
        XCTAssertEqual(composition.duration.seconds, 3.0, accuracy: 0.1)
    }

    // MARK: - Reverse frame ordering (real re-encode, real pixels)

    func testReversedIntermediateReversesFrameOrder() async throws {
        // Input hue ramps red(0)→blue-ish(0.66*0.9) over 1s; after reversing,
        // the FIRST output frame must look like the LAST input frame.
        let input = try await TestVideoFactory.makeClip(seconds: 1.0, fps: 30)
        defer { try? FileManager.default.removeItem(at: input) }

        let reversed = try await Booth360ReverseEncoder.reversedIntermediate(input: input)
        defer { try? FileManager.default.removeItem(at: reversed) }

        let inputEndHue = try await averageHue(of: input, at: 0.95)
        let reversedStartHue = try await averageHue(of: reversed, at: 0.05)
        XCTAssertEqual(reversedStartHue, inputEndHue, accuracy: 0.08,
                       "reversed clip must START with the input's LAST frames")

        let inputStartHue = try await averageHue(of: input, at: 0.05)
        let reversedEndHue = try await averageHue(of: reversed, at: 0.95)
        XCTAssertEqual(reversedEndHue, inputStartHue, accuracy: 0.08,
                       "reversed clip must END with the input's FIRST frames")

        // Same duration, same frame budget.
        let inDuration = try await AVURLAsset(url: input).load(.duration).seconds
        let outDuration = try await AVURLAsset(url: reversed).load(.duration).seconds
        XCTAssertEqual(inDuration, outDuration, accuracy: 0.15)
    }

    private func averageHue(of url: URL, at seconds: Double) async throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let cgImage = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])!
        let context = CIContext()
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            filter.outputImage!, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let color = UIColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var hue: CGFloat = 0
        color.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        return Double(hue)
    }
}
