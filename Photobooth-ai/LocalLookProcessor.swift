import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// On-device photo "looks" — instant, free, no network, no AI API. This lets the
/// booth run as a full photo booth even when the cloud AI is unavailable: the
/// guest picks a look, it's applied with Core Image on-device, and the result is
/// ready to save / print / share immediately.
enum LocalLook: String, CaseIterable, Identifiable, Sendable {
    case original, noir, mono, chrome, fade, instant, process, transfer, sepia, vivid, comic, pop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: "Original"
        case .noir:     "Noir"
        case .mono:     "Mono"
        case .chrome:   "Chrome"
        case .fade:     "Fade"
        case .instant:  "Instant"
        case .process:  "Process"
        case .transfer: "Transfer"
        case .sepia:    "Sepia"
        case .vivid:    "Vivid"
        case .comic:    "Comic"
        case .pop:      "Pop Art"
        }
    }

    var symbol: String {
        switch self {
        case .original: "photo"
        case .noir:     "moon.stars"
        case .mono:     "circle.lefthalf.filled"
        case .chrome:   "sparkles"
        case .fade:     "sun.haze"
        case .instant:  "camera.filters"
        case .process:  "swatchpalette"
        case .transfer: "drop"
        case .sepia:    "leaf"
        case .vivid:    "wand.and.rays"
        case .comic:    "scribble.variable"
        case .pop:      "paintpalette"
        }
    }
}

enum LocalLookProcessor {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Apply a look to JPEG/PNG data and return JPEG data. Returns the original
    /// data unchanged if the look is `.original` or processing fails.
    static func process(_ imageData: Data, look: LocalLook) -> Data {
        guard look != .original,
              let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return imageData
        }
        let input = CIImage(cgImage: cgImage)
        guard let output = apply(look, to: input)?.cropped(to: input.extent) else {
            return imageData
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return context.jpegRepresentation(of: output, colorSpace: colorSpace, options: [:]) ?? imageData
    }

    /// Small preview (used for the picker thumbnails) — same pipeline, downscaled.
    static func thumbnail(_ imageData: Data, look: LocalLook, maxDimension: CGFloat = 240) -> UIImage? {
        guard let uiImage = UIImage(data: imageData), let cg = uiImage.cgImage else { return nil }
        var input = CIImage(cgImage: cg)
        let scale = min(1, maxDimension / max(input.extent.width, input.extent.height))
        if scale < 1 {
            input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let output = (look == .original ? input : apply(look, to: input))?.cropped(to: input.extent),
              let cgOut = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgOut)
    }

    // MARK: - Filters

    private static func apply(_ look: LocalLook, to image: CIImage) -> CIImage? {
        switch look {
        case .original:
            return image
        case .noir:     return photoEffect("CIPhotoEffectNoir", image)
        case .mono:     return photoEffect("CIPhotoEffectMono", image)
        case .chrome:   return photoEffect("CIPhotoEffectChrome", image)
        case .fade:     return photoEffect("CIPhotoEffectFade", image)
        case .instant:  return photoEffect("CIPhotoEffectInstant", image)
        case .process:  return photoEffect("CIPhotoEffectProcess", image)
        case .transfer: return photoEffect("CIPhotoEffectTransfer", image)
        case .sepia:
            let f = CIFilter.sepiaTone()
            f.inputImage = image
            f.intensity = 0.9
            return f.outputImage
        case .vivid:
            let v = CIFilter.vibrance()
            v.inputImage = image
            v.amount = 1.0
            guard let vibrant = v.outputImage else { return image }
            let s = CIFilter.colorControls()
            s.inputImage = vibrant
            s.saturation = 1.35
            s.contrast = 1.08
            return s.outputImage
        case .comic:
            // Stylized "AI-ish" cartoon look — edges + posterized color.
            let f = CIFilter.comicEffect()
            f.inputImage = image
            return f.outputImage
        case .pop:
            let f = CIFilter.colorPosterize()
            f.inputImage = image
            f.levels = 6
            return f.outputImage
        }
    }

    private static func photoEffect(_ name: String, _ image: CIImage) -> CIImage? {
        guard let f = CIFilter(name: name) else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        return f.outputImage
    }
}
