import Foundation
import os.log
import ffmpegkit

/// IM0: live FFmpeg-backed 360 render client.
///
/// Pipeline (per `runPipeline`):
///   1. Build the `filter_complex` string from the active template
///      (`buildFilterComplex`). Composes trim → setpts → reverse → concat
///      per segment, plus optional brand-overlay layer.
///   2. Build the full `ffmpeg` command — encoder is `h264_videotoolbox`
///      (hardware-accelerated, no GPL contamination, friendly to older
///      iPhones), pixel format yuv420p, faststart enabled for smooth
///      playback.
///   3. Optionally mux the soundtrack the operator picked in M4 via
///      `-i <music>` + `-c:a aac_at -shortest`. Skipped silently if no
///      track is set or the file went missing.
///   4. Execute asynchronously via `FFmpegKit.executeAsync(_:)`.
///   5. Stream progress: `FFmpegKitConfig.enableStatisticsCallback`
///      reports the current output time in ms; we map that onto
///      `Booth360Job.progress` (0…1).
///   6. On non-zero return code, fall back to the passthrough client so
///      the user still ends with the raw take + a "montage failed"
///      surface — never crash mid-event.
@MainActor
final class Booth360FFmpegRenderClient: Booth360RenderClient {
    static let shared = Booth360FFmpegRenderClient()

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Booth360FFmpeg")

    private init() {}

    func runPipeline(jobId: UUID, app: AppState) async {
        guard var job = app.job(id: jobId),
              let rawURL = job.rawVideoLocalURL,
              FileManager.default.fileExists(atPath: rawURL.path) else {
            await Booth360PassthroughRenderClient.shared.runPipeline(jobId: jobId, app: app)
            return
        }

        let segments = job.settingsSnapshot.effectiveSegments
        let outputURL = rawURL
            .deletingLastPathComponent()
            .appendingPathComponent("final_\(jobId.uuidString.prefix(8)).mp4")

        // M7: if the operator uploaded a custom logo we bake it into the final
        // via FFmpeg's overlay filter (added in buildFilterComplex when
        // overlayLogoURL != nil).
        let overlayURL = BrandOverlayLayer.uploadedLogoURL(
            eventId: job.eventId,
            settings: job.brandOverlay
        )

        // M4 soundtrack — silently optional. If file is missing we just drop
        // the audio input; never block the render on it.
        let soundtrackURL = Self.resolveSoundtrackURL(eventId: job.eventId, settings: job.settingsSnapshot)

        let chain = Self.buildFilterComplex(
            segments: segments,
            overlay: overlayURL == nil ? nil : OverlaySpec(
                position: job.brandOverlay.position,
                sizeFraction: job.brandOverlay.size,
                paddingFraction: job.brandOverlay.padding,
                opacity: job.brandOverlay.opacity
            )
        )
        let cmd = Self.buildCommand(
            inputURL: rawURL,
            overlayURL: overlayURL,
            soundtrackURL: soundtrackURL,
            outputURL: outputURL,
            filterComplex: chain,
            bitrateMbps: job.settingsSnapshot.bitrateMbps
        )

        log.debug("ffmpeg cmd: \(cmd, privacy: .public)")

        // Move job to processing immediately so the UI doesn't sit at 0%.
        job.status = .processing
        job.currentStep = .stabilizing
        job.progress = 0.05
        app.upsertJob(job)

        // Total expected output duration in ms — used to translate per-frame
        // ffmpeg `time` statistics into a 0…1 progress value. Falls back to
        // raw recording duration if the template doesn't declare its own.
        let renderedDurationMs = max(1.0, expectedRenderedSeconds(for: job) * 1000.0)

        // Install statistics callback BEFORE executeAsync so the very first
        // tick is captured. The callback runs on FFmpegKit's worker — hop to
        // the main actor to mutate AppState safely.
        FFmpegKitConfig.enableStatisticsCallback { [weak app] stats in
            guard let app, let stats else { return }
            let timeMs = Double(stats.getTime())
            let pct = max(0.0, min(0.95, timeMs / renderedDurationMs))
            Task { @MainActor in
                guard var live = app.job(id: jobId) else { return }
                live.progress = pct
                live.currentStep = .cinematicEffects
                app.upsertJob(live)
            }
        }

        // Run the command. executeAsync's completion callback fires once per
        // session — we bridge it onto an async continuation so we can await it.
        let returnCode: ReturnCode? = await withCheckedContinuation { (cont: CheckedContinuation<ReturnCode?, Never>) in
            FFmpegKit.executeAsync(cmd) { session in
                let rc = session?.getReturnCode()
                cont.resume(returning: rc)
            }
        }

        FFmpegKitConfig.enableStatisticsCallback(nil)

        // Outcome → job state.
        if let rc = returnCode, ReturnCode.isSuccess(rc),
           FileManager.default.fileExists(atPath: outputURL.path) {
            guard var live = app.job(id: jobId) else { return }
            live.status = .completed
            live.currentStep = nil
            live.progress = 1.0
            live.completedAt = .now
            live.finalVideoURL = outputURL
            // Optimistic mock share URL — replaced by the real one returned
            // from /api/booth360/jobs (confirm) once the BM0 cloud uploader
            // finishes. If the operator opens the result screen before the
            // upload completes, the mock URL keeps copy-link / share working
            // (link itself will 404 until upload lands, but UI doesn't break).
            if live.publicShareURL == nil {
                live.publicShareURL = URL(string: "https://boothify.app/v/\(jobId.uuidString.prefix(8).lowercased())")
            }
            app.upsertJob(live)

            // BM0: kick off the cloud upload pipeline (sign → PUT → confirm).
            // Non-blocking — operator can navigate to Result screen / start
            // recording the next guest while the upload runs in background.
            Booth360CloudUploader.shared.enqueue(jobId: jobId, app: app)
            return
        }

        // Anything other than success → log + passthrough fallback so the
        // operator still gets the raw take + a non-nil finalVideoURL.
        if let rc = returnCode {
            log.error("ffmpeg returned \(rc.getValue(), privacy: .public) — falling back to passthrough")
        } else {
            log.error("ffmpeg session returned nil — falling back to passthrough")
        }
        var failed = job
        failed.errorMessage = "Montage failed — saved the raw recording instead."
        app.upsertJob(failed)
        await Booth360PassthroughRenderClient.shared.runPipeline(jobId: jobId, app: app)
    }

    /// Total seconds we expect the final output to span — used for progress
    /// scaling. Falls back to raw recording duration when no template is set.
    private func expectedRenderedSeconds(for job: Booth360Job) -> Double {
        let segs = job.settingsSnapshot.effectiveSegments
        let total = segs.reduce(0.0) { $0 + $1.renderedDuration }
        if total > 0 { return total }
        return max(1.0, job.settingsSnapshot.recordingDurationSeconds)
    }

    /// Resolve the absolute on-disk path of the operator's chosen soundtrack
    /// (M4). Stored relative under `Documents/events/<id>/audio/<file>`.
    private static func resolveSoundtrackURL(eventId: UUID, settings: AI360Settings) -> URL? {
        guard let relative = settings.soundtrackRelativePath, !relative.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = docs
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent(eventId.uuidString, isDirectory: true)
            .appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Overlay positioning spec passed into the filter chain builder.
    struct OverlaySpec: Sendable {
        let position: BrandOverlayPosition
        let sizeFraction: Double      // 0…1 fraction of the shorter video edge
        let paddingFraction: Double   // 0…1 fraction of the shorter video edge
        let opacity: Double           // 0…1
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
    ///
    /// If `overlay` is non-nil, an extra `[concatOut][1:v]overlay=…[outv]`
    /// stage is appended that assumes input index `[1:v]` is the overlay PNG.
    static func buildFilterComplex(
        segments: [CaptureSegment],
        overlay: OverlaySpec? = nil
    ) -> String {
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
        let concatOutLabel = overlay == nil ? "outv" : "concatOut"
        let concat = "\(concatInputs)concat=n=\(segments.count):v=1:a=0[\(concatOutLabel)]"
        parts.append(concat)

        // M7: overlay logo if present. We first scale the PNG to a fraction
        // of the shorter video edge, then composite at the requested anchor
        // with padding. `main_w` / `main_h` are FFmpeg's video dimensions;
        // `overlay_w` / `overlay_h` are the (scaled) overlay dimensions.
        if let overlay {
            let size = max(0.01, min(0.5, overlay.sizeFraction))
            let pad = max(0.0, min(0.2, overlay.paddingFraction))
            let opacity = max(0.0, min(1.0, overlay.opacity))

            // Scale: side = shorter_edge * size. Use `min(iw,ih)` of the main
            // input via `main_w` / `main_h` placeholders by composing two filters.
            // Easier: precompute scaled overlay with -2 to keep aspect.
            let scaleExpr = String(format: "min(iw,ih)*%.3f", size)
            // Apply opacity via colorchannelmixer or format=rgba + colorchannelmixer.
            let alpha = String(format: "%.3f", opacity)

            let xExpr: String
            let yExpr: String
            switch overlay.position {
            case .topLeft:
                xExpr = String(format: "main_w*%.3f", pad)
                yExpr = String(format: "main_h*%.3f", pad)
            case .topRight:
                xExpr = String(format: "main_w-overlay_w-main_w*%.3f", pad)
                yExpr = String(format: "main_h*%.3f", pad)
            case .bottomLeft:
                xExpr = String(format: "main_w*%.3f", pad)
                yExpr = String(format: "main_h-overlay_h-main_h*%.3f", pad)
            case .bottomRight:
                xExpr = String(format: "main_w-overlay_w-main_w*%.3f", pad)
                yExpr = String(format: "main_h-overlay_h-main_h*%.3f", pad)
            case .center:
                xExpr = "(main_w-overlay_w)/2"
                yExpr = "(main_h-overlay_h)/2"
            }

            // Prep overlay: scale + alpha. Reference main video by passing
            // `[concatOut]` first so `main_w`/`main_h` resolve.
            let overlayPrep = "[1:v]format=rgba,colorchannelmixer=aa=\(alpha),scale=\(scaleExpr):-2[ovl]"
            let overlayApply = "[concatOut][ovl]overlay=\(xExpr):\(yExpr):format=auto[outv]"
            parts.append(overlayPrep)
            parts.append(overlayApply)
        }

        // FFmpeg expects filter_complex parts joined by `;` (or newline-equivalent).
        return parts.joined(separator: ";")
    }

    /// Compose the full `ffmpeg` argv string passed straight to
    /// `FFmpegKit.executeAsync`. Encoder is `h264_videotoolbox` (hardware,
    /// not GPL libx264). Soundtrack (when present) is muxed in unmodified
    /// — `-shortest` clamps duration to the video stream so audio doesn't
    /// outrun the montage.
    ///
    /// Input ordering matters because the filter chain references streams
    /// positionally: `[0:v]` = video, `[1:v]` = overlay (if present),
    /// `[2:a]` = soundtrack (if present and overlay is also present),
    /// otherwise `[1:a]`. Audio input is appended last so the index math
    /// stays stable when overlay is absent.
    static func buildCommand(
        inputURL: URL,
        overlayURL: URL? = nil,
        soundtrackURL: URL? = nil,
        outputURL: URL,
        filterComplex: String,
        bitrateMbps: Double
    ) -> String {
        let bitrate = max(1, bitrateMbps)
        var argv: [String] = [
            "-y",
            "-i", quoted(inputURL.path),
        ]
        if let overlayURL {
            // Second input — referenced as [1:v] in filter_complex.
            argv += ["-i", quoted(overlayURL.path)]
        }
        var audioIndex: Int? = nil
        if let soundtrackURL {
            audioIndex = (overlayURL == nil) ? 1 : 2
            argv += ["-i", quoted(soundtrackURL.path)]
        }
        argv += ["-filter_complex", "\"\(filterComplex)\""]
        argv += ["-map", "[outv]"]
        if let audioIndex {
            argv += ["-map", "\(audioIndex):a:0"]
            argv += ["-c:a", "aac_at", "-b:a", "128k", "-shortest"]
        } else {
            argv += ["-an"]
        }
        argv += [
            "-c:v", "h264_videotoolbox",
            "-pix_fmt", "yuv420p",
            "-b:v", String(format: "%.1fM", bitrate),
            "-movflags", "+faststart",
            quoted(outputURL.path),
        ]
        return argv.joined(separator: " ")
    }

    /// FFmpegKit splits the command string on whitespace. Wrap paths in
    /// quotes so spaces (e.g. an event id with a space) don't break parsing.
    private static func quoted(_ path: String) -> String {
        "\"\(path)\""
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
