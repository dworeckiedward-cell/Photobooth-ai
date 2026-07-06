import Foundation
import UIKit
import os.log

/// Phase 5 — turn operator settings into engine `RenderDecorations`.
///
/// Overlay strategy: whatever the source (bundled sample, uploaded PNG, text
/// fallback), we rasterize a FULL-FRAME transparent canvas at the output size
/// with the mark placed per BrandOverlaySettings (position/size/opacity/
/// padding). The engine then composites one exact-size, guaranteed-transparent
/// image — uploaded assets are validated via `OverlaySpec` first.
enum RenderDecorationsBuilder {
    private static let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Decorations")

    static func eventDirectory(eventId: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent(eventId.uuidString, isDirectory: true)
    }

    static func build(
        eventId: UUID,
        settings: EventSettings,
        spec: RenderSpec
    ) -> Booth360RenderEngine.RenderDecorations {
        var decorations = Booth360RenderEngine.RenderDecorations()
        let eventDir = eventDirectory(eventId: eventId)

        // Overlay canvas (only when the operator enabled branding on results).
        if settings.brandOverlay.enabled, settings.brandOverlay.applyToResults {
            decorations.overlay = overlayCanvas(
                brand: settings.brandOverlay, spec: spec, eventDir: eventDir
            )
        }

        // Soundtrack / intro / outro — relative to the event directory.
        func resolve(_ relative: String?) -> URL? {
            guard let relative, !relative.isEmpty else { return nil }
            let url = eventDir.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else {
                log.warning("asset missing: \(relative, privacy: .public)")
                return nil
            }
            return url
        }
        decorations.soundtrackURL = resolve(settings.ai360.soundtrackRelativePath)
        decorations.introURL = resolve(settings.ai360.introRelativePath)
        decorations.outroURL = resolve(settings.ai360.outroRelativePath)
        return decorations
    }

    /// Rasterize the brand mark onto a transparent full-frame canvas.
    static func overlayCanvas(
        brand: BrandOverlaySettings,
        spec: RenderSpec,
        eventDir: URL
    ) -> CGImage? {
        // 1) Resolve the mark image (or text).
        var markImage: UIImage?
        switch brand.logoSource {
        case .boothifySample:
            markImage = UIImage(named: brand.logoAssetName ?? "BoothifyLogo")
        case .uploaded:
            if let relative = brand.customLogoRelativePath {
                let url = eventDir.appendingPathComponent(relative)
                if let image = UIImage(contentsOfFile: url.path) {
                    // Uploaded assets must not be opaque full-bleed rectangles.
                    let verdict = OverlaySpec.validate(image: image, compositionSize: spec.size)
                    switch verdict {
                    case .rejectedOpaque:
                        // A logo (smaller than frame) is fine even when its own
                        // bounds are opaque — the canvas adds the transparency.
                        // Only reject FULL-FRAME opaque uploads.
                        if image.size.width >= spec.size.width * 0.95 {
                            log.warning("overlay rejected: opaque full-frame upload")
                            markImage = nil
                        } else {
                            markImage = image
                        }
                    default:
                        markImage = image
                    }
                }
            }
        case .textFallback:
            markImage = renderTextMark(brand.overlayText)
        }
        guard let mark = markImage, mark.size.width > 0, mark.size.height > 0 else { return nil }

        // 2) Place onto the canvas.
        let canvasSize = spec.size
        let markWidth = canvasSize.width * brand.size
        let markHeight = markWidth * (mark.size.height / mark.size.width)
        let pad = canvasSize.width * brand.padding

        let origin: CGPoint
        switch brand.position {
        case .topLeft:      origin = CGPoint(x: pad, y: pad)
        case .topRight:     origin = CGPoint(x: canvasSize.width - markWidth - pad, y: pad)
        case .bottomLeft:   origin = CGPoint(x: pad, y: canvasSize.height - markHeight - pad)
        case .bottomRight:  origin = CGPoint(x: canvasSize.width - markWidth - pad, y: canvasSize.height - markHeight - pad)
        case .center:       origin = CGPoint(x: (canvasSize.width - markWidth) / 2, y: (canvasSize.height - markHeight) / 2)
        }

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: {
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false
            format.scale = 1
            return format
        }())
        let canvas = renderer.image { _ in
            mark.draw(
                in: CGRect(origin: origin, size: CGSize(width: markWidth, height: markHeight)),
                blendMode: .normal,
                alpha: brand.opacity
            )
        }
        return canvas.cgImage
    }

    /// Watermark text → image (uploaded-logo-free operators still get branding).
    private static func renderTextMark(_ text: String) -> UIImage? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 96, weight: .heavy),
            .foregroundColor: UIColor.white.withAlphaComponent(0.95),
            .strokeColor: UIColor.black.withAlphaComponent(0.35),
            .strokeWidth: -2,
        ]
        let size = (trimmed as NSString).size(withAttributes: attributes)
        guard size.width > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            (trimmed as NSString).draw(at: .zero, withAttributes: attributes)
        }
    }
}
