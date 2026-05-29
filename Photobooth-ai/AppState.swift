import SwiftUI
import Observation

/// App-level state — thin shell over `BoothifyAPI`. The webapp is the source of truth;
/// `AppState` holds a small in-memory cache (events list) and the navigation path.
/// Views read from the cache for fast paint, then trigger refreshes async.
@Observable
final class AppState {
    /// Cached events. Populated by `loadRecentEvents()`; updated by `createEvent` /
    /// `refreshEvent`. Views look up events by id with `event(id:)`.
    var events: [Event] = []

    /// Set true while a top-level fetch is in flight (used by the events list to show a spinner).
    var isLoadingEvents = false

    /// Last error from a top-level fetch (events list, create event). Surfaces in UI as a banner.
    var topLevelError: String?

    /// NavigationStack path. Each entry is a Route.
    var path = NavigationPath()

    /// Parallel typed stack mirroring `path`. NavigationPath itself is opaque, so
    /// we track Routes here to support `popUntil(_:)`. System swipe-back can drift
    /// this stack ahead of `path`, so callers must clamp to `path.count`.
    private var routeStack: [Route] = []

    // MARK: - Auth state

    /// The current signed-in session, or nil if signed out. RootView reads this
    /// directly to gate LoginView vs the main app.
    private(set) var session: AuthSession?

    /// True until the launch-time Keychain probe finishes. RootView shows a
    /// splash placeholder while this is true so we don't flash LoginView for a
    /// frame before restoring a valid session.
    private(set) var isAuthLoading: Bool = true

    var currentUser: AuthUser? { session?.user }
    var isAuthenticated: Bool { session != nil }

    /// True when the LoginView gate is bypassed (AppConfig.authGateEnabled == false)
    /// AND there is no real session in memory. Backend-touching methods on AppState
    /// short-circuit in this state so the operator can navigate the UI without
    /// every screen throwing 401s.
    ///
    /// TODO: Re-enable Sign in with Apple before production multi-user launch.
    var isDemoMode: Bool { !AppConfig.authGateEnabled && session == nil }

    /// Called once from `Photobooth_aiApp.task`. Loads any persisted session
    /// from Keychain, wires the BoothifyAPI hooks, and refreshes proactively if
    /// the access token is near expiry.
    func bootstrapAuth() async {
        BoothifyAPI.shared.sessionProvider = { [weak self] in self?.session }
        BoothifyAPI.shared.refreshHandler = { [weak self] in
            await self?.refreshSession()
        }

        if let restored = KeychainStore.loadSession() {
            session = restored
            if restored.isExpired {
                _ = await refreshSession()
            }
        }
        isAuthLoading = false

        // BM1: re-fire any 360 uploads that didn't make it to the cloud
        // before the app was killed. Persistent queue lives in
        // Application Support; dead entries (local file gone) are dropped.
        // Non-blocking — uploads race in the background.
        Booth360UploadQueue.shared.replayPending(app: self)

        // RA2 — restore last active event after crash / force-quit.
        // Fetches recent events synchronously here (small payload, ≤8
        // rows), then if the stashed id matches one of them, pushes
        // straight into its EventHub. Deliberately doesn't restore past
        // the hub — Recording / Settings stay one tap away.
        await restoreLastActiveEvent()
    }

    /// RA2 — pull recent events, find the stashed event, push EventHub.
    /// Safe no-op when:
    /// - no session (anon launch path),
    /// - no stashed id (never been into an event),
    /// - stashed id no longer exists in the recents (event deleted /
    ///   migrated to a different operator account).
    private func restoreLastActiveEvent() async {
        guard isAuthenticated, let stashed = CrashRestoreManager.lastActiveEventId() else { return }
        await loadRecentEvents()
        guard events.contains(where: { $0.id == stashed }) else {
            // Stale stash — wipe so we don't keep re-attempting every launch.
            CrashRestoreManager.clearActiveEvent()
            return
        }
        // Push the hub. Use the generic event hub route since we don't
        // remember whether the operator was in photo or 360 mode last —
        // EventHubView handles photo; Booth360EventHubView handles 360.
        // Default to photo (more common today); operator can swap if needed.
        path.append(Route.eventHub(eventId: stashed))
    }

    /// Persist a freshly minted session (from Apple sign-in). Updates both
    /// in-memory state and Keychain.
    func setSession(_ new: AuthSession) {
        // RA3 — tag this user on Sentry events so we can correlate
        // crashes/errors to specific operators. Only the Supabase uuid
        // is sent; no email, no PII.
        SentryClient.shared.setUser(id: new.user.id)
        SentryClient.shared.breadcrumb("signed in", category: "auth")
        session = new
        try? KeychainStore.saveSession(new)
    }

    /// Refresh against the backend. Returns the new access token on success,
    /// nil on failure (which triggers sign-out in the BoothifyAPI 401 path).
    func refreshSession() async -> String? {
        guard let rt = session?.refreshToken else { return nil }
        do {
            let fresh = try await AuthClient.shared.refresh(refreshToken: rt)
            setSession(fresh)
            return fresh.accessToken
        } catch {
            signOut()
            return nil
        }
    }

    /// Wipe in-memory + Keychain session and reset cached event data. Also
    /// clears Apple's cached profile attributes so a re-login starts clean.
    func signOut() {
        // RA3 — wipe user tag so post-sign-out crashes aren't mis-attributed.
        SentryClient.shared.setUser(id: nil)
        SentryClient.shared.breadcrumb("signed out", category: "auth")
        session = nil
        KeychainStore.clearSession()
        AppleProfileCache.clear()
        events.removeAll()
        path = NavigationPath()
        routeStack.removeAll()
    }

    // MARK: - Event cache lookups

    func event(id: UUID) -> Event? {
        events.first { $0.id == id }
    }

    func event(slug: String) -> Event? {
        events.first { $0.slug == slug }
    }

    // MARK: - Events API

    /// Fetch the most recent events. Called when PhotoboothLandingView appears.
    /// In demo mode (auth gate disabled), keeps the in-memory list as-is.
    func loadRecentEvents() async {
        if isDemoMode {
            topLevelError = nil
            return
        }
        isLoadingEvents = true
        defer { isLoadingEvents = false }
        do {
            events = try await BoothifyAPI.shared.listRecentEvents()
            topLevelError = nil
        } catch {
            topLevelError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Create a new event, insert into cache, return it.
    /// In demo mode, builds the event locally without calling the backend so
    /// the operator can walk through the navigation flow.
    @discardableResult
    func createEvent(name: String) async throws -> Event {
        let event: Event
        if isDemoMode {
            event = Event.localDemo(name: name)
            events.insert(event, at: 0)
        } else {
            event = try await BoothifyAPI.shared.createEvent(name: name)
            events.insert(event, at: 0)
        }

        // IM3: seed per-event settings from onboarding answers (if any) so
        // the operator's stated preferences actually take effect on the very
        // first event without them having to dig through settings.
        if let answers = OnboardingStore.lastAnswers {
            var settings = EventSettings.default
            if let raw = answers.preferredTemplateRawDuration {
                settings.ai360.recordingDurationSeconds = raw
            }
            if let branding = answers.branding {
                switch branding {
                case .clientLogo:
                    settings.brandOverlay.enabled = true
                    settings.brandOverlay.logoSource = .uploaded
                case .eventName:
                    settings.brandOverlay.enabled = true
                    settings.brandOverlay.logoSource = .textFallback
                    settings.brandOverlay.overlayText = name.uppercased()
                case .none:
                    break
                }
            }
            updateSettings(settings, for: event.id)
        }

        return event
    }

    /// Refresh a single event (e.g. when entering EventHub to get fresh photo counts).
    /// No-op in demo mode — the local event is the source of truth.
    func refreshEvent(slug: String) async {
        if isDemoMode { return }
        do {
            let event = try await BoothifyAPI.shared.getEvent(slug: slug)
            if let idx = events.firstIndex(where: { $0.id == event.id }) {
                events[idx] = event
            } else {
                events.insert(event, at: 0)
            }
        } catch {
            // Swallow — refresh failures shouldn't block UI. Hub view already shows
            // cached version. Surface via toast later.
        }
    }

    // MARK: - Cloud status (IM2)
    //
    // Cache keyed by event id so the EventHub panel reads a stable snapshot
    // while a background refresh runs. Refresh hits the backend first; on
    // failure (404 / network) we compose a local snapshot from the in-memory
    // `Booth360Job` cache + `Event.completedPhotos`.

    var cloudStatusCache: [UUID: EventCloudStatus] = [:]

    func cloudStatus(for eventId: UUID) -> EventCloudStatus {
        cloudStatusCache[eventId] ?? localCloudStatus(for: eventId)
    }

    /// Background refresh — tries the backend, falls back to local compute.
    /// Safe to call repeatedly; throttling left to callers.
    func refreshCloudStatus(for eventId: UUID) async {
        // Optimistic local snapshot so the panel paints immediately on first open.
        cloudStatusCache[eventId] = localCloudStatus(for: eventId)

        guard isAuthenticated, let event = self.event(id: eventId) else { return }
        do {
            let remote = try await BoothifyAPI.shared.eventStatus(slug: event.slug)
            cloudStatusCache[eventId] = remote
        } catch {
            // Backend not deployed / network blip — keep the local snapshot.
            // Surface via topLevelError only if it persists (skipped for now).
        }
    }

    /// Pure local rollup. Source of truth in demo mode + on any backend
    /// failure. Counts:
    ///   - queued: jobs `.idle` or `.queued`
    ///   - uploading: jobs `.uploading`
    ///   - done: jobs `.completed` + photos `completed_photos` on the event
    ///   - sent: 0 (local SMS log not implemented; backend owns this)
    private func localCloudStatus(for eventId: UUID) -> EventCloudStatus {
        let eventJobs = jobs(for: eventId)
        let queued = eventJobs.filter { $0.status == .idle || $0.status == .queued }.count
        let uploading = eventJobs.filter { $0.status == .uploading || $0.status == .processing }.count
        let completedJobs = eventJobs.filter { $0.status == .completed }.count
        let completedPhotos = event(id: eventId)?.completedPhotos ?? 0
        return EventCloudStatus(
            queued: queued,
            uploading: uploading,
            done: completedJobs + completedPhotos,
            sent: 0
        )
    }

    // MARK: - Navigation

    func push(_ route: Route) {
        path.append(route)
        routeStack.append(route)
    }

    func popToRoot() {
        path.removeLast(path.count)
        routeStack.removeAll()
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
        if !routeStack.isEmpty { routeStack.removeLast() }
    }

    /// Pop screens off the stack until the predicate matches (target stays on top).
    /// Used to return to a known screen from an unknown depth (e.g. Result → EventHub
    /// across Processing + Result intermediates). Clamps to `path.count` so a drifted
    /// `routeStack` after swipe-back can't underflow the NavigationPath.
    func popUntil(_ predicate: (Route) -> Bool) {
        var pops = 0
        var i = routeStack.count - 1
        while i >= 0, !predicate(routeStack[i]) {
            pops += 1
            i -= 1
        }
        guard i >= 0 else { return }
        let actualPops = min(pops, path.count)
        if actualPops > 0 {
            path.removeLast(actualPops)
            routeStack.removeLast(min(actualPops, routeStack.count))
        }
    }

    // MARK: - Per-event settings
    //
    // MVP: persist to UserDefaults as JSON keyed by event id. When the backend grows
    // a `settings JSONB` column we'll sync this same struct up via PATCH /api/events/[slug].
    //
    // Observable-aware: `settingsCache` is tracked, so reading via `settings(for:)`
    // and mutating via `updateSettings(_:for:)` propagates to views automatically.

    private static let settingsKeyPrefix = "boothify.event.settings."

    var settingsCache: [UUID: EventSettings] = [:]

    func settings(for eventId: UUID) -> EventSettings {
        if let cached = settingsCache[eventId] { return cached }
        let key = Self.settingsKeyPrefix + eventId.uuidString
        let loaded: EventSettings
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(EventSettings.self, from: data) {
            loaded = decoded
        } else {
            loaded = .default
        }
        settingsCache[eventId] = loaded
        return loaded
    }

    func updateSettings(_ settings: EventSettings, for eventId: UUID) {
        settingsCache[eventId] = settings
        let key = Self.settingsKeyPrefix + eventId.uuidString
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Wipes all locally-persisted settings for an event (Account → Reset).
    func resetSettings(for eventId: UUID) {
        settingsCache.removeValue(forKey: eventId)
        let key = Self.settingsKeyPrefix + eventId.uuidString
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Survey responses (MVP local store)

    private static let surveyKeyPrefix = "boothify.event.surveys."

    var surveyResponsesCache: [UUID: [SurveyResponse]] = [:]

    func surveyResponses(for eventId: UUID) -> [SurveyResponse] {
        if let cached = surveyResponsesCache[eventId] { return cached }
        let key = Self.surveyKeyPrefix + eventId.uuidString
        let loaded: [SurveyResponse]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SurveyResponse].self, from: data) {
            loaded = decoded
        } else {
            loaded = []
        }
        surveyResponsesCache[eventId] = loaded
        return loaded
    }

    func appendSurveyResponse(_ response: SurveyResponse, for eventId: UUID) {
        var current = surveyResponses(for: eventId)
        current.append(response)
        surveyResponsesCache[eventId] = current
        let key = Self.surveyKeyPrefix + eventId.uuidString
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Consent log (MVP local store)

    private static let consentKeyPrefix = "boothify.event.consent."

    var consentLogCache: [UUID: [ConsentRecord]] = [:]

    func consentLog(for eventId: UUID) -> [ConsentRecord] {
        if let cached = consentLogCache[eventId] { return cached }
        let key = Self.consentKeyPrefix + eventId.uuidString
        let loaded: [ConsentRecord]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ConsentRecord].self, from: data) {
            loaded = decoded
        } else {
            loaded = []
        }
        consentLogCache[eventId] = loaded
        return loaded
    }

    func recordConsent(for eventId: UUID) {
        var current = consentLog(for: eventId)
        current.append(ConsentRecord(
            acceptedAt: .now,
            deviceName: UIDevice.current.name
        ))
        consentLogCache[eventId] = current
        let key = Self.consentKeyPrefix + eventId.uuidString
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func resetConsent(for eventId: UUID) {
        consentLogCache.removeValue(forKey: eventId)
        let key = Self.consentKeyPrefix + eventId.uuidString
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - 360 AI Booth job store (frontend MVP — in-memory)
    //
    // When the backend ships, replace these with API-backed reads/writes plus a
    // local cache. View code already reads via `job(id:)` / `jobs(for:)`, so
    // swapping the implementation is a single-layer change.

    var booth360Jobs: [UUID: Booth360Job] = [:]

    func job(id: UUID) -> Booth360Job? { booth360Jobs[id] }

    func upsertJob(_ job: Booth360Job) { booth360Jobs[job.id] = job }

    func jobs(for eventId: UUID) -> [Booth360Job] {
        booth360Jobs.values
            .filter { $0.eventId == eventId }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Routes for NavigationStack

enum Route: Hashable {
    case photoboothLanding
    case eventHub(eventId: UUID)
    case camera(eventId: UUID)
    case stylePicker(eventId: UUID, capturedImageData: Data)
    case result(eventId: UUID, photoId: UUID)
    case gallery(eventId: UUID)
    case slideshow(eventId: UUID)

    // Settings tree — each subsection has its own dedicated route so deep links work.
    case settingsHub(eventId: UUID)
    case settingsCapture(eventId: UUID)
    case settingsCamera(eventId: UUID)
    case settingsAIPortraits(eventId: UUID)
    case settingsAI360(eventId: UUID)
    case settingsEffects(eventId: UUID)
    case settingsSharing(eventId: UUID)
    case settingsEmailSMS(eventId: UUID)
    case settingsLockPin(eventId: UUID)
    case settingsGallerySlideshow(eventId: UUID)

    // MVP add-ons (formerly Coming Soon)
    case settingsPrint(eventId: UUID)
    case settingsBackgroundRemoval(eventId: UUID)
    case settingsStickers(eventId: UUID)
    case settingsVirtualAttendant(eventId: UUID)
    case settingsDisclaimer(eventId: UUID)
    case settingsSurvey(eventId: UUID)
    case settingsSharingStatus(eventId: UUID)
    case settingsAccount(eventId: UUID)

    case settingsComingSoon(title: String, blurb: String)
    case aboutBoothify

    // 360 AI Booth flow (frontend MVP, backend-ready)
    case booth360Landing
    case booth360EventHub(eventId: UUID)
    case booth360Recording(eventId: UUID)
    case booth360Processing(jobId: UUID)
    case booth360Result(jobId: UUID)
    case settings360Hub(eventId: UUID)
}
