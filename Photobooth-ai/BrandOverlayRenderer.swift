import UIKit

/// Bakes the operator's brand overlay (logo or text mark) into a finished image.
/// Standalone + reusable so the no-AI paths (Instant Looks, photo strip) produce
/// white-labeled, print-ready output just like the AI result screen — operators
/// expect their logo on every photo.
enum BrandOverlayRenderer {
    /// Returns `base` with the overlay drawn in, or unchanged when disabled.
    static func bake(into base: UIImage, settings: BrandOverlaySettings, eventId: UUID) -> UIImage {
        guard settings.enabled else { return base }

        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: base.size))

            let shorter = min(base.size.width, base.size.height)
            let side = shorter * CGFloat(settings.size)
            let pad = shorter * CGFloat(settings.padding)

            switch settings.logoSource {
            case .boothifySample, .uploaded:
                let logo: UIImage?
                if settings.logoSource == .uploaded, let relative = settings.customLogoRelativePath {
                    logo = BrandOverlayLayer.loadUploadedLogo(eventId: eventId, relative: relative)
                        ?? UIImage(named: settings.logoAssetName)
                } else {
                    logo = UIImage(named: settings.logoAssetName)
                }
                guard let logo else { return }
                let rect = anchoredRect(side: side, pad: pad, container: base.size, position: settings.position)
                ctx.cgContext.setAlpha(CGFloat(settings.opacity))
                logo.draw(in: rect)
            case .textFallback:
                let fontSize = max(11, side * 0.30)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(CGFloat(settings.opacity)),
                ]
                let text = settings.overlayText as NSString
                let textSize = text.size(withAttributes: attrs)
                let rect = anchoredRect(side: max(side, textSize.width + 16),
                                        pad: pad, container: base.size, position: settings.position)
                let bg = UIColor.black.withAlphaComponent(0.42 * CGFloat(settings.opacity))
                bg.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
                text.draw(
                    in: CGRect(x: rect.midX - textSize.width / 2,
                               y: rect.midY - textSize.height / 2,
                               width: textSize.width, height: textSize.height),
                    withAttributes: attrs
                )
            }
        }
    }

    private static func anchoredRect(side: CGFloat, pad: CGFloat, container: CGSize, position: BrandOverlayPosition) -> CGRect {
        switch position {
        case .topLeft:     return CGRect(x: pad, y: pad, width: side, height: side)
        case .topRight:    return CGRect(x: container.width - side - pad, y: pad, width: side, height: side)
        case .bottomLeft:  return CGRect(x: pad, y: container.height - side - pad, width: side, height: side)
        case .bottomRight: return CGRect(x: container.width - side - pad, y: container.height - side - pad, width: side, height: side)
        case .center:      return CGRect(x: (container.width - side) / 2, y: (container.height - side) / 2, width: side, height: side)
        }
    }
}
