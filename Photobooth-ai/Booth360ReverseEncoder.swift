import Foundation
import AVFoundation
import os.log

/// Phase 4 — real reverse playback (blueprint §7.3: "Reverse doubles cost
/// (AVAssetReader/Writer reverse re-encode) — expected; warn, keep it").
///
/// AVFoundation has no native reverse. We re-encode the requested range into
/// an UPRIGHT intermediate file with frames in reverse order:
/// - chunked (default 0.2 s of source per chunk, processed last→first) so
///   memory stays bounded (blueprint §8: never load a full clip),
/// - decoded via `AVAssetReaderVideoCompositionOutput` with an identity
///   composition at the ORIENTED size, so the intermediate carries no
///   preferredTransform baggage into the main composition,
/// - autoreleasepool around every chunk.
///
/// Audio is intentionally dropped (reversed audio is noise; Phase 5 lays the
/// soundtrack over the whole timeline anyway).
enum Booth360ReverseEncoder {
    private static let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "ReverseEncoder")

    static let chunkSeconds: Double = 0.2

    /// Re-encode `range` of `input` reversed, upright, into a temp .mov.
    /// Returns the intermediate URL (caller owns cleanup).
    static func reversedIntermediate(
        input: URL,
        range: CMTimeRange? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Booth360RenderEngineError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = naturalSize.applying(transform)
        let uprightSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let fps = try await track.load(.nominalFrameRate)
        let frameRate = fps > 0 ? Double(fps) : 30
        let assetDuration = try await asset.load(.duration)
        let fullRange = range ?? CMTimeRange(start: .zero, duration: assetDuration)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("boothify-rev-\(UUID().uuidString).mov")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(uprightSize.width),
            AVVideoHeightKey: Int(uprightSize.height),
            AVVideoCompressionPropertiesKey: [
                // Intermediate quality must not bottleneck the master.
                AVVideoAverageBitRateKey: 20_000_000,
            ],
        ])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        writer.add(writerInput)
        guard writer.startWriting() else {
            throw Booth360RenderEngineError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        // Upright decode helper: identity composition sized to the oriented frame.
        func makeIdentityComposition() -> AVMutableVideoComposition {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(uprightTransform(natural: naturalSize, preferred: transform), at: .zero)
            instruction.layerInstructions = [layer]
            let comp = AVMutableVideoComposition()
            comp.renderSize = uprightSize
            comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate, 1)))
            comp.instructions = [instruction]
            return comp
        }

        // Chunk boundaries, processed last → first.
        let total = fullRange.duration.seconds
        let chunkCount = max(Int(ceil(total / chunkSeconds)), 1)
        var globalFrame = 0
        let outFrameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate, 1)))

        for chunkIndex in stride(from: chunkCount - 1, through: 0, by: -1) {
            if Task.isCancelled {
                writerInput.markAsFinished()
                writer.cancelWriting()
                throw Booth360RenderEngineError.cancelled
            }
            let chunkStart = fullRange.start.seconds + Double(chunkIndex) * chunkSeconds
            let chunkDuration = min(chunkSeconds, fullRange.start.seconds + total - chunkStart)
            let chunkRange = CMTimeRange(
                start: CMTime(seconds: chunkStart, preferredTimescale: 600),
                duration: CMTime(seconds: chunkDuration, preferredTimescale: 600)
            )

            // Fresh reader per chunk (readers are single-pass).
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = chunkRange
            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track],
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            output.videoComposition = makeIdentityComposition()
            guard reader.canAdd(output) else {
                throw Booth360RenderEngineError.readerFailed("cannot add reverse output")
            }
            reader.add(output)
            guard reader.startReading() else {
                throw Booth360RenderEngineError.readerFailed(reader.error?.localizedDescription ?? "unknown")
            }

            // Collect this chunk's frames (bounded: chunkSeconds × fps).
            var chunkBuffers: [CVPixelBuffer] = []
            while true {
                var done = false
                autoreleasepool {
                    if let sample = output.copyNextSampleBuffer(),
                       let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
                        chunkBuffers.append(pixelBuffer)
                    } else {
                        done = true
                    }
                }
                if done { break }
            }
            if reader.status == .failed {
                throw Booth360RenderEngineError.readerFailed(reader.error?.localizedDescription ?? "unknown")
            }

            // Append reversed, with fresh ascending PTS.
            for buffer in chunkBuffers.reversed() {
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                let pts = CMTimeMultiply(outFrameDuration, multiplier: Int32(globalFrame))
                if !adaptor.append(buffer, withPresentationTime: pts) {
                    throw Booth360RenderEngineError.writerFailed(writer.error?.localizedDescription ?? "append failed")
                }
                globalFrame += 1
            }
            chunkBuffers.removeAll()
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Booth360RenderEngineError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        log.info("reversed \(globalFrame) frames → \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
    }

    /// Transform that maps the raw buffer into an upright frame at origin.
    private static func uprightTransform(natural: CGSize, preferred: CGAffineTransform) -> CGAffineTransform {
        let oriented = natural.applying(preferred)
        var t = preferred
        // preferredTransform can leave the image at a negative origin — shift back.
        t.tx = oriented.width < 0 ? abs(oriented.width) : max(t.tx, 0) == t.tx ? t.tx : t.tx
        // Standard normalization: apply, then translate negatives into view.
        let rect = CGRect(origin: .zero, size: natural).applying(preferred)
        t = t.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        return t
    }
}
