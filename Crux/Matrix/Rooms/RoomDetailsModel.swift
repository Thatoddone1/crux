//
//  RoomDetailsModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

///holds all the information for a given room
@Observable
final class RoomDetailsModel {
    ///sdk room object to feed to other views that need it
    let room: Room
    let timeline: TimelineModel ///the timeline of the view

    private let client: Client

    private(set) var info: RoomInfo?
    private(set) var members: [Member] = []
    private(set) var accountData: [RoomAccountDataEventType: RoomAccountDataEvent] = [:]

    // Cheap snapshots taken at init so name/avatar/heroes are populated before the
    // first `RoomInfo` arrives; `info` supersedes them once it loads.
    private let fallbackName: String
    private let fallbackAvatarUrl: String?
    private let fallbackHeroes: [RoomHero]

    private var infoHandle: TaskHandle?
    private var accountDataHandles: [RoomAccountDataEventType: TaskHandle] = [:]

    /// One row of the member list, flattened off `RoomMember` so views stay SDK-free.
    struct Member: Identifiable {
        let id: String
        let displayName: String?
        var name: String { displayName ?? id }
    }

    init(room: Room, client: Client) {
        self.room = room
        self.client = client
        self.timeline = TimelineModel(room: room)
        self.fallbackName = room.displayName() ?? room.id()
        self.fallbackAvatarUrl = room.avatarUrl()
        self.fallbackHeroes = room.heroes()
    }

    convenience init(session: UserSession, roomId: String) throws {
        self.init(room: try session.room(id: roomId), client: session.client)
    }

    // MARK: Derived display values (prefer live `info`, fall back to init snapshot)

    var name: String { info?.displayName ?? fallbackName }
    var isDirect: Bool { info?.isDirect ?? false }
    var avatarUrl: String? { info?.avatarUrl ?? fallbackAvatarUrl }
    /// The other participant in a DM, for opening their profile from the title.
    var directHeroId: String? { (info?.heroes ?? fallbackHeroes).first?.userId }

    // MARK: Lifecycle

    /// Subscribes to room info and opens the timeline. Idempotent.
    func start() async {
        if infoHandle == nil {
            let listener = RoomInfoBridge { [weak self] info in
                Task { @MainActor in self?.info = info }
            }
            infoHandle = room.subscribeToRoomInfoUpdates(listener: listener)

            // The subscription only pushes future changes; seed the current snapshot.
            if let seeded = try? await room.roomInfo() {
                await MainActor.run { self.info = seeded }
            }
        }
        try? await timeline.start()
    }

    /// Drops the subscriptions so the Rust objects behind them are freed. The
    /// timeline is released when this model is.
    func stop() {
        infoHandle = nil
        accountDataHandles = [:]
    }

    /// Loads the member list once (for the member picker). Chunked at 500 like the
    /// old view code; larger rooms would need real pagination.
    func loadMembers() async {
        guard members.isEmpty, let iterator = try? await room.members() else { return }
        let mapped = (iterator.nextChunk(chunkSize: 500) ?? [])
            .map { Member(id: $0.userId, displayName: $0.displayName) }
        await MainActor.run { self.members = mapped }
    }

    /// Only `m.fully_read`, `m.marked_unread` and `m.tag` are readable this way
    func observeAccountData(_ type: RoomAccountDataEventType) throws {
        guard accountDataHandles[type] == nil else { return }
        let listener = RoomAccountDataBridge { [weak self] event in
            Task { @MainActor in self?.accountData[type] = event }
        }
        accountDataHandles[type] = try client.observeRoomAccountDataEvent(
            roomId: room.id(), eventType: type, listener: listener)
    }

    // MARK: Permissions for the signed-in user. False until `info` has loaded.

    func canSendMessage(_ type: MessageLikeEventType = .message) -> Bool {
        info?.powerLevels?.canOwnUserSendMessage(message: type) ?? false
    }
    func canSendState(_ type: StateEventType) -> Bool {
        info?.powerLevels?.canOwnUserSendState(stateEvent: type) ?? false
    }
    func canInvite() -> Bool { info?.powerLevels?.canOwnUserInvite() ?? false }
    func canKick() -> Bool { info?.powerLevels?.canOwnUserKick() ?? false }
    func canBan() -> Bool { info?.powerLevels?.canOwnUserBan() ?? false }
    func canRedactOwn() -> Bool { info?.powerLevels?.canOwnUserRedactOwn() ?? false }
    func canRedactOther() -> Bool { info?.powerLevels?.canOwnUserRedactOther() ?? false }
    func canPinUnpin() -> Bool { info?.powerLevels?.canOwnUserPinUnpin() ?? false }
    func canTriggerNotification() -> Bool { info?.powerLevels?.canOwnUserTriggerRoomNotification() ?? false }

    // MARK: Membership

    func join() async throws { try await room.join() }
    ///leave room or reject invite
    func leave() async throws { try await room.leave() }
    func invite(userId: String) async throws { try await room.inviteUserById(userId: userId) }
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
