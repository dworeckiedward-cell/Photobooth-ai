import UIKit

/// Composes a classic photo-booth strip from a SINGLE capture, rendering the same
/// photo in several on-device looks stacked vertically with the event branding.
///
/// This is a differentiator: traditional booths (incl. LumaBooth) need a burst of
/// separate captures to build a strip. Boothify generates the iconic strip instantly
/// from one photo — no multi-capture, no network, no AI API.
enum PhotoStripComposer {

    /// Classic 2"×6" strip proportions (1:3). Each frame is 4:3, center-cropped.
    static func compose(
        from imageData: Data,
        looks: [LocalLook] = [.original, .vivid, .noir, .sepia],
        title: String?,
        accent: UIColor
    ) -> Data? {
        guard let source = UIImage(data: imageData) else { return nil }

        let width: CGFloat = 1200
        let margin: CGFloat = 36
        let gap: CGFloat = 18
        let footerH: CGFloat = 150
        let frameW = width - margin * 2
        let frameH = frameW * 3 / 4 // 4:3
        let count = max(1, looks.count)
        let height = margin + (frameH + gap) * CGFloat(count) - gap + footerH

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            // Card background
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            var y = margin
            for look in looks {
                let frame = CGRect(x: margin, y: y, width: frameW, height: frameH)
                // Apply the look to the source, then aspect-fill into the frame.
                let lookData = LocalLookProcessor.process(imageData, look: look)
                let lookImage = UIImage(data: lookData) ?? source
                drawAspectFill(lookImage, in: frame, context: ctx.cgContext)
                // Thin frame border
                ctx.cgContext.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
                ctx.cgContext.setLineWidth(1)
                ctx.cgContext.stroke(frame)
                y += frameH + gap
            }

            // Footer band
            let footerRect = CGRect(x: 0, y: height - footerH, width: width, height: footerH)
            accent.withAlphaComponent(0.10).setFill()
            ctx.fill(footerRect)

            let titleText = (title?.isEmpty == false ? title! : "Boothify") as NSString
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52, weight: .bold),
                .foregroundColor: UIColor(white: 0.1, alpha: 1),
            ]
            let tSize = titleText.size(withAttributes: titleAttrs)
            titleText.draw(
                at: CGPoint(x: (width - tSize.width) / 2, y: height - footerH + 30),
                withAttributes: titleAttrs
            )

            let date = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none) as NSString
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .medium),
                .foregroundColor: UIColor(white: 0.45, alpha: 1),
            ]
            let dSize = date.size(withAttributes: dateAttrs)
            date.draw(
                at: CGPoint(x: (width - dSize.width) / 2, y: height - footerH + 92),
                withAttributes: dateAttrs
            )
        }
        return image.jpegData(compressionQuality: 0.92)
    }

    /// Draw `image` filling `rect` (aspect fill), clipped to the rect.
    private static func drawAspectFill(_ image: UIImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        let imgSize = image.size
        let scale = max(rect.width / imgSize.width, rect.height / imgSize.height)
        let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let origin = CGPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )
        image.draw(in: CGRect(origin: origin, size: drawSize))
        context.restoreGState()
    }
}
