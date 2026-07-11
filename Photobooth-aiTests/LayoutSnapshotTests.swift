import XCTest
import SwiftUI
@testable import Photobooth_ai

/// LAYOUT-run harness: renders every redesigned screen into a PNG so the
/// composition gate (brief §4 — breathing room, one dominant, no brick-walls)
/// can be checked against real layout output, including screens that sit
/// behind the backend (hub, processing, result) and are unreachable in a
/// plain simulator session.
///
/// Pure scaffolding — no assertions on pixels, it only fails if a screen
/// cannot render at all. Output dir: SNAPSHOT_DIR env (pass via
/// TEST_RUNNER_SNAPSHOT_DIR) or the test host's tmp directory.
@MainActor
final class LayoutSnapshotTests: XCTestCase {
    private static let size = CGSize(width: 393, height: 852)   // iPhone 15/16/17 point grid

    private var outputDir: URL {
        let base = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base, isDirectory: true)
    }

    private func snapshot(_ name: String, @ViewBuilder content: () -> some View) throws {
        let host = UIHostingController(rootView: AnyView(content()))
        // Attach to the test host's window scene — an orphan UIWindow renders
        // blank through drawHierarchy.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: Self.size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        // Let onAppear / .task-driven first paint settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let renderer = UIGraphicsImageRenderer(size: Self.size)
        var image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        // Fallback: some configurations still return an empty snapshot —
        // render the layer tree directly (misses live materials, keeps layout).
        if image.isBlank {
            image = renderer.image { ctx in
                window.layer.render(in: ctx.cgContext)
            }
        }
        guard let data = image.pngData() else { XCTFail("png encode failed: \(name)"); return }
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let url = outputDir.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("SNAPSHOT \(name): \(url.path)")
        window.isHidden = true
    }

    // MARK: - State factories

    private func makeEvent(name: String, daysAgo: Int = 0) -> Event {
        Event(
            id: UUID(), name: name, slug: name.lowercased().replacingOccurrences(of: " ", with: "-"),
            totalPhotos: 0, completedPhotos: 0, failedPhotos: nil, maxPhotos: nil,
            isActive: true, brandingLogoUrl: nil, expiresAt: nil,
            createdAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            thumbnailUrl: nil, shareMode: nil
        )
    }

    private func makeJob(app: AppState, eventId: UUID,
                         status: Booth360RenderStatus,
                         step: Booth360ProcessingStep? = nil,
                         progress: Double = 0,
                         shared: Bool = false) -> Booth360Job {
        var job = Booth360Job(
            eventId: eventId,
            settingsSnapshot: app.settings(for: eventId).ai360,
            brandOverlay: app.settings(for: eventId).brandOverlay
        )
        job.status = status
        job.currentStep = step
        job.progress = progress
        if shared {
            job.publicShareURL = URL(string: "https://boothify.app/v/a1b2c3d4")
            job.cloudUploadStatus = .uploaded
        }
        app.upsertJob(job)
        return job
    }

    // MARK: - Screens

    func test_renderAllScreens() throws {
        // Opt-in only (TEST_RUNNER_SNAPSHOT_DIR=… xcodebuild test -only-testing:…):
        // rendering live screens spins up background AVFoundation work that
        // must never share a test-host process with the render-engine suites.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil,
            "snapshot harness is opt-in — set TEST_RUNNER_SNAPSHOT_DIR"
        )

        // Jobs are persisted now — wipe the store so this harness is
        // deterministic across runs (emptyApp must be truly empty).
        UserDefaults.standard.removeObject(forKey: "boothify.booth360Jobs.v1")

        // Landing — empty and populated.
        let emptyApp = AppState()
        emptyApp.booth360Jobs = [:]
        emptyApp.currentEventId = nil
        try snapshot("landing_empty") {
            NavigationStack { Booth360LandingView() }.environment(emptyApp)
        }

        let app = AppState()
        let wedding = makeEvent(name: "Anna and Tom", daysAgo: 1)
        let corpo = makeEvent(name: "Servify Summit", daysAgo: 6)
        app.events = [wedding, corpo]
        // Live-event marker: the wedding runs at the booth → landing shows
        // the Continue banner, its hub shows LIVE + End event.
        app.currentEventId = wedding.id
        _ = makeJob(app: app, eventId: wedding.id, status: .completed, shared: true)
        _ = makeJob(app: app, eventId: wedding.id, status: .processing, step: .slowMotion, progress: 0.42)
        try snapshot("landing_events") {
            NavigationStack { Booth360LandingView() }.environment(app)
        }

        // Event hub.
        try snapshot("hub") {
            NavigationStack { Booth360EventHubView(eventId: wedding.id) }.environment(app)
        }

        // Attract (kiosk).
        try snapshot("attract") {
            KioskAttractView(eventId: wedding.id).environment(app)
        }

        // Processing — mid-render. (Its .task calls startRender; with no raw
        // file the state may advance async — the snapshot is layout-only.)
        let processingJob = makeJob(app: app, eventId: wedding.id, status: .processing,
                                    step: .cinematicEffects, progress: 0.63)
        try snapshot("processing") {
            NavigationStack { Booth360ProcessingView(jobId: processingJob.id) }.environment(app)
        }

        // Result — completed, link ready, no local file (placeholder preview).
        let doneJob = makeJob(app: app, eventId: wedding.id, status: .completed, shared: true)
        try snapshot("result") {
            NavigationStack { Booth360ResultView(jobId: doneJob.id) }.environment(app)
        }

        // Settings hub.
        try snapshot("settings") {
            NavigationStack { SettingsHubView(eventId: wedding.id, mode: .ai360) }.environment(app)
        }

        // Events calendar (glass pane + agenda).
        try snapshot("calendar") {
            NavigationStack { EventsCalendarView() }.environment(app)
        }
    }
}

private extension UIImage {
    /// Cheap blank-detector: samples a small thumbnail and checks whether
    /// every pixel is (near-)white or fully transparent.
    var isBlank: Bool {
        let side = 8
        guard let cg = cgImage else { return true }
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx?.data else { return true }
        let buf = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for i in 0..<(side * side) {
            let r = buf[i*4], g = buf[i*4+1], b = buf[i*4+2], a = buf[i*4+3]
            if a > 8 && (r < 245 || g < 245 || b < 245) { return false }
        }
        return true
    }
}
