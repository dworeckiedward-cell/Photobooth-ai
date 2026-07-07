import Foundation
import UIKit
import CoreImage

/// Phase 5 — overlay asset rules (blueprint §7.5).
///
/// Sizes 1080×1920 / 1920×1080 / 1080×1080; transparent background MANDATORY;
/// the asset must match the composition size — exact match passes, same-aspect
/// smaller/larger assets are scaled WITH a warning, aspect mismatches are
/// REJECTED (stretching is an amateur tell — we never stretch).
enum OverlayValidation: Equatable {
    case ok
    /// Same aspect, different pixels — usable, scaled, operator warned.
    case scaledWithWarning(from: CGSize)
    case rejectedOpaque
    case rejectedAspectMismatch(assetAspect: Double, compositionAspect: Double)

    var isUsable: Bool {
        switch self {
        case .ok, .scaledWithWarning: return true
        case .rejectedOpaque, .rejectedAspectMismatch: return false
        }
    }

    /// Operator-legible message (error taxonomy §8 — cause + recovery).
    var operatorMessage: String? {
        switch self {
        case .ok:
            return nil
        case .scaledWithWarning(let from):
            return "Overlay is \(Int(from.width))×\(Int(from.height)) — it will be scaled to fit. For the crispest result export it at the output size."
        case .rejectedOpaque:
            return "Overlay has no transparency — export it as PNG with a transparent background, otherwise it would cover the whole video."
        case .rejectedAspectMismatch:
            return "Overlay aspect ratio doesn't match the video. Export it at 1080×1920 (portrait), 1920×1080 (landscape) or 1080×1080 (square)."
        }
    }
}

enum OverlaySpec {
    /// Validate an overlay image against a composition size.
    static func validate(image: UIImage, compositionSize: CGSize) -> OverlayValidation {
        guard let cgImage = image.cgImage else { return .rejectedOpaque }

        // 1) Transparency: the format must carry alpha AND actually use it.
        let alphaInfo = cgImage.alphaInfo
        let hasAlphaChannel = !(alphaInfo == .none || alphaInfo == .noneSkipLast || alphaInfo == .noneSkipFirst)
        guard hasAlphaChannel, hasActualTransparency(cgImage) else {
            return .rejectedOpaque
        }

        // 2) Geometry.
        let assetSize = CGSize(width: cgImage.width, height: cgImage.height)
        if assetSize == compositionSize { return .ok }

        let assetAspect = assetSize.width / assetSize.height
        let compositionAspect = compositionSize.width / compositionSize.height
        if abs(assetAspect - compositionAspect) < 0.01 {
            return .scaledWithWarning(from: assetSize)
        }
        return .rejectedAspectMismatch(
            assetAspect: Double(assetAspect), compositionAspect: Double(compositionAspect)
        )
    }

    /// Cheap min-alpha probe: render to a 1×1 minimum-alpha reduction.
    private static func hasActualTransparency(_ cgImage: CGImage) -> Bool {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaMinimum", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent),
        ]), let output = filter.outputImage else { return false }
        var pixel = [UInt8](repeating: 255, count: 4)
        CIContext().render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        // Some pixel somewhere is meaningfully transparent.
        return pixel[3] < 250
    }
}

/// §7.6 — music licensing guardrail, guest/operator-visible, localized.
enum SoundtrackLicensing {
    static func copy() -> String {
        Loc.t(
            "Use royalty-cleared or client-supplied music. Syncing commercial tracks to video requires sync rights — a venue's public-performance license does not cover it.",
            pl: "Używaj muzyki z licencją royalty-free lub dostarczonej przez klienta. Synchronizacja utworów komercyjnych z wideo wymaga praw synchronizacyjnych — licencja na publiczne odtwarzanie ich nie obejmuje.",
            de: "Nutze lizenzfreie oder vom Kunden bereitgestellte Musik. Das Synchronisieren kommerzieller Titel mit Video erfordert Sync-Rechte — eine Aufführungslizenz deckt das nicht ab."
        )
    }

    /// Raw variants exposed for tests (every SHIPPED language must exist —
    /// EN + DE; Polish was dropped with the market decision).
    static var allVariants: [String] {
        [
            "Use royalty-cleared or client-supplied music. Syncing commercial tracks to video requires sync rights — a venue's public-performance license does not cover it.",
            "Nutze lizenzfreie oder vom Kunden bereitgestellte Musik. Das Synchronisieren kommerzieller Titel mit Video erfordert Sync-Rechte — eine Aufführungslizenz deckt das nicht ab.",
        ]
    }
}
