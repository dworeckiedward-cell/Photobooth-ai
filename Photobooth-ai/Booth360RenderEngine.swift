import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import os.log

/// Phase 3 — the native on-device render core (blueprint §7): raw capture →
/// AVMutableComposition (+timeline) → AVAssetReader/AVAssetWriter (H.264 via
/// VideoToolbox) → spec-correct MP4.
///
/// Pure and UI-free by design: no AppState, no job bookkeeping — the client
/// wraps it. That's what makes the whole pipeline testable in the simulator
/// against a synthetic input clip (blueprint §12).
enum Booth360RenderEngineError: Error, LocalizedError {
    case noVideoTrack
    case cannotAddTrack
    case readerFailed(String)
    case writerFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:       "The recording has no video track."
        case .cannotAddTrack:     "Couldn't assemble the composition track."
        case .readerFailed(let m): "Reading the recording failed: \(m)"
        case .writerFailed(let m): "Writing the video failed: \(m)"
        case .cancelled:          "Render cancelled."
        }
    }
}

struct Booth360RenderEngine: Sendable {
    private static let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "RenderEngine")

    // MARK: - Composition assembly (tested directly in Gate A)

    /// Build the composition + video composition for a timeline over `asset`.
    /// Phase 3 consumes 1× full-range timelines; Phase 4's multi-segment
    /// speed/reverse model plugs in here via `scaleTimeRange`.
    /// Build the composition + video composition for a timeline over `asset`.
    /// Reversed segments consume pre-generated upright intermediates
    /// (`reversedIntermediates`, keyed by segment index — see `render`).
    ///
    /// One composition video track hosts inserts from BOTH the raw asset and
    /// the intermediates; a single layer instruction carries a time-keyed
    /// aspect-fill transform per insert (`setTransform(_:at:)`).
    static func buildComposition(
        asset: AVAsset,
        timeline: RenderTimeline,
        spec: RenderSpec,
        reversedIntermediates: [Int: AVAsset] = [:],
        intro: AVAsset? = nil,
        outro: AVAsset? = nil
    ) async throws -> (composition: AVMutableComposition, videoComposition: AVMutableVideoComposition) {
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw Booth360RenderEngineError.noVideoTrack
        }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let sourceNatural = try await sourceVideo.load(.naturalSize)
        let sourceTransform = try await sourceVideo.load(.preferredTransform)
        let sourceDuration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw Booth360RenderEngineError.cannotAddTrack }
        let audioTrack = sourceAudio == nil ? nil : composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        var cursor = CMTime.zero

        /// Insert a whole standalone clip (intro/outro) at the cursor with its
        /// own aspect-fill transform key. Its audio rides along when present.
        @Sendable func insertStandalone(_ clip: AVAsset) async throws {
            guard let clipVideo = try await clip.loadTracks(withMediaType: .video).first else { return }
            let clipDuration = try await clip.load(.duration)
            let clipNatural = try await clipVideo.load(.naturalSize)
            let clipTransform = try await clipVideo.load(.preferredTransform)
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: clipDuration), of: clipVideo, at: cursor
            )
            if let audioTrack {
                if let clipAudio = try await clip.loadTracks(withMediaType: .audio).first {
                    try? audioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: clipDuration), of: clipAudio, at: cursor
                    )
                } else {
                    audioTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: clipDuration))
                }
            }
            layerInstruction.setTransform(
                aspectFillTransform(sourceSize: clipNatural, preferred: clipTransform, spec: spec),
                at: cursor
            )
            cursor = CMTimeAdd(cursor, clipDuration)
        }

        if let intro { try await insertStandalone(intro) }

        for (index, segment) in timeline.segments.enumerated() {
            let segmentOutputStart = cursor

            if segment.reversed, let intermediate = reversedIntermediates[index] {
                guard let revTrack = try await intermediate.loadTracks(withMediaType: .video).first else {
                    throw Booth360RenderEngineError.noVideoTrack
                }
                let revDuration = try await intermediate.load(.duration)
                let revNatural = try await revTrack.load(.naturalSize)
                try videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: revDuration), of: revTrack, at: cursor
                )
                var insertedDuration = revDuration
                if segment.speed != 1 {
                    let scaled = CMTime(
                        seconds: revDuration.seconds / max(segment.speed, 0.0001),
                        preferredTimescale: 600
                    )
                    videoTrack.scaleTimeRange(
                        CMTimeRange(start: cursor, duration: revDuration), toDuration: scaled
                    )
                    insertedDuration = scaled
                }
                // Reversed spans are silent (soundtrack arrives in Phase 5).
                if let audioTrack {
                    audioTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: insertedDuration))
                }
                layerInstruction.setTransform(
                    aspectFillTransform(sourceSize: revNatural, preferred: .identity, spec: spec),
                    at: segmentOutputStart
                )
                cursor = CMTimeAdd(cursor, insertedDuration)
            } else {
                let start = CMTime(seconds: segment.sourceStart, preferredTimescale: 600)
                let rawDuration = CMTime(seconds: segment.sourceDuration, preferredTimescale: 600)
                let clampedEnd = min(CMTimeAdd(start, rawDuration), sourceDuration)
                let range = CMTimeRange(start: start, end: clampedEnd)
                guard range.duration > .zero else { continue }

                try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
                if let audioTrack, let sourceAudio {
                    try? audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
                }
                var insertedDuration = range.duration
                if segment.speed != 1 {
                    let scaled = CMTime(
                        seconds: range.duration.seconds / max(segment.speed, 0.0001),
                        preferredTimescale: 600
                    )
                    let inserted = CMTimeRange(start: cursor, duration: range.duration)
                    videoTrack.scaleTimeRange(inserted, toDuration: scaled)
                    audioTrack?.scaleTimeRange(inserted, toDuration: scaled)
                    insertedDuration = scaled
                }
                layerInstruction.setTransform(
                    aspectFillTransform(sourceSize: sourceNatural, preferred: sourceTransform, spec: spec),
                    at: segmentOutputStart
                )
                cursor = CMTimeAdd(cursor, insertedDuration)
            }
        }

        if let outro { try await insertStandalone(outro) }

        // Hard duration cap (spec of record).
        let cap = CMTime(seconds: spec.maxDurationSeconds, preferredTimescale: 600)
        if composition.duration > cap {
            composition.removeTimeRange(CMTimeRange(start: cap, end: composition.duration))
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = spec.size
        videoComposition.frameDuration = spec.frameDuration
        videoComposition.instructions = [instruction]

        return (composition, videoComposition)
    }

    /// Aspect-FILL (crop, never stretch) of a source frame into spec.size.
    private static func aspectFillTransform(
        sourceSize: CGSize, preferred: CGAffineTransform, spec: RenderSpec
    ) -> CGAffineTransform {
        let oriented = sourceSize.applying(preferred)
        let effective = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let scale = max(spec.size.width / effective.width, spec.size.height / effective.height)
        let scaledSize = CGSize(width: effective.width * scale, height: effective.height * scale)
        let offset = CGPoint(
            x: (spec.size.width - scaledSize.width) / 2,
            y: (spec.size.height - scaledSize.height) / 2
        )
        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        return transform
    }

    // MARK: - Soundtrack (Phase 5, §7.6)

    /// Add `soundtrack` as its own audio track trimmed to the composition,
    /// with fade-in/out ramps; ORIGINAL audio tracks are muted (booth output
    /// convention — reversed spans are silent anyway). Returns the mix the
    /// export's audio reader must consume.
    static func addSoundtrack(
        _ soundtrack: AVAsset,
        to composition: AVMutableComposition,
        fadeSeconds: Double = 0.8
    ) async throws -> AVAudioMix? {
        guard let sourceTrack = try await soundtrack.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        let target = composition.duration
        guard target > .zero,
              let musicTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { return nil }

        // Trim (or loop) the soundtrack to the video length.
        let soundtrackDuration = try await soundtrack.load(.duration)
        var written = CMTime.zero
        while written < target {
            let remaining = CMTimeSubtract(target, written)
            let chunk = min(soundtrackDuration, remaining)
            try musicTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: chunk), of: sourceTrack, at: written
            )
            written = CMTimeAdd(written, chunk)
        }

        let mix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []

        // Music: fade in over the first `fadeSeconds`, out over the last.
        let music = AVMutableAudioMixInputParameters(track: musicTrack)
        let fade = CMTime(seconds: min(fadeSeconds, target.seconds / 2), preferredTimescale: 600)
        music.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1,
                            timeRange: CMTimeRange(start: .zero, duration: fade))
        music.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0,
                            timeRange: CMTimeRange(start: CMTimeSubtract(target, fade), duration: fade))
        params.append(music)

        // Original capture audio: muted when a soundtrack is present.
        for track in composition.tracks(withMediaType: .audio) where track != musicTrack {
            let original = AVMutableAudioMixInputParameters(track: track)
            original.setVolume(0, at: .zero)
            params.append(original)
        }

        mix.inputParameters = params
        return mix
    }

    // MARK: - Export (reader → writer, VideoToolbox H.264)

    /// Export the composition to `outputURL` per spec. Streams frame-by-frame
    /// (autoreleasepool, no full-asset loads — blueprint §8 memory discipline).
    /// `progress` is called on no particular thread with 0…1.
    static func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        spec: RenderSpec,
        to outputURL: URL,
        overlay: CGImage? = nil,
        audioMix: AVAudioMix? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let reader = try AVAssetReader(asset: composition)
        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: composition.tracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        readerOutput.videoComposition = videoComposition
        guard reader.canAdd(readerOutput) else {
            throw Booth360RenderEngineError.readerFailed("cannot add video output")
        }
        reader.add(readerOutput)

        // Audio passthrough decode → AAC re-encode when the capture has sound.
        let audioTracks = composition.tracks(withMediaType: .audio)
        var audioReaderOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM
            ])
            out.audioMix = audioMix   // Phase 5: soundtrack fades + original mute
            if reader.canAdd(out) { reader.add(out); audioReaderOutput = out }
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: spec.writerVideoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw Booth360RenderEngineError.writerFailed("cannot add video input")
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) { writer.add(input); audioInput = input }
        }

        // Phase 5 — overlay compositing. CoreAnimationTool does NOT run in the
        // reader→writer path, so a static overlay is composited per frame on
        // the GPU via CoreImage into pool buffers (adaptor append).
        let adaptor: AVAssetWriterInputPixelBufferAdaptor? = overlay == nil ? nil :
            AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: spec.width,
                    kCVPixelBufferHeightKey as String: spec.height,
                ]
            )
        let overlayCI: CIImage? = overlay.map { cg in
            let img = CIImage(cgImage: cg)
            // Scale (aspect-validated upstream) to the render size.
            let sx = spec.size.width / img.extent.width
            let sy = spec.size.height / img.extent.height
            return img.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        let ciContext = CIContext()

        guard reader.startReading() else {
            throw Booth360RenderEngineError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard writer.startWriting() else {
            throw Booth360RenderEngineError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = max(composition.duration.seconds, 0.001)


        // Video pump.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "boothify.render.video")
            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    if Task.isCancelled {
                        reader.cancelReading()
                        videoInput.markAsFinished()
                        cont.resume(throwing: Booth360RenderEngineError.cancelled)
                        return
                    }
                    var stop = false
                    autoreleasepool {
                        if let sample = readerOutput.copyNextSampleBuffer() {
                            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                            progress?(min(pts.seconds / totalSeconds, 1))
                            if let adaptor, let overlayCI,
                               let sourceBuffer = CMSampleBufferGetImageBuffer(sample) {
                                // Composite overlay over the frame.
                                let frame = CIImage(cvPixelBuffer: sourceBuffer)
                                let composited = overlayCI.composited(over: frame)
                                var outBuffer: CVPixelBuffer?
                                if let pool = adaptor.pixelBufferPool {
                                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
                                }
                                if let outBuffer {
                                    ciContext.render(composited, to: outBuffer)
                                    if !adaptor.append(outBuffer, withPresentationTime: pts) { stop = true }
                                } else {
                                    stop = true
                                }
                            } else if !videoInput.append(sample) {
                                stop = true
                            }
                        } else {
                            stop = true
                        }
                    }
                    if stop {
                        videoInput.markAsFinished()
                        if reader.status == .failed {
                            cont.resume(throwing: Booth360RenderEngineError.readerFailed(
                                reader.error?.localizedDescription ?? "unknown"))
                        } else if writer.status == .failed {
                            cont.resume(throwing: Booth360RenderEngineError.writerFailed(
                                writer.error?.localizedDescription ?? "unknown"))
                        } else {
                            cont.resume()
                        }
                        return
                    }
                }
            }
        }

        // Audio pump (after video completes — output duration is video-bound).
        if let audioReaderOutput, let audioInput {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let queue = DispatchQueue(label: "boothify.render.audio")
                audioInput.requestMediaDataWhenReady(on: queue) {
                    while audioInput.isReadyForMoreMediaData {
                        var stop = false
                        autoreleasepool {
                            if let sample = audioReaderOutput.copyNextSampleBuffer() {
                                if !audioInput.append(sample) { stop = true }
                            } else {
                                stop = true
                            }
                        }
                        if stop {
                            audioInput.markAsFinished()
                            cont.resume()
                            return
                        }
                    }
                }
            }
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw Booth360RenderEngineError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        if reader.status == .failed {
            throw Booth360RenderEngineError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        progress?(1)
        Self.log.info("export complete → \(outputURL.lastPathComponent, privacy: .public)")
    }

    /// Phase 5 — optional decorations layered onto a render (§7.5–7.6).
    struct RenderDecorations: Sendable {
        var overlay: CGImage? = nil
        var introURL: URL? = nil
        var outroURL: URL? = nil
        var soundtrackURL: URL? = nil
        var soundtrackFadeSeconds: Double = 0.8

        init() {}
    }

    /// Convenience: full pipeline (composition + export) from a raw file.
    /// Reversed segments are pre-flattened into upright intermediates here
    /// (reverse doubles cost — expected, blueprint §7.3); temp files are
    /// cleaned up after export.
    static func render(
        input: URL,
        timeline: RenderTimeline? = nil,
        spec: RenderSpec = .default,
        decorations: RenderDecorations = RenderDecorations(),
        to outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds
        let effectiveTimeline = timeline ?? .fullRange(duration: duration)

        var intermediates: [Int: AVAsset] = [:]
        var tempURLs: [URL] = []
        defer { tempURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        for (index, segment) in effectiveTimeline.segments.enumerated() where segment.reversed {
            let range = CMTimeRange(
                start: CMTime(seconds: segment.sourceStart, preferredTimescale: 600),
                duration: CMTime(seconds: segment.sourceDuration, preferredTimescale: 600)
            )
            let url = try await Booth360ReverseEncoder.reversedIntermediate(input: input, range: range)
            tempURLs.append(url)
            intermediates[index] = AVURLAsset(url: url)
        }

        let (composition, videoComposition) = try await buildComposition(
            asset: asset, timeline: effectiveTimeline, spec: spec,
            reversedIntermediates: intermediates,
            intro: decorations.introURL.map { AVURLAsset(url: $0) },
            outro: decorations.outroURL.map { AVURLAsset(url: $0) }
        )

        var audioMix: AVAudioMix?
        if let soundtrackURL = decorations.soundtrackURL {
            audioMix = try await addSoundtrack(
                AVURLAsset(url: soundtrackURL), to: composition,
                fadeSeconds: decorations.soundtrackFadeSeconds
            )
        }

        try await export(
            composition: composition, videoComposition: videoComposition,
            spec: spec, to: outputURL,
            overlay: decorations.overlay,
            audioMix: audioMix,
            progress: progress
        )
    }
}
