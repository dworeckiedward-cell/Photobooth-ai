import Foundation
import AVFoundation
import CoreVideo
import UIKit

/// Blueprint §12 — synthetic input clips so the capture→render→export path is
/// testable in the simulator with NO camera and NO binary fixtures in the repo.
/// Generates a solid-color (per-frame varying) H.264 .mov at the requested
/// fps/size/duration via AVAssetWriter.
enum TestVideoFactory {

    static func makeClip(
        seconds: Double = 2.0,
        fps: Int32 = 30,
        width: Int = 640,
        height: Int = 480
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-\(UUID().uuidString).mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "factory", code: 1) }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(seconds * Double(fps))
        var frame = 0
        while frame < frameCount {
            if input.isReadyForMoreMediaData {
                let time = CMTime(value: CMTimeValue(frame), timescale: fps)
                guard let buffer = makePixelBuffer(width: width, height: height, hue: CGFloat(frame) / CGFloat(frameCount)) else {
                    throw NSError(domain: "factory", code: 2)
                }
                adaptor.append(buffer, withPresentationTime: time)
                frame += 1
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "factory", code: 3) }
        return url
    }

    private static func makePixelBuffer(width: Int, height: Int, hue: CGFloat) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pixelBuffer
        )
        guard let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        let color = UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
