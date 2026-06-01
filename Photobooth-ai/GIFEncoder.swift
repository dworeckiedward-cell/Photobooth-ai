import ImageIO
import UIKit
import UniformTypeIdentifiers

enum GIFEncoder {
    /// Encode frames into animated GIF Data.
    /// - Parameters:
    ///   - frames: Array of UIImages in capture order.
    ///   - boomerang: If true, appends reversed frames for a ping-pong loop.
    ///   - frameDelay: Seconds per frame (default 0.06 ≈ 16 fps).
    /// - Returns: GIF data, or nil on failure.
    static func encode(
        frames: [UIImage],
        boomerang: Bool = true,
        frameDelay: Double = 0.06
    ) -> Data? {
        guard !frames.isEmpty else { return nil }

        // Build the full frame sequence (ping-pong when boomerang is on).
        var sequence = frames
        if boomerang, frames.count > 2 {
            let reversed = Array(frames.dropFirst().dropLast().reversed())
            sequence.append(contentsOf: reversed)
        }

        // Resize frames so the GIF stays small (max 480 px wide).
        let resized = sequence.map { resize($0, maxDimension: 480) }

        // Create an in-memory destination.
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            resized.count,
            nil
        ) else { return nil }

        // Set file-level GIF properties (infinite loop).
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        // Add each frame.
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]
        for image in resized {
            guard let cgImage = image.cgImage else { continue }
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - Private helpers

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
