import Foundation
import AVFoundation
import CoreGraphics
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
    static func buildComposition(
        asset: AVAsset,
        timeline: RenderTimeline,
        spec: RenderSpec
    ) async throws -> (composition: AVMutableComposition, videoComposition: AVMutableVideoComposition) {
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw Booth360RenderEngineError.noVideoTrack
        }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let preferredTransform = try await sourceVideo.load(.preferredTransform)
        let sourceDuration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw Booth360RenderEngineError.cannotAddTrack }
        let audioTrack = sourceAudio == nil ? nil : composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )

        // Insert each segment back-to-back, then retime it (scaleTimeRange).
        var cursor = CMTime.zero
        for segment in timeline.segments {
            let start = CMTime(seconds: segment.sourceStart, preferredTimescale: 600)
            let rawDuration = CMTime(seconds: segment.sourceDuration, preferredTimescale: 600)
            // Clamp to the asset — a timeline must never read past the capture.
            let clampedEnd = min(CMTimeAdd(start, rawDuration), sourceDuration)
            let range = CMTimeRange(start: start, end: clampedEnd)
            guard range.duration > .zero else { continue }

            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
            if let audioTrack, let sourceAudio {
                try? audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
            }

            let scaledDuration = CMTime(
                seconds: segment.sourceDuration / max(segment.speed, 0.0001),
                preferredTimescale: 600
            )
            if segment.speed != 1 {
                let inserted = CMTimeRange(start: cursor, duration: range.duration)
                videoTrack.scaleTimeRange(inserted, toDuration: scaledDuration)
                audioTrack?.scaleTimeRange(inserted, toDuration: scaledDuration)
            }
            cursor = CMTimeAdd(cursor, segment.speed == 1 ? range.duration : scaledDuration)
        }

        // Hard duration cap (spec of record).
        let cap = CMTime(seconds: spec.maxDurationSeconds, preferredTimescale: 600)
        if composition.duration > cap {
            composition.removeTimeRange(CMTimeRange(start: cap, end: composition.duration))
        }

        // Aspect-fill transform: source (with its preferredTransform applied)
        // scaled to cover spec.size, centered. Stretching is an amateur tell —
        // we crop, never distort.
        let oriented = naturalSize.applying(preferredTransform)
        let sourceSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let scale = max(spec.size.width / sourceSize.width, spec.size.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let offset = CGPoint(
            x: (spec.size.width - scaledSize.width) / 2,
            y: (spec.size.height - scaledSize.height) / 2
        )
        var transform = preferredTransform
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = spec.size
        videoComposition.frameDuration = spec.frameDuration
        videoComposition.instructions = [instruction]

        return (composition, videoComposition)
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
                            if !videoInput.append(sample) { stop = true }
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

    /// Convenience: full pipeline (composition + export) from a raw file.
    static func render(
        input: URL,
        timeline: RenderTimeline? = nil,
        spec: RenderSpec = .default,
        to outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds
        let effectiveTimeline = timeline ?? .fullRange(duration: duration)
        let (composition, videoComposition) = try await buildComposition(
            asset: asset, timeline: effectiveTimeline, spec: spec
        )
        try await export(
            composition: composition, videoComposition: videoComposition,
            spec: spec, to: outputURL, progress: progress
        )
    }
}
