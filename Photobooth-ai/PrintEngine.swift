import UIKit

/// AirPrint engine. Wraps UIPrintInteractionController so callers
/// don't need to import UIKit directly. All presentation happens from
/// the key window's root view controller.
enum PrintEngine {

    /// Print a single photo. Handles layout composition (single, 2-strip, 4-strip, double-single),
    /// optional QR code overlay, and copies count.
    /// - Parameters:
    ///   - image: The generated AI portrait to print.
    ///   - settings: Current event print settings.
    ///   - eventName: Optional event name for header overlay.
    ///   - qrURL: Optional URL for QR code overlay (guest download link).
    @MainActor
    static func print(
        image: UIImage,
        settings: PrintSetupSettings,
        eventName: String? = nil,
        qrURL: URL? = nil
    ) {
        guard UIPrintInteractionController.isPrintingAvailable else {
            showNoPrinterAlert()
            return
        }

        let controller = UIPrintInteractionController.shared

        // Info
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo
        info.jobName = eventName.map { "Boothify – \($0)" } ?? "Boothify Photo"
        info.duplex = .none
        controller.printInfo = info

        // Compose the printable image (layout: single / 2-strip / 4-strip / double-single)
        let composed = compose(
            image: image,
            layout: settings.layout,
            eventName: settings.includeEventName ? eventName : nil,
            qrURL: settings.includeQRCode ? qrURL : nil
        )

        // Page renderer
        let renderer = SingleImagePrintRenderer(image: composed)
        controller.printPageRenderer = renderer
        controller.showsNumberOfCopies = true

        // Present from the key window's root view controller
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }

        controller.present(from: root.view.bounds, in: root.view, animated: true) { _, _, error in
            if let error { Swift.print("[PrintEngine] error: \(error)") }
        }
    }

    // MARK: - Layout composition

    private static func compose(
        image: UIImage,
        layout: PrintLayout,
        eventName: String?,
        qrURL: URL?
    ) -> UIImage {
        let copies: Int
        switch layout {
        case .single:       copies = 1
        case .twoStrip:     copies = 2
        case .fourStrip:    copies = 4
        case .doubleSingle: copies = 2
        }

        let overlaid = addOverlays(to: image, eventName: eventName, qrURL: qrURL)

        if copies == 1 { return overlaid }

        // Tile: arrange copies in a vertical strip
        let cols = 1
        let rows = copies
        let cellW = image.size.width
        let cellH = image.size.height
        let canvasSize = CGSize(width: cellW * CGFloat(cols), height: cellH * CGFloat(rows))

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
            for i in 0..<copies {
                let row = CGFloat(i)
                let rect = CGRect(x: 0, y: row * cellH, width: cellW, height: cellH)
                overlaid.draw(in: rect)
            }
        }
    }

    private static func addOverlays(to image: UIImage, eventName: String?, qrURL: URL?) -> UIImage {
        guard eventName != nil || qrURL != nil else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            // Event name — bottom center, small white text on semi-transparent bar
            if let name = eventName {
                let barH: CGFloat = 40
                let barRect = CGRect(x: 0, y: image.size.height - barH,
                                     width: image.size.width, height: barH)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIRectFill(barRect)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ]
                let str = NSAttributedString(string: name, attributes: attrs)
                let strSize = str.size()
                str.draw(at: CGPoint(x: (image.size.width - strSize.width) / 2,
                                     y: barRect.midY - strSize.height / 2))
            }

            // QR code — bottom-right corner, 80×80pt
            if let url = qrURL,
               let qrImage = QRGenerator.image(from: url.absoluteString, targetSide: 240) {
                let qrSize: CGFloat = 80
                let margin: CGFloat = 8
                let qrRect = CGRect(x: image.size.width - qrSize - margin,
                                    y: image.size.height - qrSize - margin,
                                    width: qrSize, height: qrSize)
                UIColor.white.setFill()
                UIRectFill(qrRect.insetBy(dx: -4, dy: -4))
                qrImage.draw(in: qrRect)
            }
        }
    }

    @MainActor
    private static func showNoPrinterAlert() {
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        let alert = UIAlertController(
            title: "No Printer Found",
            message: "Connect an AirPrint-compatible printer to the same WiFi network and try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(alert, animated: true)
    }
}

// MARK: - Page renderer

private final class SingleImagePrintRenderer: UIPrintPageRenderer {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
        super.init()
        self.headerHeight = 0
        self.footerHeight = 0
    }

    override var numberOfPages: Int { 1 }

    override func drawContentForPage(at pageIndex: Int, in contentRect: CGRect) {
        let imgRatio = image.size.width / image.size.height
        let rectRatio = contentRect.width / contentRect.height
        let drawRect: CGRect
        if imgRatio > rectRatio {
            let h = contentRect.width / imgRatio
            drawRect = CGRect(x: contentRect.minX,
                              y: contentRect.minY + (contentRect.height - h) / 2,
                              width: contentRect.width, height: h)
        } else {
            let w = contentRect.height * imgRatio
            drawRect = CGRect(x: contentRect.minX + (contentRect.width - w) / 2,
                              y: contentRect.minY,
                              width: w, height: contentRect.height)
        }
        image.draw(in: drawRect)
    }
}
