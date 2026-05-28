import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import SwiftUI

/// IM1: on-device QR code generator for guest-share URLs. CoreImage based —
/// no third-party deps. We use `correctionLevel = "H"` (highest, 30%
/// recoverable) so the code stays scannable even if the operator covers
/// part of it on a print or under harsh stage lighting.
///
/// Output is a crisp UIImage scaled by `targetSide` (defaults to 512 px),
/// and rendered with `.interpolation(.none)` from SwiftUI consumers to
/// keep the modules sharp instead of blurry.
enum QRGenerator {
    private static let context = CIContext(options: nil)

    /// Generate a black-on-white QR `UIImage` for the given string.
    /// Returns nil only when the filter genuinely cannot encode the input
    /// (extremely long string, etc.) — callers should always fall back to
    /// showing the URL as text.
    static func image(from string: String, targetSide: CGFloat = 512) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"

        guard let baseImage = filter.outputImage else { return nil }

        // Scale up — default QR output is ~80x80, looks pixel-shifted on
        // any sane preview. Use `.transformed` so the bitmap upscale is
        // exact (no interpolation), then SwiftUI consumers can shrink it.
        let scale = max(1, targetSide / max(baseImage.extent.width, 1))
        let scaled = baseImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// IM1: SwiftUI helper that renders a QR code from a URL with the
/// nearest-neighbour scaling that keeps the modules crisp at any
/// container size. White background is drawn underneath so the symbol
/// stays scannable on dark UI.
struct QRCodeView: View {
    let url: URL
    var background: Color = .white
    var foreground: Color = .black
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            background

            if let image = QRGenerator.image(from: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .colorMultiply(foreground == .black ? .white : foreground)
            } else {
                // Encoder refused (very long URL?). Show the raw URL text so
                // the operator can still type it / paste it elsewhere.
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("QR code for \(url.absoluteString)")
    }
}
