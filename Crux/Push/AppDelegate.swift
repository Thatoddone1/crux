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

    /// The actions the extension's notifications opt into. No action requires
    /// authentication, so all of them work straight from the lock screen.
    private static var messageCategory: UNNotificationCategory {
        let reply = UNTextInputNotificationAction(identifier: AppConfiguration.Push.replyAction,
                                                  title: "Reply",
                                                  options: [],
                                                  textInputButtonTitle: "Send",
                                                  textInputPlaceholder: "Message")
        let reactions = AppConfiguration.Push.reactions.map {
            UNNotificationAction(identifier: AppConfiguration.Push.reactionAction(for: $0),
                                 title: $0,
                                 options: [])
        }
        return UNNotificationCategory(identifier: AppConfiguration.Push.messageCategory,
                                      actions: [reply] + reactions,
                                      intentIdentifiers: [],
                                      options: [])
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Don't banner a room the user is already reading.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let roomId = roomId(in: notification), roomId == router.visibleRoomId else {
            return [.banner, .sound, .list]
        }
        return []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let roomId = userInfo[AppConfiguration.Push.roomIdKey] as? String else { return }
        let eventId = userInfo[AppConfiguration.Push.eventIdKey] as? String

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            router.open(roomId: roomId)

        case AppConfiguration.Push.replyAction:
            guard let reply = response as? UNTextInputNotificationResponse else { return }
            await inBackground { await self.matrix.sendMessage(reply.userText, in: roomId) }

        default:
            guard let key = AppConfiguration.Push.reactionKey(forAction: response.actionIdentifier),
                  let eventId else { return }
            await inBackground { await self.matrix.react(key, toEvent: eventId, in: roomId) }
        }
    }

    /// An action wakes the app with no UI, and it may be killed as soon as this
    /// returns — the assertion buys enough time to queue the send.
    private func inBackground(_ work: () async -> Void) async {
        let task = UIApplication.shared.beginBackgroundTask(withName: "Notification action")
        await work()
        UIApplication.shared.endBackgroundTask(task)
    }

    private func roomId(in notification: UNNotification) -> String? {
        notification.request.content.userInfo[AppConfiguration.Push.roomIdKey] as? String
    }
}
