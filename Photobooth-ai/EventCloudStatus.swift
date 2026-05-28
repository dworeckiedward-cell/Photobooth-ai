import Foundation

/// IM2: lightweight rollup of an event's media-pipeline state. Shown during
/// the event so the operator can answer "where's everyone's video / photo".
///
/// Wire format matches a future `GET /api/events/{slug}/status` endpoint. iOS
/// silently falls back to a locally-computed snapshot built from the in-memory
/// `Booth360Job` cache + photo counts on the cached `Event`, so the panel is
/// always populated.
struct EventCloudStatus: Codable, Hashable, Sendable {
    /// Items waiting in line (uploaded, awaiting render or backend pickup).
    var queued: Int
    /// Items actively uploading from this device.
    var uploading: Int
    /// Items finished rendering and available to share.
    var done: Int
    /// SMS / link sends recorded (backend-tracked; locally we report 0 since
    /// we don't have a delivery log yet).
    var sent: Int

    static let empty = EventCloudStatus(queued: 0, uploading: 0, done: 0, sent: 0)
}
