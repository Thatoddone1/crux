//
//  UserSession.swift
//  Crux
//

import Foundation
import MatrixRustSDK

enum RoomCreationError: LocalizedError {
    case emptyName
    var errorDescription: String? { "Rooms need a name." }
}

enum RoomLookupError: LocalizedError {
    case notFound
    var errorDescription: String? { "That room couldn't be found." }
}

/// A signed-in Matrix session: the client, background sync and the room list.
@Observable
final class UserSession {
    let client: Client
    let userId: String
    /// The one place room state lives; the list and every open room read from it.
    let rooms: RoomStore
    let roomList: RoomListModel
    let spaces: SpaceListModel
    let verification: VerificationModel
    let mountain = MountainModel()

    /// The signed-in user's own display name, for menus etc.
    private(set) var displayName: String?
    /// MXC for the signed-in user's own avatar.
    private(set) var avatarUrl: String?

    private let syncService: SyncService
    private let roomListService: RoomListService

    init(client: Client) async throws {
        self.client = client
        userId = try client.userId()
        syncService = try await client.syncService().finish()
        roomListService = syncService.roomListService()
        rooms = RoomStore(client: client)
        roomList = RoomListModel(service: roomListService, store: rooms)
        spaces = SpaceListModel(service: await client.spaceService(), roomListService: roomListService)
        verification = VerificationModel(client: client)
    }

    /// Starts syncing with the homeserver and populating the room list, amoung other things
    func start() async {
        // The queue is persistent, so a reply sent from a notification still
        // goes out if the app was killed before it reached the server.
        await client.enableAllSendQueues(enable: true)
        await syncService.start()
        await roomList.start()
        await rooms.startNotifications()
        await spaces.start()
        await verification.start()

        if let profile = try? await client.getProfile(userId: userId) {
            displayName = profile.displayName
            avatarUrl = profile.avatarUrl
        }
    }

    func stop() async {
        await syncService.stop()
    }

    func room(id: String) throws -> Room {
        try roomListService.room(roomId: id)
    }

   
    func roomModel(for roomId: String) throws -> RoomModel {
        rooms.retain(try room(id: roomId))
    }

    func releaseRoom(_ roomId: String) {
        rooms.release(roomId)
    }

    /// Sends without opening the room, for the notification's reply action.
    /// Goes through `client.getRoom` rather than the room list, which needs sync
    /// to have run.
    func sendMessage(_ markdown: String, in roomId: String) async throws {
        let timeline = try await notificationTimeline(for: roomId)
        _ = try await timeline.send(msg: messageEventContentFromMarkdown(md: markdown))
    }

    /// Reacts without opening the room, for the notification's reaction actions.
    func react(_ key: String, toEvent eventId: String, in roomId: String) async throws {
        let timeline = try await notificationTimeline(for: roomId)
        _ = try await timeline.toggleReaction(itemId: .eventId(eventId: eventId), key: key)
    }

    private func notificationTimeline(for roomId: String) async throws -> Timeline {
        guard let room = try client.getRoom(roomId: roomId) else { throw RoomLookupError.notFound }
        return try await room.timeline()
    }

    /// Leaves a room or space; declines the invite if you're only invited.
    func leave(_ roomId: String) async {
        try? await room(id: roomId).leave()
    }

    // MARK: Room creation

    /// Reuses an existing 1:1 DM if one exists rather than creating a duplicate.
    func createDM(with userId: String, isEncrypted: Bool = true) async throws -> String {
        if let existing = try? client.getDmRoom(userId: userId) {
            return existing.id()
        }
        let params = CreateRoomParameters(
            name: nil, isEncrypted: isEncrypted, isDirect: true,
            visibility: .private, preset: .trustedPrivateChat, invite: [userId])
        return try await client.createRoom(request: params)
    }

    func createRoom(name: String, topic: String? = nil, isEncrypted: Bool = true,
                     isPublic: Bool = false, invite: [String] = [],
                     canonicalAlias: String? = nil, avatar: String? = nil) async throws -> String {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw RoomCreationError.emptyName }
        let params = CreateRoomParameters(
            name: name, topic: topic, isEncrypted: isEncrypted,
            visibility: isPublic ? .public : .private,
            preset: isPublic ? .publicChat : .privateChat,
            invite: invite.isEmpty ? nil : invite, avatar: avatar, canonicalAlias: canonicalAlias)
        return try await client.createRoom(request: params)
    }

    /// Spaces are created via the same `createRoom` call, just flagged `isSpace`.
    func createSpace(name: String, topic: String? = nil, isPublic: Bool = false,
                      invite: [String] = []) async throws -> String {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw RoomCreationError.emptyName }
        let params = CreateRoomParameters(
            name: name, topic: topic, isEncrypted: false,
            visibility: isPublic ? .public : .private,
            preset: isPublic ? .publicChat : .privateChat,
            invite: invite.isEmpty ? nil : invite, isSpace: true)
        return try await client.createRoom(request: params)
    }
}
