import UIKit
import AVFoundation

/// Renders a short square MP4 that cycles a single capture through several
/// on-device looks — a shareable "reel" from one photo. Pure AVFoundation, no
/// network, no AI API. Another thing a still-only booth (LumaBooth) can't do
/// from a single frame.
enum LookReelComposer {
    /// Compose an MP4. `holdSeconds` is how long each look is shown.
    /// Completion returns the file URL on the main thread (nil on failure).
    static func compose(
        from imageData: Data,
        looks: [LocalLook] = [.original, .vivid, .noir, .sepia, .pop, .chrome],
        side: CGFloat = 1080,
        fps: Int32 = 30,
        holdSeconds: Double = 0.5,
        completion: @escaping (URL?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("boothify-reel-\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: url)

            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
                return done(nil, completion)
            }
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(side),
                AVVideoHeightKey: Int(side),
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(side),
                kCVPixelBufferHeightKey as String: Int(side),
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input, sourcePixelBufferAttributes: attrs
            )
            guard writer.canAdd(input) else { return done(nil, completion) }
            writer.add(input)

            // Pre-render one square pixel buffer per look.
            let size = CGSize(width: side, height: side)
            let buffers: [CVPixelBuffer] = looks.compactMap { look in
                let data = LocalLookProcessor.process(imageData, look: look)
                guard let img = UIImage(data: data) else { return nil }
                return pixelBuffer(from: img, size: size)
            }
            guard !buffers.isEmpty else { return done(nil, completion) }

            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            let framesPerLook = max(1, Int(Double(fps) * holdSeconds))
            var frameIndex = 0
            let queue = DispatchQueue(label: "boothify.reel.writer")
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    let totalFrames = buffers.count * framesPerLook
                    if frameIndex >= totalFrames {
                        input.markAsFinished()
                        writer.finishWriting {
                            done(writer.status == .completed ? url : nil, completion)
                        }
                        return
                    }
                    let buffer = buffers[(frameIndex / framesPerLook) % buffers.count]
                    let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                    adaptor.append(buffer, withPresentationTime: time)
                    frameIndex += 1
                }
            }
        }
    }

    private static func done(_ url: URL?, _ completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async { completion(url) }
    }

    /// Aspect-fill `image` into a square pixel buffer.
    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB, attrs, &pb
        )
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ), let cg = image.cgImage else { return nil }

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // Aspect-fill
        let imgSize = CGSize(width: cg.width, height: cg.height)
        let scale = max(size.width / imgSize.width, size.height / imgSize.height)
        let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        ctx.draw(cg, in: CGRect(origin: origin, size: drawSize))
        return buffer
    }
}
