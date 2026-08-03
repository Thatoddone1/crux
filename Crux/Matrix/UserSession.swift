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

/// A signed-in Matrix session: the client, background sync and the room list.
@Observable
final class UserSession {
    let client: Client
    let userId: String
    let roomList: RoomListModel
    let spaces: SpaceListModel
    let verification: VerificationModel

    /// The signed-in user's own display name, for menus etc.
    private(set) var displayName: String?
    /// MXC for the signed-in user's own avatar.
    private(set) var avatarUrl: String?

    private let syncService: SyncService
    private let roomListService: RoomListService

    ///cache the room details so it is not constatly remade (for rooms and mountain cards). Maybe a bit better for SDK connections and memory
    private var roomDetailsCache: [String: RoomDetailsModel] = [:]

    init(client: Client) async throws {
        self.client = client
        userId = try client.userId()
        syncService = try await client.syncService().finish()
        roomListService = syncService.roomListService()
        roomList = RoomListModel(service: roomListService)
        spaces = SpaceListModel(service: await client.spaceService(), roomListService: roomListService)
        verification = VerificationModel(client: client)
    }

    /// Starts syncing with the homeserver and populating the room list, amoung other things
    func start() async {
        await syncService.start()
        await roomList.start()
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

    
    func roomDetails(for roomId: String) throws -> RoomDetailsModel {
        if let existing = roomDetailsCache[roomId] { return existing }
        let details = try RoomDetailsModel(session: self, roomId: roomId)
        roomDetailsCache[roomId] = details
        return details
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
