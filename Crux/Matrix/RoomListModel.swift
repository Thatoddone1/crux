//
//  RoomListModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK
import FoundationModels

/// up to date list of all the rooms for a given user (session)
@Observable
final class RoomListModel {
    struct Summary: Identifiable {
        let id: String
        let name: String
        /// Unread message count (all messages since your read marker).
        let unreadMessages: Int
        /// Unread *notifications*—this accounts for any notification settings
        let unreadNotifications: Int
        /// Unread events that mention/highlight you specifically — the SDK's own
        /// count, not something we compute by scanning messages ourselves.
        let unreadMentions: Int
        /// Set when you (or another client) explicitly marked the room unread.
        let isMarkedUnread: Bool

        let isDirect: Bool
        let isFavorite: Bool
        let isLowPriority: Bool

        ///MXC for room's avatar/picture
        let avatarUrl: String?

        let room: Room

        /// if there is at least one unread message in the entire room list
        var hasUnread: Bool { unreadMessages > 0 || isMarkedUnread }

        func priorityScore(messages: [TimelineModel.Message]) async -> Int {
            var score = 0

            if unreadMentions > 0 {
                score += 80 //getting directly mentioned is treated as a high priority thing
                print("[priorityScore] \(name): +80 for \(unreadMentions) unread mention(s) -> \(score)") // DEBUG/TUNING
            }

            if isFavorite {score += 30}
            if isDirect {score += 30}
            if isLowPriority {score -= 60}
            print("[priorityScore] \(name): isFavorite=\(isFavorite) isDirect=\(isDirect) isLowPriority=\(isLowPriority) -> \(score)") // DEBUG: remove

            let transcript = messages.suffix(10)
                .map { "\($0.sender) (\($0.date.formatted(date: .abbreviated, time: .shortened))): \($0.body)" }
                .joined(separator: "\n")
            print("[priorityScore] \(name): transcript fed to LLM:\n\(transcript)") // DEBUG: remove

            let lmsession = LanguageModelSession()

            let response = try? await lmsession.respond(
                to: """
                Here is the contents of this Matrix room, over the last few messages. Analyzing only the messages that matter, disregarding old messages, you are going to score this conversation on a scale from 0-50, based on how "important" the latest message, and the messages that influence that one directly, are. Are they life threataning, something that requires you absolute attention right now, or something less important, interesting to follow along with, but not ground breaking.

                \(transcript)
                """,
                generating: Int.self
            )
            print("[priorityScore] \(name): LLM response=\(response?.content.description ?? "nil")") // DEBUG/TUNING

            score += response?.content ?? 0

            let clamped = min(max(score, 0), 100)
            print("[priorityScore] \(name): final -> \(score) (clamped \(clamped))") // DEBUG/TUNING

            return clamped
        }
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
        setFilter(.none)
    }

    /// Rooms that have left the list (e.g. by leaving) are always excluded; spaces
    /// are surfaced separately via `SpaceListModel`, not mixed into this list.
    private static let baseFilters: [RoomListEntriesDynamicFilterKind] = [.nonLeft, .nonSpace]

    /// `.none` means "no extra filter" — it must never be ANDed in via `.all`,
    /// since `.none` as a filter to match against always fails, not always passes.
    func setFilter(_ kind: RoomListEntriesDynamicFilterKind) {
        let filters = kind == .none ? Self.baseFilters : Self.baseFilters + [kind]
        _ = controller?.setFilter(kind: .all(filters: filters))
    }

    enum RoomFilter {
        case all, invites, joined, favourites, unread, lowPriority
        case category(RoomListFilterCategory)
        case search(String)

        var sdkKind: RoomListEntriesDynamicFilterKind {
            switch self {
            case .all: .none
            case .invites: .invite
            case .joined: .joined
            case .favourites: .favourite
            case .unread: .unread
            case .lowPriority: .lowPriority
            case .category(let category): .category(expect: category)
            case .search(let query): .normalizedMatchRoomName(pattern: query)
            }
        }
    }

    /// Named apart from `setFilter(_:)`: `RoomFilter` and `RoomListEntriesDynamicFilterKind`
    /// share case names like `.unread`/`.category`, so an overload would be ambiguous.
    func applyFilter(_ filter: RoomFilter) { setFilter(filter.sdkKind) }

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
                           unreadMentions: Int(info?.numUnreadMentions ?? 0),
                           isMarkedUnread: info?.isMarkedUnread ?? false,
                           isDirect: info?.isDirect ?? false,
                           isFavorite: info?.isFavourite ?? false, //this uses the british spelling since the SDK does. Sorry for the inconsistancy.
                           isLowPriority: info?.isLowPriority ?? false,
                           avatarUrl: room.avatarUrl() ?? info?.heroes.first?.avatarUrl,
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

            // Seeds the current snapshot: the subscription above only pushes future changes.
            Task { @MainActor [weak self] in
                guard let info = try? await room.roomInfo() else { return }
                self?.roomInfo[id] = info
                self?.rebuildSummaries()
            }
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
/// background threads. Not private: reused by RoomDetailsModel.
nonisolated final class RoomInfoBridge: RoomInfoListener {
    private let handler: @Sendable (RoomInfo) -> Void

    init(_ handler: @escaping @Sendable (RoomInfo) -> Void) {
        self.handler = handler
    }

    func call(roomInfo: RoomInfo) {
        handler(roomInfo)
    }
}
