//
//  AppRouter.swift
//  Crux
//

import SwiftUI

/// The navigation state a notification needs to reach: which tab is showing and
/// what's on the rooms stack.
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case mountain, rooms, spaces, search
    }

    var selectedTab: Tab = .mountain
    var roomsPath = NavigationPath()

    /// The room on screen, so a push for it isn't shown on top of itself.
    var visibleRoomId: String?

    /// A tapped notification, held until the session is signed in — the tap can
    /// arrive during a cold launch, well before there's a room list.
    private(set) var pendingRoomId: String?

    func open(roomId: String) {
        pendingRoomId = roomId
    }

    func openPendingRoom() {
        guard let roomId = pendingRoomId else { return }
        pendingRoomId = nil
        selectedTab = .rooms
        roomsPath = NavigationPath([RoomListRoute.room(id: roomId)])
    }
}
