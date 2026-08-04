//
//  AppDelegate.swift
//  Crux
//

import SwiftUI
import UserNotifications

/// Hosts the objects that outlive the scene. A notification can be delivered,
/// tapped or replied to before any UI exists, so these can't live in a view.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let push = PushModel()
    let router = AppRouter()
    private(set) lazy var matrix = MatrixService(push: push)

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([Self.messageCategory])

        Task { await push.refresh() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.setDeviceToken(deviceToken)
    }

    /// The inline reply field the extension's notifications opt into.
    private static var messageCategory: UNNotificationCategory {
        let reply = UNTextInputNotificationAction(identifier: AppConfiguration.Push.replyAction,
                                                  title: "Reply",
                                                  options: [],
                                                  textInputButtonTitle: "Send",
                                                  textInputPlaceholder: "Message")
        return UNNotificationCategory(identifier: AppConfiguration.Push.messageCategory,
                                      actions: [reply],
                                      intentIdentifiers: [],
                                      options: [])
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Don't banner a room the user is already reading.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        roomId(in: notification) == router.visibleRoomId ? [] : [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let roomId = roomId(in: response.notification) else { return }

        guard let reply = response as? UNTextInputNotificationResponse,
              let eventId = response.notification.request.content
                  .userInfo[AppConfiguration.Push.eventIdKey] as? String else {
            return router.open(roomId: roomId)
        }

        // The app was woken with no UI, and may be killed as soon as this
        // returns — the assertion buys enough time to queue the message.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Quick reply")
        await matrix.sendReply(reply.userText, toEvent: eventId, in: roomId)
        UIApplication.shared.endBackgroundTask(task)
    }

    private func roomId(in notification: UNNotification) -> String? {
        notification.request.content.userInfo[AppConfiguration.Push.roomIdKey] as? String
    }
}
