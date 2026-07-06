import Foundation
import AVFoundation
import os.log

/// Phase 3 — the REAL render client behind `Booth360RenderClient`. Replaces
/// Passthrough as the default at the single concrete call-site.
///
/// Responsibilities (the engine stays pure; this owns the messy edges):
/// - job status/step/progress bookkeeping on the MainActor
/// - StorageLifecycle: master placement, raw purge on success, per-event cap
/// - kicking the cloud upload after render (restores the initiation the
///   deleted FFmpeg client used to own — see DECISIONS_LOG Phase 3)
/// - graceful failure: status .failed + operator-legible message; raw KEPT on
///   failure so a retry is possible
@MainActor
final class Booth360NativeRenderClient: Booth360RenderClient {
    static let shared = Booth360NativeRenderClient()
    private init() {}

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "NativeRender")

    func runPipeline(jobId: UUID, app: AppState) async {
        guard var job = app.job(id: jobId) else { return }

        // No raw file (simulator without camera) → Mock keeps the UI honest
        // and alive, same contract as Passthrough had.
        guard let rawURL = job.rawVideoLocalURL,
              FileManager.default.fileExists(atPath: rawURL.path) else {
            await MockBooth360RenderClient.shared.runPipeline(jobId: jobId, app: app)
            return
        }

        func update(_ mutate: (inout Booth360Job) -> Void) {
            guard var j = app.job(id: jobId) else { return }
            mutate(&j)
            app.upsertJob(j)
        }

        let storage = StorageLifecycle.shared
        storage.prepare(eventId: job.eventId)
        let masterURL = storage.masterURL(eventId: job.eventId, jobId: jobId)

        update {
            $0.status = .processing
            $0.currentStep = .stabilizing
            $0.progress = 0.05
        }

        let spec = RenderSpec.default
        do {
            update { $0.currentStep = .slowMotion; $0.progress = 0.1 }

            // Progress callbacks arrive off-main; hop back for the observable job.
            try await Booth360RenderEngine.render(
                input: rawURL,
                spec: spec,
                to: masterURL,
                progress: { fraction in
                    Task { @MainActor in
                        guard var j = app.job(id: jobId), !j.status.isTerminal else { return }
                        j.currentStep = .cinematicEffects
                        // Map export 0…1 into the 10…90% band of the job bar.
                        j.progress = 0.1 + fraction * 0.8
                        app.upsertJob(j)
                    }
                }
            )

            if Task.isCancelled { return }
            update { $0.currentStep = .sharePage; $0.progress = 0.95 }

            // Success bookkeeping — master in place, raw is disposable now.
            storage.purgeRaw(jobId: jobId)
            let evicted = storage.enforceMasterCap(eventId: job.eventId)
            if evicted > 0 {
                log.notice("master cap evicted \(evicted) old clips for event \(job.eventId.uuidString, privacy: .public)")
            }

            update {
                $0.status = .completed
                $0.currentStep = nil
                $0.progress = 1
                $0.completedAt = .now
                $0.finalVideoURL = masterURL
                // publicShareURL stays nil until the uploader confirms the REAL
                // link — no more mock links (delivery must be honest).
            }

            // Restore upload initiation (was owned by the removed FFmpeg client).
            Booth360CloudUploader.shared.enqueue(jobId: jobId, app: app)
        } catch is CancellationError {
            return
        } catch let error as Booth360RenderEngineError {
            if case .cancelled = error { return }
            log.error("render failed for \(jobId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            update {
                $0.status = .failed
                $0.currentStep = nil
                $0.errorMessage = error.errorDescription ?? "Render failed."
                // Raw is kept — the operator can retry without re-shooting.
            }
        } catch {
            log.error("render failed for \(jobId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            update {
                $0.status = .failed
                $0.currentStep = nil
                $0.errorMessage = "Render failed: \(error.localizedDescription)"
            }
        }
    }
}
