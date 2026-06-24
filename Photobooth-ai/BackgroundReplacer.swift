import UIKit
import Vision
import CoreImage

/// On-device green-screen / background replacement using Apple's Vision person
/// segmentation (`VNGeneratePersonSegmentationRequest`) composited with CoreImage.
/// No third-party dependency, no network — runs entirely on the device.
///
/// This replaces the old "Demo" background-removal flow with a real pipeline:
///  - `.remove`        → person on a transparent background (PNG)
///  - `.replaceColor`  → person over a solid color (`backgroundHex`)
///  - `.replaceImage`  → person over a bundled background asset (`backgroundImageName`)
enum BackgroundReplacer {

    /// Shared context — creating a CIContext is expensive, so reuse one.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Returns new image data with the background replaced per `settings`, or the
    /// original data unchanged if the feature is off or segmentation fails (so the
    /// capture flow never dead-ends on a segmentation miss).
    ///
    /// CPU-bound — call from a background task, not the main thread.
    static func process(_ imageData: Data, settings: BackgroundRemovalSettings) -> Data {
        guard settings.enabled, settings.mode != .off,
              let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return imageData
        }

        let foreground = CIImage(cgImage: cgImage)
        let extent = foreground.extent

        guard let mask = personMask(for: cgImage, matching: extent) else {
            return imageData
        }

        let transparent = settings.mode == .remove
        let background = transparent
            ? CIImage.empty()
            : backgroundImage(for: settings, extent: extent)

        guard let blend = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: foreground,
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask,
        ])?.outputImage?.cropped(to: extent) else {
            return imageData
        }

        // Transparent output must be PNG (JPEG has no alpha); composites stay JPEG.
        if transparent {
            guard let cg = context.createCGImage(blend, from: extent) else { return imageData }
            return UIImage(cgImage: cg).pngData() ?? imageData
        } else {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            return context.jpegRepresentation(of: blend, colorSpace: colorSpace,
                                              options: [:]) ?? imageData
        }
    }

    // MARK: - Person mask

    private static func personMask(for cgImage: CGImage, matching extent: CGRect) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first else { return nil }

        let maskBuffer = result.pixelBuffer
        var mask = CIImage(cvPixelBuffer: maskBuffer)

        // The mask comes back at the model's resolution — scale it to the photo.
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        return mask
    }

    // MARK: - Background

    private static func backgroundImage(for settings: BackgroundRemovalSettings, extent: CGRect) -> CIImage {
        if settings.mode == .replaceImage,
           let name = settings.backgroundImageName,
           let asset = UIImage(named: name)?.cgImage {
            let bg = CIImage(cgImage: asset)
            return aspectFill(bg, into: extent)
        }
        let color = CIColor(color: UIColor(hex: settings.backgroundHex) ?? .black)
        return CIImage(color: color).cropped(to: extent)
    }

    /// Scale + center a background image to cover the target extent (aspect fill).
    private static func aspectFill(_ image: CIImage, into extent: CGRect) -> CIImage {
        let scale = max(extent.width / image.extent.width,
                        extent.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (extent.width - scaled.extent.width) / 2 - scaled.extent.origin.x
        let dy = (extent.height - scaled.extent.height) / 2 - scaled.extent.origin.y
        return scaled
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: extent)
    }
}

// MARK: - Hex color

private extension UIColor {
    /// Parses `#RRGGBB` (with or without leading `#`). Returns nil on bad input.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
