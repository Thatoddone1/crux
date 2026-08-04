//
//  NotificationService.swift
//  CruxNSE
//

import MatrixRustSDK
import UserNotifications

/// Decrypts an incoming push and replaces the placeholder the gateway sent.
///
/// The push itself only carries a room and event id, so everything the user
/// reads is fetched and decrypted here, inside a 30-second budget.
final class NotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var fallback = UNNotificationContent()

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        lock.withLock {
            self.contentHandler = contentHandler
            self.fallback = request.content
        }

        let userInfo = request.content.userInfo
        guard let roomId = userInfo[AppConfiguration.Push.roomIdKey] as? String,
              let eventId = userInfo[AppConfiguration.Push.eventIdKey] as? String else {
            return deliver(request.content)
        }

        Task {
            deliver(await content(roomId: roomId, eventId: eventId, badge: request.content.badge))
        }
    }

    override func serviceExtensionTimeWillExpire() {
        deliver(nil)
    }

    private func content(roomId: String, eventId: String, badge: NSNumber?) async -> UNNotificationContent? {
        guard let result = try? await NotificationSession.shared.notification(roomId: roomId,
                                                                             eventId: eventId) else { return nil }

        switch result.status {
        case .event(let item):
            return await NotificationContentBuilder.content(for: item,
                                                            roomId: roomId,
                                                            eventId: eventId,
                                                            badge: badge,
                                                            client: result.client)
        // Muted by a push rule, sent by an ignored user, or since deleted.
        case .eventFilteredOut, .eventRedacted:
            return NotificationContentBuilder.suppressed
        case .eventNotFound:
            return nil
        }
    }

    /// Always runs exactly once — iOS shows nothing and eventually throttles the
    /// app if the handler is skipped, and expiry can race a successful fetch.
    private func deliver(_ content: UNNotificationContent?) {
        let handler = lock.withLock {
            defer { contentHandler = nil }
            return contentHandler
        }
        handler?(content ?? fallback)
    }
}
