//
//  SpaceListModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// Top-level joined spaces (spaces with no joined parent — the SDK computes this for
/// us), plus the ability to tell which rooms don't belong to any space at all.
@Observable
final class SpaceListModel {
    private(set) var spaces: [SpaceRoom] = []
    private(set) var nodes: [SpaceNode] = []

    /// A space we've been invited to but haven't joined. SpaceService only tracks
    /// *joined* spaces, so these are sourced from the room list and shown at the
    /// top of the Spaces tab with a Join button.
    struct Invite: Identifiable {
        let id: String
        let name: String
        let avatarUrl: String?
        let room: Room
    }
    private(set) var invites: [Invite] = []

    private let service: SpaceService
    private let roomListService: RoomListService
    private var handle: TaskHandle?
    private var nodesByID: [String: SpaceNode] = [:]

    /// No bulk "which rooms have a space parent" call exists in the SDK — only a
    /// per-room `joinedParentsOfChild` check — so results are cached by room ID.
    private var orphanCache: [String: Bool] = [:]

    // Invited-spaces stream, filtered off the room list. Retained for the same
    // reason as RoomListModel's roomList/controller/handle — dropping any frees
    // the Rust objects the updates read from.
    private var inviteRooms: [Room] = []
    private var inviteRoomList: RoomList?
    private var inviteController: RoomListDynamicEntriesController?
    private var inviteEntriesHandle: TaskHandle?

    init(service: SpaceService, roomListService: RoomListService) {
        self.service = service
        self.roomListService = roomListService
    }

    func start() async {
        await startInvites()
        guard handle == nil else { return }
        let listener = SpaceListBridge { [weak self] updates in
            Task { @MainActor in
                guard let self else { return }
                SpaceNode.applyDiff(updates, to: &self.spaces)
                self.rebuildNodes()
            }
        }
        handle = await service.subscribeToTopLevelJoinedSpaces(listener: listener)
        spaces = await service.topLevelJoinedSpaces()
        rebuildNodes()
    }

    private func startInvites() async {
        guard inviteEntriesHandle == nil, let all = try? await roomListService.allRooms() else { return }
        inviteRoomList = all
        let listener = RoomListEntriesBridge { updates in
            Task { @MainActor [weak self] in self?.applyInvite(updates) }
        }
        let result = all.entriesWithDynamicAdapters(pageSize: 100, listener: listener)
        inviteController = result.controller()
        inviteEntriesHandle = result.entriesStream()
        _ = inviteController?.setFilter(kind: .all(filters: [.nonLeft, .space, .invite]))
    }

    private func applyInvite(_ updates: [RoomListEntriesUpdate]) {
        for update in updates {
            switch update {
            case .append(let values): inviteRooms.append(contentsOf: values)
            case .clear: inviteRooms.removeAll()
            case .pushFront(let value): inviteRooms.insert(value, at: 0)
            case .pushBack(let value): inviteRooms.append(value)
            case .popFront: inviteRooms.removeFirst()
            case .popBack: inviteRooms.removeLast()
            case .insert(let index, let value): inviteRooms.insert(value, at: Int(index))
            case .set(let index, let value): inviteRooms[Int(index)] = value
            case .remove(let index): inviteRooms.remove(at: Int(index))
            case .truncate(let length): inviteRooms.removeSubrange(Int(length)...)
            case .reset(let values): inviteRooms = values
            }
        }
        rebuildInvites()
    }

    /// Built straight from the Room objects the filtered stream delivers — no
    /// SpaceService lookup, which doesn't resolve spaces we haven't joined yet.
    private func rebuildInvites() {
        invites = inviteRooms.map { room in
            Invite(id: room.id(), name: room.displayName() ?? room.id(),
                   avatarUrl: room.avatarUrl(), room: room)
        }
        print("[SpaceInvites] stream delivered \(inviteRooms.count) invited space(s)") // DEBUG: remove once confirmed
    }

    private func rebuildNodes() {
        let currentIDs = Set(spaces.map(\.roomId))
        nodesByID = nodesByID.filter { currentIDs.contains($0.key) }
        nodes = spaces.map { room in
            if let existing = nodesByID[room.roomId] {
                return existing
            }
            let node = SpaceNode(spaceRoom: room, service: service)
            nodesByID[room.roomId] = node
            return node
        }
    }

    /// Filters `summaries` down to rooms that don't belong to any joined space.
    func orphaned(from summaries: [RoomListModel.Summary]) async -> [RoomListModel.Summary] {
        var result: [RoomListModel.Summary] = []
        for summary in summaries {
            if let cached = orphanCache[summary.id] {
                if cached { result.append(summary) }
                continue
            }
            let parents = (try? await service.joinedParentsOfChild(childId: summary.id)) ?? []
            let isOrphaned = parents.isEmpty
            orphanCache[summary.id] = isOrphaned
            if isOrphaned { result.append(summary) }
        }
        return result
    }
}

private nonisolated final class SpaceListBridge: SpaceServiceJoinedSpacesListener {
    private let handler: @Sendable ([SpaceListUpdate]) -> Void

    init(_ handler: @escaping @Sendable ([SpaceListUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomUpdates: [SpaceListUpdate]) {
        handler(roomUpdates)
    }
}
