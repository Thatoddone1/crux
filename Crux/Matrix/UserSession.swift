//
//  UserSession.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// A signed-in Matrix session: the client, background sync and the room list.
@Observable
final class UserSession {
    let client: Client
    let userId: String
    let roomList: RoomListModel

    private let syncService: SyncService

    init(client: Client) async throws {
        self.client = client
        userId = try client.userId()
        syncService = try await client.syncService().finish()
        roomList = RoomListModel(service: syncService.roomListService())
    }

    /// Starts syncing with the homeserver and populating the room list.
    func start() async {
        await syncService.start()
        await roomList.start()
    }

    func stop() async {
        await syncService.stop()
    }
}
