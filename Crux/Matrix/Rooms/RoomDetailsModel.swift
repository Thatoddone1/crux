//
//  RoomDetailsModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// holds all details about a specific room (Room)
@Observable
final class RoomDetailsModel {
    private let room: Room
    private let client: Client

    private(set) var info: RoomInfo?
    private(set) var accountData: [RoomAccountDataEventType: RoomAccountDataEvent] = [:]

    private var infoHandle: TaskHandle?
    private var accountDataHandles: [RoomAccountDataEventType: TaskHandle] = [:]

    init(room: Room, client: Client) {
        self.room = room
        self.client = client
    }

    func start() {
        guard infoHandle == nil else { return }
        let listener = RoomInfoBridge { [weak self] info in
            Task { @MainActor in self?.info = info }
        }
        infoHandle = room.subscribeToRoomInfoUpdates(listener: listener)
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
    /// No separate reject call — leaving an unjoined room rejects the invite (and
    /// "forgets" it, per the SDK, as anti-spam).
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
