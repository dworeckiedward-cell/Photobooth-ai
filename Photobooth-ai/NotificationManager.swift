import UserNotifications
import UIKit

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    /// Call once at app launch (Photobooth_aiApp.swift)
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Fire a local notification "Your portrait is ready!"
    /// Fires immediately (timeInterval: 1) — used when app is backgrounded during generation.
    func notifyPhotoReady(eventName: String, styleName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your portrait is ready!"
        content.body = "\(styleName) style — tap to view."
        content.sound = .default
        content.categoryIdentifier = "PHOTO_READY"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "photo-ready-\(UUID().uuidString)"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    /// Cancel all pending photo-ready notifications (when app comes to foreground and user sees result)
    func cancelPhotoReadyNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let ids = reqs.filter { $0.identifier.hasPrefix("photo-ready-") }.map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
