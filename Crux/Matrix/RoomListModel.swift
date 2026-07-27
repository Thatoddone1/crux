//
//  RoomListModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// up to date list of all the rooms for a given user (session)
@Observable
final class RoomListModel {
    struct Summary: Identifiable {
        let id: String
        let name: String
        /// Unread message count (all messages since your read marker).
        let unreadMessages: Int
        /// Unread *notifications* — messages that should badge, per notification settings.
        let unreadNotifications: Int
        /// Set when you (or another client) explicitly marked the room unread.
        let isMarkedUnread: Bool

        let isDirect: Bool
        let isFavourite: Bool
        let isLowPriority: Bool

        let room: Room

        /// if there is at least one unread message in the entire room list
        var hasUnread: Bool { unreadNotifications > 0 || isMarkedUnread }
    }

    private(set) var summaries: [Summary] = []

    private let service: RoomListService
    private var rooms: [Room] = []

    // These must all be retained for as long as we want updates. Releasing any
    // of them frees the Rust object behind it: dropping `roomList` frees the
    // room list the entries stream reads from (a crash), and dropping the handle
    // or controller stops updates.
    private var roomList: RoomList?
    private var controller: RoomListDynamicEntriesController?
    private var entriesHandle: TaskHandle?

    // Unread counts aren't a plain field on Room; they arrive live, per room,
    // through `subscribeToRoomInfoUpdates`. We keep the latest info for each
    // room here, plus the handle keeping that subscription alive.
    private var roomInfo: [String: RoomInfo] = [:]
    private var infoHandles: [String: TaskHandle] = [:]

    init(service: RoomListService) {
        self.service = service
    }

    func start() async {
        guard entriesHandle == nil, let allRooms = try? await service.allRooms() else { return }
        roomList = allRooms

        let listener = RoomListEntriesBridge { updates in
            Task { @MainActor [weak self] in self?.apply(updates) }
        }
        let result = allRooms.entriesWithDynamicAdapters(pageSize: 100, listener: listener)
        controller = result.controller()
        entriesHandle = result.entriesStream()
        _ = controller?.setFilter(kind: .all(filters: [.nonLeft]))
    }

    private func apply(_ updates: [RoomListEntriesUpdate]) {
        for update in updates {
            switch update {
            case .append(let values): rooms.append(contentsOf: values)
            case .clear: rooms.removeAll()
            case .pushFront(let value): rooms.insert(value, at: 0)
            case .pushBack(let value): rooms.append(value)
            case .popFront: rooms.removeFirst()
            case .popBack: rooms.removeLast()
            case .insert(let index, let value): rooms.insert(value, at: Int(index))
            case .set(let index, let value): rooms[Int(index)] = value
            case .remove(let index): rooms.remove(at: Int(index))
            case .truncate(let length): rooms.removeSubrange(Int(length)...)
            case .reset(let values): rooms = values
            }
        }
        syncInfoSubscriptions()
        rebuildSummaries()
    }

    /// Rebuilds `summaries` from the current rooms and whatever unread info we have cached so far.
    private func rebuildSummaries() {
        summaries = rooms.map { room in
            let info = roomInfo[room.id()]
            return Summary(id: room.id(),
                           name: room.displayName() ?? room.id(),
                           unreadMessages: Int(info?.numUnreadMessages ?? 0),
                           unreadNotifications: Int(info?.numUnreadNotifications ?? 0),
                           isMarkedUnread: info?.isMarkedUnread ?? false,
                           isDirect: info?.isDirect ?? false,
                           isFavourite: info?.isFavourite ?? false,
                           isLowPriority: info?.isLowPriority ?? false,
                           room: room)
        }
    }

    /// Keeps exactly one room-info subscription per room in the list: adds one
    /// for each new room, and drops the subscription (and cached info) for any
    /// room that has left, so handles don't leak as the list changes.
    private func syncInfoSubscriptions() {
        let currentIDs = Set(rooms.map { $0.id() })

        for id in infoHandles.keys where !currentIDs.contains(id) {
            infoHandles[id] = nil
            roomInfo[id] = nil
        }

        for room in rooms where infoHandles[room.id()] == nil {
            let id = room.id()
            let listener = RoomInfoBridge { info in
                Task { @MainActor [weak self] in
                    self?.roomInfo[id] = info
                    self?.rebuildSummaries()
                }
            }
            infoHandles[id] = room.subscribeToRoomInfoUpdates(listener: listener)
        }
    }
}

/// Forwards room list updates from the SDK's background threads.
private nonisolated final class RoomListEntriesBridge: RoomListEntriesListener {
    private let handler: @Sendable ([RoomListEntriesUpdate]) -> Void

    init(_ handler: @escaping @Sendable ([RoomListEntriesUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        handler(roomEntriesUpdate)
    }
}

/// Forwards one room's info updates (unread counts, name, …) from the SDK's
/// background threads.
private nonisolated final class RoomInfoBridge: RoomInfoListener {
    private let handler: @Sendable (RoomInfo) -> Void

    init(_ handler: @escaping @Sendable (RoomInfo) -> Void) {
        self.handler = handler
    }

    func call(roomInfo: RoomInfo) {
        handler(roomInfo)
    }
}
