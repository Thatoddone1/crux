//
//  RoomStore.swift
//  Crux
//

import Foundation
import MatrixRustSDK

///hands out room models
@Observable
@MainActor
final class RoomStore {
    private let client: Client

    /// The account-wide defaults every room without its own setting inherits.
    private(set) var notificationDefaults = NotificationDefaults()

    private var models: [String: RoomModel] = [:]
    /// How many holders (the room list, plus each view showing the room) want each
    /// model kept alive.
    private var holders: [String: Int] = [:]

    /// Rooms whose timeline is open but which nothing is showing any more, oldest
    /// first. A started timeline is a Rust timeline plus a listener, so these are
    /// capped; the models themselves stay live and keep counting unread.
    private var idleTimelines: [String] = []
    private static let openTimelineLimit = 8

    private var settings: NotificationSettings?
    private var settingsDelegateInstalled = false

    init(client: Client) {
        self.client = client
    }

    // MARK: Models

    /// The room's model, if anything is currently holding it.
    func model(for roomId: String) -> RoomModel? { models[roomId] }

    /// Takes a hold on a room, creating its model the first time. Every call must
    /// be paired with `release(_:)`.
    @discardableResult
    func retain(_ room: Room) -> RoomModel {
        let id = room.id()
        holders[id, default: 0] += 1
        idleTimelines.removeAll { $0 == id }

        if let existing = models[id] { return existing }
        let model = RoomModel(room: room, client: client)
        models[id] = model
        model.notificationDefaults = notificationDefaults
        if let settings { model.use(settings) }
        model.startSubscriptions()
        return model
    }

    /// Drops one holder's interest. The model — and with it the room's
    /// subscription and timeline — goes away once no one is left holding it.
    func release(_ roomId: String) {
        guard let count = holders[roomId] else { return }
        if count > 1 {
            holders[roomId] = count - 1
            return
        }
        holders[roomId] = nil
        idleTimelines.removeAll { $0 == roomId }
        models.removeValue(forKey: roomId)?.stop()
    }

    // MARK: Timelines
    //
    // `TimelineModel.start()/stop()` do the actual work. These two decide *when*
    // — which is a decision about the whole app, not about one room, so it lives
    // here and views go through `openRoom` rather than starting a timeline
    // themselves.

    /// Opens a room's timeline for a view about to show its messages. The room
    /// list never calls this: that's what keeps a few hundred listed rooms from
    /// opening a few hundred timelines.
    func openTimeline(_ roomId: String) async {
        idleTimelines.removeAll { $0 == roomId }
        try? await models[roomId]?.timeline.start()
    }

    /// Gives up a view's claim on a timeline. It stays open so stepping back into
    /// the room keeps its scrollback, until enough other rooms push it out.
    func closeTimeline(_ roomId: String) {
        guard models[roomId] != nil else { return }
        idleTimelines.removeAll { $0 == roomId }
        idleTimelines.append(roomId)
        while idleTimelines.count > Self.openTimelineLimit {
            models[idleTimelines.removeFirst()]?.timeline.stop()
        }
    }

    // MARK: Notifications

    /// Loads the account defaults and keeps them current. Without them, rooms
    /// muted by the account default read as unmuted
    func startNotifications() async {
        let settings: NotificationSettings
        if let existing = self.settings {
            settings = existing
        } else {
            settings = await client.getNotificationSettings()
            self.settings = settings
        }
        for model in models.values { model.use(settings) }

        if !settingsDelegateInstalled {
            settingsDelegateInstalled = true
            let delegate = NotificationSettingsBridge { [weak self] in
                guard let store = self else { return }
                Task { @MainActor in
                    await store.reloadNotificationDefaults()
                    // The delegate fires for *any* push rule change, including a
                    // room's own setting changed from another client — which
                    // nothing else would tell us about.
                    for model in store.models.values { model.refreshNotificationOverride() }
                }
            }
            settings.setDelegate(delegate: delegate)
        }
        await reloadNotificationDefaults()
    }

    /// Re-reads the account defaults and pushes them into every live room, which
    /// re-derives each room's effective mode off the new baseline.
    func reloadNotificationDefaults() async {
        guard let settings else { return }

        var defaults = NotificationDefaults()
        defaults.encryptedOneToOne = await settings.getDefaultRoomNotificationMode(isEncrypted: true, isOneToOne: true)
        defaults.encryptedGroup = await settings.getDefaultRoomNotificationMode(isEncrypted: true, isOneToOne: false)
        defaults.unencryptedOneToOne = await settings.getDefaultRoomNotificationMode(isEncrypted: false, isOneToOne: true)
        defaults.unencryptedGroup = await settings.getDefaultRoomNotificationMode(isEncrypted: false, isOneToOne: false)

        guard defaults != notificationDefaults else { return }
        notificationDefaults = defaults
        for model in models.values { model.notificationDefaults = defaults }
    }

    /// Encrypted and unencrypted rooms are separate push rules, but that's not a
    /// distinction anyone wants to configure, so both move together.
    func setDefaultNotificationMode(_ mode: RoomNotificationMode, isOneToOne: Bool) async {
        for isEncrypted in [true, false] {
            try? await settings?.setDefaultRoomNotificationMode(isEncrypted: isEncrypted,
                                                                isOneToOne: isOneToOne,
                                                                mode: mode)
        }
        await reloadNotificationDefaults()
    }
}


private nonisolated final class NotificationSettingsBridge: NotificationSettingsDelegate {
    private let handler: @Sendable () -> Void

    init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func settingsDidChange() {
        handler()
    }
}
