import Foundation
import os.log

#if canImport(Sentry)
import Sentry
#endif

/// RA3 — thin wrapper around the Sentry iOS SDK.
///
/// Why wrap: lets the rest of the codebase reference one `SentryClient.shared`
/// instead of `import Sentry` everywhere; makes the dependency easy to
/// stub-out for unit tests later; lets `start()` no-op cleanly when the
/// DSN env is unset (dev / CI / first install before the operator wires
/// the project on sentry.io).
///
/// DSN discovery: `Info.plist` key `BOOTHIFY_SENTRY_DSN` → falls back to
/// disabled. We do NOT hardcode a DSN — see TODO-HUMAN.md.
///
/// PII: `sendDefaultPii = false` so we don't auto-collect emails or IPs.
/// We attach a userId (Supabase uuid) once auth lands; nothing else.
@MainActor
final class SentryClient {
    static let shared = SentryClient()

    private(set) var isEnabled: Bool = false
    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Sentry")

    private init() {}

    /// Call from `Photobooth_aiApp.init` (before any other SDK work).
    /// Safe to call multiple times — only the first init takes.
    func start() {
        #if canImport(Sentry)
        guard !isEnabled else { return }
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "BOOTHIFY_SENTRY_DSN") as? String,
              !dsn.isEmpty, dsn.hasPrefix("https://") else {
            log.notice("Sentry disabled — no DSN configured. Set BOOTHIFY_SENTRY_DSN in Info.plist.")
            return
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let env: String
        #if DEBUG
        env = "debug"
        #else
        env = "release"
        #endif

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = env
            options.releaseName = "boothify-ios@\(version)+\(build)"
            options.sendDefaultPii = false
            // Crashes + unhandled exceptions captured automatically.
            options.enableAutoBreadcrumbTracking = true
            // We don't want UI noise — disable user-interaction breadcrumbs
            // (taps + swipes). Our manual breadcrumbs are higher signal.
            options.enableUserInteractionTracing = false
            // Tracing: low sample rate, just enough to spot real perf regressions
            options.tracesSampleRate = 0.1
        }
        isEnabled = true
        log.notice("Sentry started for env=\(env, privacy: .public) release=boothify-ios@\(version, privacy: .public)+\(build, privacy: .public)")
        #else
        log.notice("Sentry module unavailable — skipping init.")
        #endif
    }

    /// Capture a non-fatal error with optional structured context. Returns
    /// silently if Sentry isn't enabled.
    func capture(_ error: Error, context: [String: Any]? = nil) {
        #if canImport(Sentry)
        guard isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            if let context, !context.isEmpty {
                scope.setContext(value: context, key: "boothify")
            }
        }
        #endif
    }

    /// Capture a synthetic message (e.g. "thermal critical for 5min").
    /// Useful for non-error events worth observing.
    func captureMessage(_ message: String, level: SeverityLevel = .info) {
        #if canImport(Sentry)
        guard isEnabled else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level.sentryLevel)
        }
        #endif
    }

    /// Add a navigation / state breadcrumb. Cheap; show up in the next event's
    /// timeline. Use sparingly on major flow points (start recording, upload
    /// succeeded, share opened) — not on every tap.
    func breadcrumb(_ message: String, category: String = "flow", data: [String: Any]? = nil) {
        #if canImport(Sentry)
        guard isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        if let data { crumb.data = data }
        SentrySDK.addBreadcrumb(crumb)
        #endif
    }

    /// Attach the signed-in user's uuid. Email and other PII are NOT sent
    /// (`sendDefaultPii = false`). Clear by passing nil after sign-out.
    func setUser(id: String?) {
        #if canImport(Sentry)
        guard isEnabled else { return }
        SentrySDK.configureScope { scope in
            if let id {
                let user = User(userId: id)
                scope.setUser(user)
            } else {
                scope.setUser(nil)
            }
        }
        #endif
    }

    /// Severity level abstraction — Sentry's `SentryLevel` enum is ObjC
    /// flavour; we wrap so callers don't import.
    enum SeverityLevel {
        case debug, info, warning, error, fatal

        #if canImport(Sentry)
        var sentryLevel: SentryLevel {
            switch self {
            case .debug:   .debug
            case .info:    .info
            case .warning: .warning
            case .error:   .error
            case .fatal:   .fatal
            }
        }
        #endif
    }
}
