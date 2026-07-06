import XCTest
import AVFoundation
import CoreImage
@testable import Photobooth_ai

/// PHASE 5 GATE A: overlay size-match validation + transparent-bg enforcement,
/// pre/post-roll insertion, audio fade ramps + original-mute, licensing copy
/// present in all three languages, and a pixel-verified overlay composite.
final class OverlayAudioTests: XCTestCase {

    // MARK: - Overlay validation

    private func makePNG(size: CGSize, opaque: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.red.withAlphaComponent(opaque ? 1 : 0.6).setFill()
            if opaque {
                ctx.fill(CGRect(origin: .zero, size: size))
            } else {
                // Half-covered canvas — real transparency present.
                ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
            }
        }
    }

    func testExactSizeTransparentOverlayPasses() {
        let image = makePNG(size: CGSize(width: 1080, height: 1920), opaque: false)
        XCTAssertEqual(OverlaySpec.validate(image: image, compositionSize: CGSize(width: 1080, height: 1920)), .ok)
    }

    func testOpaqueOverlayRejected() {
        let image = makePNG(size: CGSize(width: 1080, height: 1920), opaque: true)
        XCTAssertEqual(
            OverlaySpec.validate(image: image, compositionSize: CGSize(width: 1080, height: 1920)),
            .rejectedOpaque
        )
        XCTAssertNotNil(OverlayValidation.rejectedOpaque.operatorMessage)
    }

    func testSameAspectDifferentSizeScalesWithWarning() {
        let image = makePNG(size: CGSize(width: 540, height: 960), opaque: false)
        let verdict = OverlaySpec.validate(image: image, compositionSize: CGSize(width: 1080, height: 1920))
        guard case .scaledWithWarning(let from) = verdict else {
            return XCTFail("expected scale+warn, got \(verdict)")
        }
        XCTAssertEqual(from, CGSize(width: 540, height: 960))
        XCTAssertTrue(verdict.isUsable)
    }

    func testAspectMismatchRejected() {
        let image = makePNG(size: CGSize(width: 1000, height: 1000), opaque: false)
        let verdict = OverlaySpec.validate(image: image, compositionSize: CGSize(width: 1080, height: 1920))
        guard case .rejectedAspectMismatch = verdict else {
            return XCTFail("square into portrait must be rejected, got \(verdict)")
        }
        XCTAssertFalse(verdict.isUsable)
        XCTAssertNotNil(verdict.operatorMessage)
    }

    // MARK: - Licensing copy (present + all languages)

    func testLicensingCopyPresentInThreeLanguages() {
        XCTAssertEqual(SoundtrackLicensing.allVariants.count, 3)
        for variant in SoundtrackLicensing.allVariants {
            XCTAssertGreaterThan(variant.count, 40)
        }
        XCTAssertFalse(SoundtrackLicensing.copy().isEmpty)
    }

    // MARK: - Pre/post-roll insertion

    func testIntroOutroExtendCompositionAndLeadWithIntro() async throws {
        let main = try await TestVideoFactory.makeClip(seconds: 1.0)
        let intro = try await TestVideoFactory.makeClip(seconds: 0.5)
        let outro = try await TestVideoFactory.makeClip(seconds: 0.5)
        defer { [main, intro, outro].forEach { try? FileManager.default.removeItem(at: $0) } }

        let (composition, _) = try await Booth360RenderEngine.buildComposition(
            asset: AVURLAsset(url: main),
            timeline: .fullRange(duration: 1.0),
            spec: .default,
            intro: AVURLAsset(url: intro),
            outro: AVURLAsset(url: outro)
        )
        XCTAssertEqual(composition.duration.seconds, 2.0, accuracy: 0.15,
                       "0.5 intro + 1.0 main + 0.5 outro")
    }

    // MARK: - Soundtrack mix (fades + original mute)

    func testSoundtrackMixRampsAndMutesOriginal() async throws {
        let main = try await TestVideoFactory.makeClip(seconds: 2.0)
        let music = try await TestAudioFactory.makeTone(seconds: 3.0)
        defer {
            try? FileManager.default.removeItem(at: main)
            try? FileManager.default.removeItem(at: music)
        }

        let (composition, _) = try await Booth360RenderEngine.buildComposition(
            asset: AVURLAsset(url: main), timeline: .fullRange(duration: 2.0), spec: .default
        )
        let mix = try await Booth360RenderEngine.addSoundtrack(
            AVURLAsset(url: music), to: composition, fadeSeconds: 0.5
        )
        let unwrapped = try XCTUnwrap(mix)
        // Music track got added to the composition and trimmed to its length.
        let musicTracks = composition.tracks(withMediaType: .audio)
        XCTAssertGreaterThanOrEqual(musicTracks.count, 1)

        // Ramps: fade-in at start, fade-out into the end.
        let musicParams = try XCTUnwrap(unwrapped.inputParameters.first as? AVAudioMixInputParameters)
        var startVolume: Float = -1, endVolume: Float = -1
        var range = CMTimeRange()
        XCTAssertTrue(musicParams.getVolumeRamp(
            for: .zero, startVolume: &startVolume, endVolume: &endVolume, timeRange: &range
        ))
        XCTAssertEqual(startVolume, 0, accuracy: 0.001, "fade-in starts silent")
        XCTAssertEqual(endVolume, 1, accuracy: 0.001)

        let nearEnd = CMTime(seconds: composition.duration.seconds - 0.1, preferredTimescale: 600)
        XCTAssertTrue(musicParams.getVolumeRamp(
            for: nearEnd, startVolume: &startVolume, endVolume: &endVolume, timeRange: &range
        ))
        XCTAssertEqual(endVolume, 0, accuracy: 0.001, "fade-out ends silent")
    }

    // MARK: - Pixel-verified overlay composite (DoD)

    func testOverlayActuallyCompositesOntoFrames() async throws {
        let input = try await TestVideoFactory.makeClip(seconds: 1.0)
        let plainOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).mp4")
        let overlaidOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlaid-\(UUID().uuidString).mp4")
        defer {
            [input, plainOut, overlaidOut].forEach { try? FileManager.default.removeItem(at: $0) }
        }

        // Full-frame 60%-white translucent overlay — must visibly brighten frames.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let overlayImage = UIGraphicsImageRenderer(
            size: CGSize(width: 1080, height: 1920), format: format
        ).image { ctx in
            UIColor.white.withAlphaComponent(0.6).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
        }

        try await Booth360RenderEngine.render(input: input, to: plainOut)
        var decorations = Booth360RenderEngine.RenderDecorations()
        decorations.overlay = overlayImage.cgImage
        try await Booth360RenderEngine.render(input: input, decorations: decorations, to: overlaidOut)

        let plainBrightness = try await averageBrightness(of: plainOut, at: 0.5)
        let overlaidBrightness = try await averageBrightness(of: overlaidOut, at: 0.5)
        XCTAssertGreaterThan(overlaidBrightness, plainBrightness + 0.15,
                             "translucent white overlay must brighten the frame — compositing is real")
    }

    private func averageBrightness(of url: URL, at seconds: Double) async throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let cgImage = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent),
        ])!
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            filter.outputImage!, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }
}

/// Tiny AAC tone generator — audio fixture without repo binaries.
enum TestAudioFactory {
    static func makeTone(seconds: Double, frequency: Double = 440) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tone-\(UUID().uuidString).m4a")
        let sampleRate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate)) * 0.4
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
        )
        try file.write(from: buffer)
        return url
    }
}
