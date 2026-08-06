//
//  PushModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK
import UIKit
import UserNotifications

/// Owns the APNs registration and the Matrix pusher that points the homeserver
/// at our push gateway.
@Observable
final class PushModel {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The token and the session arrive in either order, so the pusher is only
    /// registered once both are known.
    private var deviceToken: Data?
    private weak var client: Client?

    
    static func clearDeliveredNotifications(forRoom roomId: String) async {
        let ids = await UNUserNotificationCenter.current().deliveredNotifications()
            .filter { $0.request.content.threadIdentifier == roomId }
            .map(\.request.identifier)
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    /// Prompts the first time the user reaches the signed-in app. iOS only shows
    /// the system alert while the status is undetermined, so this is a no-op afterwards.
    func requestAuthorizationIfNeeded() async {
        await refresh()
        guard authorizationStatus == .notDetermined else { return }
        await requestAuthorization()
    }

    /// APNs tokens rotate on device restore or reinstall, so this runs at every
    /// launch rather than only when permission is first granted.
    func refresh() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard authorizationStatus == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func setDeviceToken(_ token: Data) {
        deviceToken = token
        Task { await registerPusher() }
    }

    func signedIn(_ client: Client) {
        self.client = client
        Task { await registerPusher() }
    }

    func signingOut(_ client: Client) async {
        defer { self.client = nil }
        guard let deviceToken else { return }
        try? await client.deletePusher(identifiers: identifiers(for: deviceToken))
    }

    private func registerPusher() async {
        guard let client, let deviceToken else { return }

        // Sygnal decodes the pushkey from base64 before handing it to APNs.
        let data = HttpPusherData(url: AppConfiguration.Push.gatewayURL,
                                  format: .eventIdOnly,
                                  defaultPayload: AppConfiguration.Push.defaultPayload)
        try? await client.setPusher(identifiers: identifiers(for: deviceToken),
                                    kind: .http(data: data),
                                    appDisplayName: AppConfiguration.clientName,
                                    deviceDisplayName: UIDevice.current.name,
                                    profileTag: nil,
                                    lang: Locale.current.language.languageCode?.identifier ?? "en",
                                    append: false)
    }

    private func identifiers(for token: Data) -> PusherIdentifiers {
        PusherIdentifiers(pushkey: token.base64EncodedString(), appId: AppConfiguration.Push.appId)
    }
}
