//
//  RoomModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

///All details about a specific room.
@Observable
@MainActor
final class RoomModel: Identifiable {
    let id: String
    ///sdk room object to feed to other views that need it
    let room: Room

    ///start the timeline with .start() first before using it
    let timeline: TimelineModel

    private let client: Client

    private(set) var info: RoomInfo?
    /// The last thing that happened here, for a list preview. Nil until it's been
    /// fetched, or when nothing renderable has happened yet.
    private(set) var latestMessage: LatestMessage?
    private(set) var members: [Member] = []
    private(set) var accountData: [RoomAccountDataEventType: RoomAccountDataEvent] = [:]

    ///notification settings; nill when set to account default
    private(set) var notificationOverride: RoomNotificationMode?
    /// Whether `notificationOverride` has actually been read. Until it has, `nil`
    /// only means "don't know yet".
    private var hasFetchedNotificationOverride = false
    ///account wide default (for rooms without notification settings of their own)
    var notificationDefaults = NotificationDefaults()
    private var notificationSettings: NotificationSettings?

    // Cheap snapshots taken at init so name/avatar/heroes are populated before the first `RoomInfo` arrives; `info` supersedes them once it loads.
    private let fallbackName: String
    private let fallbackAvatarUrl: String?
    private let fallbackHeroes: [RoomHero]

    private var infoHandle: TaskHandle?
    private var accountDataHandles: [RoomAccountDataEventType: TaskHandle] = [:]

    ///in process of fetching latest event
    private var isFetchingLatest = false
    private var latestNeedsRefetch = false

    /// One row of the member list, flattened off `RoomMember` so views stay SDK-free.
    struct Member: Identifiable {
        let id: String
        let displayName: String?
        var name: String { displayName ?? id }
    }

    /// One line of preview text for the room list.
    struct LatestMessage: Equatable {
        let sender: String
        let body: String
        let date: Date
        let isOwn: Bool
        /// Still in the send queue — worth dimming in a preview.
        let isPending: Bool
    }

    init(room: Room, client: Client) {
        self.id = room.id()
        self.room = room
        self.client = client
        self.timeline = TimelineModel(room: room)
        self.fallbackName = room.displayName() ?? room.id()
        self.fallbackAvatarUrl = room.avatarUrl()
        self.fallbackHeroes = room.heroes()
    }

    // MARK: Display values (prefer live `info`, fall back to the init snapshot)

    var name: String { info?.displayName ?? fallbackName }
    var avatarUrl: String? { info?.avatarUrl ?? fallbackAvatarUrl ?? heroes.first?.avatarUrl }
    var topic: String? { info?.topic }

    /// Unread message count (all messages since your read marker).
    var unreadMessages: Int { Int(info?.numUnreadMessages ?? 0) }
    /// Unread *notifications* — this accounts for any notification settings.
    var unreadNotifications: Int { Int(info?.numUnreadNotifications ?? 0) }
    /// Unread events that mention/highlight you specifically — the SDK's own
    /// count, not something we compute by scanning messages ourselves.
    var unreadMentions: Int { Int(info?.numUnreadMentions ?? 0) }
    /// Set when you (or another client) explicitly marked the room unread.
    var isMarkedUnread: Bool { info?.isMarkedUnread ?? false }
    /// If there is at least one unread message in the entire room list.
    var hasUnread: Bool { unreadMessages > 0 || isMarkedUnread }

    var isDirect: Bool { info?.isDirect ?? false }
    /// A direct room with exactly one other person, as opposed to a group DM (which is apparently a thing?)
    var isOneToOne: Bool { info?.isDm ?? false }
    var isFavorite: Bool { info?.isFavourite ?? false }  // British spelling follows the SDK's
    var isLowPriority: Bool { info?.isLowPriority ?? false }
    var isEncrypted: Bool { info?.encryptionState == .encrypted }

    /// Whether we've joined this room or are only invited to it. Invites live in the same list but can't be entered until accepted.
    var membership: Membership { info?.membership ?? room.membership() }
    var isInvite: Bool { membership == .invited }

    var joinedMembersCount: Int { Int(info?.joinedMembersCount ?? 0) }
    private var heroes: [RoomHero] { info?.heroes ?? fallbackHeroes }
    /// The other participant in a DM, for opening their profile from the title.
    var directHeroId: String? { heroes.first?.userId }

    private var ownNotificationMode: RoomNotificationMode? {
        hasFetchedNotificationOverride ? notificationOverride : info?.cachedUserDefinedNotificationMode
    }

    ///mode the room notifies at
    var notificationMode: RoomNotificationMode {
        ownNotificationMode ?? notificationDefaults.mode(isEncrypted: isEncrypted, isOneToOne: isOneToOne)
    }
    /// Whether `notificationMode` is this room's own setting rather than inherited.
    var hasNotificationOverride: Bool { ownNotificationMode != nil }
    var isMuted: Bool { notificationMode == .mute }

    /// How a room's notification setting should be called out. Deliberately not
    /// the SDK's `RoomNotificationMode`, so views can render it without importing
    /// the SDK to do so.
    enum NotificationLabel { case muted, mentionsOnly, allMessages }

    
    var notificationLabel: NotificationLabel? {
        let mode = notificationMode
        guard mode != .mute else { return .muted }
        guard mode != notificationDefaults.mode(isEncrypted: isEncrypted, isOneToOne: isOneToOne) else {
            return nil
        }
        return mode == .mentionsAndKeywordsOnly ? .mentionsOnly : .allMessages
    }

    // MARK: Lifecycle

    /// Subscribes to room info. Called once, when the store first hands this room
    /// out; the subscription lives as long as the model does.
    func startSubscriptions() {
        guard infoHandle == nil else { return }
        let listener = RoomInfoBridge { [weak self] info in
            guard let model = self else { return }
            Task { @MainActor in model.received(info) }
        }
        infoHandle = room.subscribeToRoomInfoUpdates(listener: listener)

        // The subscription only pushes future changes; seed the current snapshot.
        Task { @MainActor [weak self] in
            guard let info = try? await self?.room.roomInfo() else { return }
            self?.received(info)
        }
        refreshLatestMessage()
    }

    /// Drops everything: the info subscription, the account data listeners and the
    /// timeline. Called when the store evicts this room entirely.
    func stop() {
        infoHandle = nil
        accountDataHandles = [:]
        timeline.stop()
    }

    private func received(_ new: RoomInfo) {
        info = new
        refreshLatestMessage()
    }

    ///loades member list (in chunks of 500)
    func loadMembers() async {
        guard members.isEmpty, let iterator = try? await room.members() else { return }
        members = (iterator.nextChunk(chunkSize: 500) ?? [])
            .map { Member(id: $0.userId, displayName: $0.displayName) }
    }

    
    func observeAccountData(_ type: RoomAccountDataEventType) throws {
        guard accountDataHandles[type] == nil else { return }
        let listener = RoomAccountDataBridge { [weak self] event in
            guard let model = self else { return }
            Task { @MainActor in model.accountData[type] = event }
        }
        accountDataHandles[type] = try client.observeRoomAccountDataEvent(
            roomId: id, eventType: type, listener: listener)
    }

    // MARK: Last message

    private func refreshLatestMessage() {
        guard !isFetchingLatest else {
            latestNeedsRefetch = true
            return
        }
        isFetchingLatest = true
        Task { @MainActor [weak self] in
            guard let model = self else { return }
            let value = await model.room.latestEvent()
            model.isFetchingLatest = false

            let message = LatestMessage(value, ownUserId: model.room.ownUserId())
            if message != model.latestMessage { model.latestMessage = message }
            if model.latestNeedsRefetch {
                model.latestNeedsRefetch = false
                model.refreshLatestMessage()
            }
        }
    }

    // MARK: Permissions for the signed-in user. False until the room's info has loaded.

    private var powerLevels: RoomPowerLevels? { info?.powerLevels }
    /// False only because we don't know yet, not because you can't — callers that
    /// would rather be optimistic while loading can check `info` first.
    func canSendMessage(_ type: MessageLikeEventType = .message) -> Bool {
        powerLevels?.canOwnUserSendMessage(message: type) ?? false
    }
    func canSendState(_ type: StateEventType) -> Bool {
        powerLevels?.canOwnUserSendState(stateEvent: type) ?? false
    }
    func canInvite() -> Bool { powerLevels?.canOwnUserInvite() ?? false }
    func canKick() -> Bool { powerLevels?.canOwnUserKick() ?? false }
    func canBan() -> Bool { powerLevels?.canOwnUserBan() ?? false }
    func canRedactOwn() -> Bool { powerLevels?.canOwnUserRedactOwn() ?? false }
    func canRedactOther() -> Bool { powerLevels?.canOwnUserRedactOther() ?? false }
    func canPinUnpin() -> Bool { powerLevels?.canOwnUserPinUnpin() ?? false }
    func canTriggerNotification() -> Bool { powerLevels?.canOwnUserTriggerRoomNotification() ?? false }

    // MARK: Settings

    // Favorite and low priority are two independent room tags, so nothing stops
    // the server holding both — but they mean opposite things, and the room list's
    // `.favourite` and `.lowPriority` filters would each claim the room. Turning
    // one on clears the other, here rather than in a view, so the settings sheet
    // and the list's context menu can't diverge on it.

    func setFavorite(_ isFavorite: Bool) async {
        try? await room.setIsFavourite(isFavourite: isFavorite, tagOrder: nil)
        guard isFavorite, isLowPriority else { return }
        try? await room.setIsLowPriority(isLowPriority: false, tagOrder: nil)
    }

    func setLowPriority(_ isLowPriority: Bool) async {
        try? await room.setIsLowPriority(isLowPriority: isLowPriority, tagOrder: nil)
        guard isLowPriority, isFavorite else { return }
        try? await room.setIsFavourite(isFavourite: false, tagOrder: nil)
    }

    func setTopic(_ topic: String) async throws { try await room.setTopic(topic: topic) }
    func setName(_ name: String) async throws { try await room.setName(name: name) }

    /// Marks the room read, clearing both its unread receipts and any manual
    /// unread flag.
    func markRead() async {
        try? await room.markAsRead(receiptType: .read)
        if isMarkedUnread { try? await room.setUnreadFlag(newValue: false) }
    }

    func markUnread() async {
        try? await room.setUnreadFlag(newValue: true)
    }

    // MARK: Notifications

    /// Handed the shared settings object rather than fetching its own, so every
    /// room writes through the same push rules.
    func use(_ settings: NotificationSettings) {
        guard notificationSettings == nil else { return }
        notificationSettings = settings
        refreshNotificationOverride()
    }

    ///rereads notification settings for this room
    func refreshNotificationOverride() {
        guard let settings = notificationSettings else { return }
        Task { @MainActor [weak self] in
            guard let model = self else { return }
            let mode = try? await settings.getUserDefinedRoomNotificationMode(roomId: model.id)
            model.hasFetchedNotificationOverride = true
            if mode != model.notificationOverride { model.notificationOverride = mode }
        }
    }

    func setNotificationMode(_ mode: RoomNotificationMode) async {
        try? await notificationSettings?.setRoomNotificationMode(roomId: id, mode: mode)
        hasFetchedNotificationOverride = true
        notificationOverride = mode
    }

    /// Clears this room's own setting so it follows the account default again.
    func followDefaultNotificationMode() async {
        try? await notificationSettings?.restoreDefaultRoomNotificationMode(roomId: id)
        hasFetchedNotificationOverride = true
        notificationOverride = nil
    }

    func setMuted(_ muted: Bool) async {
        if muted {
            await setNotificationMode(.mute)
        } else {
            try? await notificationSettings?.unmuteRoom(roomId: id,
                                                        isEncrypted: isEncrypted,
                                                        isOneToOne: isOneToOne)
            let restored = try? await notificationSettings?
                .getUserDefinedRoomNotificationMode(roomId: id)
            hasFetchedNotificationOverride = true
            notificationOverride = restored
        }
    }

    // MARK: Membership

    func join() async throws { try await room.join() }
    ///leave room or reject invite
    func leave() async throws { try await room.leave() }
    func invite(userId: String) async throws { try await room.inviteUserById(userId: userId) }
}

/// The account-wide notification defaults, which rooms without their own setting
/// inherit. 
struct NotificationDefaults: Equatable {
    var encryptedOneToOne: RoomNotificationMode = .allMessages
    var encryptedGroup: RoomNotificationMode = .allMessages
    var unencryptedOneToOne: RoomNotificationMode = .allMessages
    var unencryptedGroup: RoomNotificationMode = .allMessages

    func mode(isEncrypted: Bool, isOneToOne: Bool) -> RoomNotificationMode {
        switch (isEncrypted, isOneToOne) {
        case (true, true): encryptedOneToOne
        case (true, false): encryptedGroup
        case (false, true): unencryptedOneToOne
        case (false, false): unencryptedGroup
        }
    }
}

extension RoomModel.LatestMessage {
    /// Flattens the SDK's latest-event value, which is available without opening
    /// a timeline.
    init?(_ value: LatestEventValue, ownUserId: String) {
        switch value {
        case .none:
            return nil
        case .remote(let timestamp, let sender, let isOwn, let profile, let content):
            guard let body = Self.body(of: content) else { return nil }
            self.init(sender: Self.name(of: profile, fallback: sender), body: body,
                      date: Self.date(from: timestamp), isOwn: isOwn, isPending: false)
        case .local(let timestamp, let sender, let profile, let content, _):
            guard let body = Self.body(of: content) else { return nil }
            self.init(sender: Self.name(of: profile, fallback: sender), body: body,
                      date: Self.date(from: timestamp), isOwn: sender == ownUserId, isPending: true)
        case .remoteInvite(let timestamp, let inviter, let inviterProfile):
            let name = Self.name(of: inviterProfile, fallback: inviter ?? "Someone")
            self.init(sender: name, body: "invited you", date: Self.date(from: timestamp),
                      isOwn: false, isPending: false)
        }
    }

    private static func body(of content: TimelineItemContent) -> String? {
        guard case .msgLike(let msgLike) = content,
              let body = TimelineModel.body(of: msgLike.kind) else { return nil }
        let flattened = body.split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func name(of profile: ProfileDetails, fallback: String) -> String {
        if case .ready(let displayName, _, _) = profile, let displayName { return displayName }
        return fallback
    }

    private static func date(from timestamp: Timestamp) -> Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }
}

private nonisolated final class RoomAccountDataBridge: RoomAccountDataListener {
    private let handler: @Sendable (RoomAccountDataEvent) -> Void

    init(_ handler: @escaping @Sendable (RoomAccountDataEvent) -> Void) {
        self.handler = handler
    }

    func onChange(event: RoomAccountDataEvent, roomId: String) {
        handler(event)
    }
}
