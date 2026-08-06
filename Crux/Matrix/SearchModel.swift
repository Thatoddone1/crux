//
//  SearchModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// this is **not** full text search. Maybe later?
@Observable
@MainActor
final class SearchModel {
    enum Scope { case mine, global }

    enum Result: Identifiable {
        case room(RoomModel)
        case space(SpaceNode)
        case person(UserProfile) //assuming there is no DM yet
        case unjoinedRoom(String)

        var id: String {
            switch self {
            case .room(let room): "room:\(room.id)"
            case .space(let space): "space:\(space.id)"
            case .person(let person): "person:\(person.userId)"
            case .unjoinedRoom(let idOrAlias): "unjoined:\(idOrAlias)"
            }
        }
    }

    private(set) var results: [Result] = []
    private(set) var isSearchingUsers = false

    private let session: UserSession
    private var searchTask: Task<Void, Never>?

    init(session: UserSession) {
        self.session = session
    }

    func search(_ query: String, scope: Scope) {
        searchTask?.cancel()
        isSearchingUsers = false

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        if let linkResult = resolveLink(trimmed) {
            results = (scope == .mine && Self.isGlobalOnly(linkResult)) ? [] : [linkResult]
            return
        }

        let local = localMatches(trimmed)
        results = local
        guard scope == .global, trimmed.count >= 2 else { return }

        // Debounced so fast typing doesn't fire a directory search per keystroke.
        isSearchingUsers = true
        searchTask = Task {
            defer { isSearchingUsers = false }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let users = (try? await session.client.searchUsers(searchTerm: trimmed, limit: 8))?.results ?? []
            guard !Task.isCancelled else { return }
            let extra = users
                .filter { $0.userId != session.userId }
                .map(personOrExistingDM)
            results = Self.merging(extra, into: local)
        }
    }

    /// Joins an unjoined result, so the caller can open it once it lands.
    func join(_ idOrAlias: String) async throws -> String {
        try await session.client.joinRoomByIdOrAlias(roomIdOrAlias: idOrAlias, serverNames: []).id()
    }

    /// Opens (or starts) a DM with someone found via search.
    func startDM(with userId: String) async throws -> String {
        try await session.createDM(with: userId)
    }

    // MARK: - Local matches

    private func localMatches(_ query: String) -> [Result] {
        let roomMatches: [(Int, Result)] = session.roomList.summaries.compactMap { room in
            let names = [room.name, room.canonicalAlias].compactMap { $0 } + room.alternativeAliases
            guard let score = Self.bestScore(query, in: names) else { return nil }
            return (score, .room(room))
        }
        let spaceMatches: [(Int, Result)] = session.spaces.nodes.compactMap { node in
            let names = [node.spaceRoom.displayName, node.spaceRoom.canonicalAlias].compactMap { $0 }
            guard let score = Self.bestScore(query, in: names) else { return nil }
            return (score, .space(node))
        }
        return (roomMatches + spaceMatches)
            .sorted { $0.0 > $1.0 }
            .map(\.1)
    }

    private static func bestScore(_ query: String, in candidates: [String]) -> Int? {
        candidates.compactMap { FuzzyMatch.score(query, in: $0) }.max()
    }

    private static func isGlobalOnly(_ result: Result) -> Bool {
        switch result {
        case .unjoinedRoom, .person: true
        case .room, .space: false
        }
    }

    /// Appends `extra` results not already represented in `base` (by id) — so a
    /// directory hit for someone whose DM already surfaced as a local match
    /// doesn't show up twice.
    private static func merging(_ extra: [Result], into base: [Result]) -> [Result] {
        var seen = Set(base.map(\.id))
        var combined = base
        for result in extra where seen.insert(result.id).inserted {
            combined.append(result)
        }
        return combined
    }

    // MARK: - People
    private func personOrExistingDM(_ user: UserProfile) -> Result {
        existingDM(for: user.userId).map(Result.room) ?? .person(user)
    }

    private func existingDM(for userId: String) -> RoomModel? {
        session.roomList.summaries.first { $0.isOneToOne && $0.directHeroId == userId }
    }

    // MARK: - Links and bare ids

    /// A matrix.to link, `matrix:` URI, or a bare `@user:server` / `#alias:server`
    /// / `!roomid:server` typed directly.
    private func resolveLink(_ text: String) -> Result? {
        let id: MatrixId
        if let entity = parseMatrixEntityFrom(uri: text) {
            id = entity.id
        } else if text.contains(":"), let prefix = text.first {
            switch prefix {
            case "@": id = .user(id: text)
            case "#": id = .roomAlias(alias: text)
            case "!": id = .room(id: text)
            default: return nil
            }
        } else {
            return nil
        }

        switch id {
        case .user(let userId):
            return personOrExistingDM(UserProfile(userId: userId, displayName: nil, avatarUrl: nil))
        case .room(let roomId):
            return roomResult(for: roomId)
        case .roomAlias(let alias):
            return roomResult(for: alias)
        case .eventOnRoomId(let roomId, _):
            return roomResult(for: roomId)
        case .eventOnRoomAlias(let alias, _):
            return roomResult(for: alias)
        }
    }

    /// A resolved room/space if it's already joined, else `.unjoinedRoom`, to
    /// join and open on tap. `idOrAlias` matches either a room id or an alias.
    private func roomResult(for idOrAlias: String) -> Result {
        if let joined = session.roomList.summaries.first(where: {
            $0.id == idOrAlias || $0.canonicalAlias == idOrAlias || $0.alternativeAliases.contains(idOrAlias)
        }) {
            return .room(joined)
        }
        if let space = session.spaces.nodes.first(where: {
            $0.id == idOrAlias || $0.spaceRoom.canonicalAlias == idOrAlias
        }) {
            return .space(space)
        }
        return .unjoinedRoom(idOrAlias)
    }
}
