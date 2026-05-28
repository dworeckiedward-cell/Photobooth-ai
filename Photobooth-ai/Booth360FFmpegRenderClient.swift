import Foundation
import os.log

/// M6 scaffold for the FFmpeg-backed 360 render client.
///
/// **Current state: STUB.** The official `ffmpeg-kit-ios` binary distribution
/// was retired by the maintainer; iOS doesn't ship FFmpeg natively. Until a
/// vetted community fork is added to the project (see `TODO-HUMAN.md` →
/// "M6 — FFmpeg binary"), this client:
///
///   1. Builds the actual `filter_complex` string from the active template
///      (`buildFilterComplex`) — same string FFmpegKit would execute.
///   2. Logs the exact command for debugging.
///   3. Hands the job off to `Booth360PassthroughRenderClient` so the
///      Processing UI completes and the operator sees their raw take as the
///      final video.
///
/// When binaries land, replacing the body of `runPipeline` with a real
/// `FFmpegKit.executeAsync(_:)` call is a ~10-line change. The filter chain
/// builder is the entire interesting part — it's already covered.
@MainActor
final class Booth360FFmpegRenderClient: Booth360RenderClient {
    static let shared = Booth360FFmpegRenderClient()

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Booth360FFmpeg")

    private init() {}

    func runPipeline(jobId: UUID, app: AppState) async {
        guard let job = app.job(id: jobId),
              let rawURL = job.rawVideoLocalURL,
              FileManager.default.fileExists(atPath: rawURL.path) else {
            await Booth360PassthroughRenderClient.shared.runPipeline(jobId: jobId, app: app)
            return
        }

        let segments = job.settingsSnapshot.effectiveSegments
        let outputURL = rawURL
            .deletingLastPathComponent()
            .appendingPathComponent("final_\(jobId.uuidString.prefix(8)).mp4")

        let chain = Self.buildFilterComplex(segments: segments)
        let cmd = Self.buildCommand(
            inputURL: rawURL,
            outputURL: outputURL,
            filterComplex: chain,
            bitrateMbps: job.settingsSnapshot.bitrateMbps,
            includeAudio: false  // Speed-ramp + reverse + atempo audio is fiddly; v1 ships video only.
        )

        // For now we log what we would have run, then fall through to passthrough.
        log.debug("ffmpeg-kit scaffold — would execute: \(cmd, privacy: .public)")

        await Booth360PassthroughRenderClient.shared.runPipeline(jobId: jobId, app: app)
    }

    // MARK: - Filter chain builder (covered by tests in the future)
    //
    // Builds something like:
    //   [0:v]trim=0:3,setpts=PTS/1.25[v0];
    //   [0:v]trim=3:6,setpts=PTS/0.75[v1];
    //   [0:v]trim=6:9,setpts=PTS*2,reverse[v2];
    //   [v0][v1][v2]concat=n=3:v=1:a=0[outv]

    /// Pure function — given a segment list returns the `filter_complex` body.
    /// Empty input returns empty string (caller should detect and skip render).
    static func buildFilterComplex(segments: [CaptureSegment]) -> String {
        guard !segments.isEmpty else { return "" }

        var parts: [String] = []
        var labels: [String] = []
        var cursor: Double = 0

        for (i, seg) in segments.enumerated() {
            let start = cursor
            let end = cursor + clampedDuration(seg.duration)
            cursor = end

            let speed = clampedSpeed(seg.speed)
            let label = "v\(i)"
            labels.append(label)

            // FFmpeg's setpts uses PTS/speed (faster) or PTS*1/speed (slower).
            // Equivalent forms work — we pick PTS/speed for readability.
            var ops: [String] = [
                String(format: "trim=%.3f:%.3f", start, end),
                String(format: "setpts=PTS/%.3f", speed),
            ]
            if seg.reverse {
                ops.append("reverse")
            }
            let stream = "[0:v]" + ops.joined(separator: ",") + "[\(label)]"
            parts.append(stream)
        }

        let concatInputs = labels.map { "[\($0)]" }.joined()
        let concat = "\(concatInputs)concat=n=\(segments.count):v=1:a=0[outv]"
        parts.append(concat)

        // FFmpeg expects filter_complex parts joined by `;` (or newline-equivalent).
        return parts.joined(separator: ";")
    }

    /// Compose the full `ffmpeg` argv equivalent. We don't shell-escape because
    /// FFmpegKit takes the command as a parsed string anyway — when the binary
    /// lands, swap this for `FFmpegKit.executeAsync(_:)` with the same string.
    static func buildCommand(
        inputURL: URL,
        outputURL: URL,
        filterComplex: String,
        bitrateMbps: Double,
        includeAudio: Bool
    ) -> String {
        let bitrate = max(1, bitrateMbps)
        var argv: [String] = [
            "-y",
            "-i", inputURL.path,
        ]
        argv += ["-filter_complex", "\"\(filterComplex)\""]
        argv += ["-map", "[outv]"]
        if !includeAudio {
            argv += ["-an"]
        }
        argv += [
            "-c:v", "libx264",
            "-profile:v", "baseline",
            "-pix_fmt", "yuv420p",
            "-b:v", String(format: "%.1fM", bitrate),
            "-movflags", "+faststart",
            outputURL.path,
        ]
        return argv.joined(separator: " ")
    }

    // MARK: - Validators

    /// Speed clamped to a range that gives stable output. `atempo` is bound to
    /// 0.5–2.0 (you can chain it for wider ranges), but for VIDEO setpts alone
    /// we accept 0.1–4.0 — beyond that frames start to look broken.
    private static func clampedSpeed(_ raw: Double) -> Double {
        min(4.0, max(0.1, raw))
    }

    private static func clampedDuration(_ raw: Double) -> Double {
        min(60.0, max(0.1, raw))
    }
}
