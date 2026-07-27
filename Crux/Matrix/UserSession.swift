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
    let verification: VerificationModel

    private let syncService: SyncService

    init(client: Client) async throws {
        self.client = client
        userId = try client.userId()
        syncService = try await client.syncService().finish()
        roomList = RoomListModel(service: syncService.roomListService())
        verification = VerificationModel(client: client)
    }

    /// Starts syncing with the homeserver and populating the room list, amoung other things
    func start() async {
        await syncService.start()
        await roomList.start()
        await verification.start()
    }

    func stop() async {
        await syncService.stop()
    }
}
