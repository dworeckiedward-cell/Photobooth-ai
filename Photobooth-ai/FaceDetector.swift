import Foundation
import Vision
import UIKit

/// On-device face counting via Apple Vision. Used to warn guests before AI
/// portrait generation: the AI restyle works best on a single face, so group
/// photos get a heads-up (matching the known single-face limit of AI portrait
/// modes across the category).
enum FaceDetector {
    /// Returns the number of faces detected, or nil if detection couldn't run.
    /// CPU-bound — call off the main thread.
    static func faceCount(in imageData: Data) async -> Int? {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.count ?? 0
    }
}
