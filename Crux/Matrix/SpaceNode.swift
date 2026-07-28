//
//  SpaceNode.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// One row in the space tree — a room or a nested space, distinguished by `isSpace`.
/// Children are fetched lazily via `expand()`, not held for every space up front.
@Observable
final class SpaceNode: Identifiable {
    var id: String { spaceRoom.roomId }
    private(set) var spaceRoom: SpaceRoom
    private(set) var children: [SpaceNode] = []
    var isSpace: Bool { spaceRoom.roomType == .space }
    var isJoined: Bool { spaceRoom.state == .joined }

    private let service: SpaceService
    // Retained alongside the handles: dropping it frees the Rust object the
    // subscriptions and pagination read from, same reasoning as RoomListModel.roomList.
    private var list: SpaceRoomList?
    private var roomsHandle: TaskHandle?
    private var spaceHandle: TaskHandle?
    private var childSpaceRooms: [SpaceRoom] = []
    private var childNodes: [String: SpaceNode] = [:]

    private var isExpanding = false

    init(spaceRoom: SpaceRoom, service: SpaceService) {
        self.spaceRoom = spaceRoom
        self.service = service
    }

    /// No-op for plain rooms and for spaces already expanded.
    func expand() async throws {
        guard isSpace, roomsHandle == nil, !isExpanding else { return }
        isExpanding = true
        defer { isExpanding = false }

        let list = try await service.spaceRoomList(spaceId: spaceRoom.roomId)
        self.list = list

        let roomsListener = SpaceEntriesBridge { [weak self] updates in
            Task { @MainActor in
                guard let self else { return }
                Self.applyDiff(updates, to: &self.childSpaceRooms)
                self.rebuildChildren()
            }
        }
        roomsHandle = await list.subscribeToRoomUpdate(listener: roomsListener)
        childSpaceRooms = await list.rooms()
        rebuildChildren()

        let spaceListener = SpaceSelfBridge { [weak self] updated in
            Task { @MainActor in
                if let updated { self?.spaceRoom = updated }
            }
        }
        spaceHandle = list.subscribeToSpaceUpdates(listener: spaceListener)

        // SpaceRoomList is paginated — rooms() only returns what's already been
        // fetched, so nothing shows up until we actually page through it.
        while case .idle(let endReached) = list.paginationState(), !endReached {
            try await list.paginate()
        }
    }

    /// Drops subscriptions and clears children. Call when a UI row collapses so we
    /// don't keep a live SpaceRoomList open for every space ever expanded in a session.
    func collapse() {
        list = nil
        roomsHandle = nil
        spaceHandle = nil
        childSpaceRooms = []
        childNodes = [:]
        children = []
    }

    /// Reuses existing child nodes by ID so an already-expanded grandchild doesn't
    /// lose its own subscription/state when a sibling is added or removed.
    private func rebuildChildren() {
        let currentIDs = Set(childSpaceRooms.map(\.roomId))
        childNodes = childNodes.filter { currentIDs.contains($0.key) }
        children = childSpaceRooms.map { room in
            if let existing = childNodes[room.roomId] {
                existing.spaceRoom = room
                return existing
            }
            let node = SpaceNode(spaceRoom: room, service: service)
            childNodes[room.roomId] = node
            return node
        }
    }

    /// Shared by SpaceNode (its own children) and SpaceListModel (the top-level list) —
    /// both apply this identical diff shape to a [SpaceRoom] array.
    static func applyDiff(_ updates: [SpaceListUpdate], to array: inout [SpaceRoom]) {
        for update in updates {
            switch update {
            case .append(let values): array.append(contentsOf: values)
            case .clear: array.removeAll()
            case .pushFront(let value): array.insert(value, at: 0)
            case .pushBack(let value): array.append(value)
            case .popFront: array.removeFirst()
            case .popBack: array.removeLast()
            case .insert(let index, let value): array.insert(value, at: Int(index))
            case .set(let index, let value): array[Int(index)] = value
            case .remove(let index): array.remove(at: Int(index))
            case .truncate(let length): array.removeSubrange(Int(length)...)
            case .reset(let values): array = values
            }
        }
    }
}

private nonisolated final class SpaceEntriesBridge: SpaceRoomListEntriesListener {
    private let handler: @Sendable ([SpaceListUpdate]) -> Void

    init(_ handler: @escaping @Sendable ([SpaceListUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(rooms: [SpaceListUpdate]) {
        handler(rooms)
    }
}

private nonisolated final class SpaceSelfBridge: SpaceRoomListSpaceListener {
    private let handler: @Sendable (SpaceRoom?) -> Void

    init(_ handler: @escaping @Sendable (SpaceRoom?) -> Void) {
        self.handler = handler
    }

    func onUpdate(space: SpaceRoom?) {
        handler(space)
    }
}
