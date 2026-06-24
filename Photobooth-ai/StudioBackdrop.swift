import UIKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Procedural studio backdrops for green-screen replacement — generated on-device
/// with Core Image (no image assets, no network). Gives operators a curated set of
/// premium backgrounds without shipping megabytes of photos.
///
/// Stored in `BackgroundRemovalSettings.backgroundImageName` as `"studio:<id>"`,
/// so `.replaceImage` mode renders the backdrop instead of loading a bundled asset.
enum StudioBackdrop: String, CaseIterable, Identifiable, Sendable {
    case violet, sunset, ocean, charcoal, blush, emerald, gold, midnight

    var id: String { rawValue }
    static let prefix = "studio:"
    var storageName: String { Self.prefix + rawValue }

    var label: String {
        switch self {
        case .violet:   "Violet"
        case .sunset:   "Sunset"
        case .ocean:    "Ocean"
        case .charcoal: "Charcoal"
        case .blush:    "Blush"
        case .emerald:  "Emerald"
        case .gold:     "Gold"
        case .midnight: "Midnight"
        }
    }

    /// Two-stop palette (top → bottom).
    private var colors: (CIColor, CIColor) {
        func c(_ r: Double, _ g: Double, _ b: Double) -> CIColor { CIColor(red: r, green: g, blue: b) }
        switch self {
        case .violet:   return (c(0.36, 0.30, 0.92), c(0.10, 0.08, 0.28))
        case .sunset:   return (c(0.98, 0.55, 0.30), c(0.55, 0.12, 0.40))
        case .ocean:    return (c(0.15, 0.55, 0.85), c(0.04, 0.12, 0.32))
        case .charcoal: return (c(0.28, 0.29, 0.32), c(0.07, 0.07, 0.09))
        case .blush:    return (c(0.98, 0.78, 0.82), c(0.80, 0.40, 0.55))
        case .emerald:  return (c(0.10, 0.72, 0.52), c(0.02, 0.20, 0.18))
        case .gold:     return (c(0.96, 0.80, 0.40), c(0.55, 0.36, 0.08))
        case .midnight: return (c(0.16, 0.18, 0.34), c(0.02, 0.02, 0.06))
        }
    }

    /// SwiftUI gradient for settings swatches (top → bottom).
    var swatch: LinearGradient {
        let (top, bottom) = colors
        return LinearGradient(
            colors: [Color(uiColor: UIColor(ciColor: top)), Color(uiColor: UIColor(ciColor: bottom))],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// A linear gradient backdrop (top → bottom) cropped to `extent`.
    func ciImage(extent: CGRect) -> CIImage {
        let (top, bottom) = colors
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: extent.midX, y: extent.maxY) // top in CI's flipped space
        g.point1 = CGPoint(x: extent.midX, y: extent.minY)
        g.color0 = top
        g.color1 = bottom
        return (g.outputImage ?? CIImage(color: bottom)).cropped(to: extent)
    }

    /// Resolve a stored `backgroundImageName` to a backdrop, if it encodes one.
    static func from(storageName: String?) -> StudioBackdrop? {
        guard let name = storageName, name.hasPrefix(prefix) else { return nil }
        return StudioBackdrop(rawValue: String(name.dropFirst(prefix.count)))
    }
}
