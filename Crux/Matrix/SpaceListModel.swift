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

    private let service: SpaceService
    private var handle: TaskHandle?
    private var nodesByID: [String: SpaceNode] = [:]

    /// No bulk "which rooms have a space parent" call exists in the SDK — only a
    /// per-room `joinedParentsOfChild` check — so results are cached by room ID.
    private var orphanCache: [String: Bool] = [:]

    init(service: SpaceService) {
        self.service = service
    }

    func start() async {
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
