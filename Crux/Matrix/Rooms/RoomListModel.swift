//
//  RoomListModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// up to date list of all the rooms for a given user (session)
@Observable
@MainActor
final class RoomListModel {

    ///a list of rooms (called summaries, each a RoomModel)
    private(set) var summaries: [RoomModel] = []
    var unread: [RoomModel] { summaries.filter(\.hasUnread) }

    func awaitRoomsReady() async {
        for _ in 0..<30 {
            if !summaries.isEmpty && summaries.allSatisfy({ $0.info != nil }) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private let service: RoomListService
    private let store: RoomStore
    private var rooms: [Room] = []

    // These must all be retained for as long as we want updates. Releasing any
    // of them frees the Rust object behind it: dropping `roomList` frees the
    // room list the entries stream reads from (a crash), and dropping the handle
    // or controller stops updates.
    private var roomList: RoomList?
    private var controller: RoomListDynamicEntriesController?
    private var entriesHandle: TaskHandle?

    /// The rooms this list currently holds a store subscription for, so retains
    /// and releases stay balanced as the list churns.
    private var retained: Set<String> = []

    init(service: RoomListService, store: RoomStore) {
        self.service = service
        self.store = store
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
        syncModels()
    }

    /// Balances this list's holds against the rooms it now lists, then rebuilds
    /// `summaries`. A release only frees the room if nothing else — an open room,
    /// a mountain card — is still holding it.
    private func syncModels() {
        let currentIDs = Set(rooms.map { $0.id() })

        for id in retained.subtracting(currentIDs) {
            store.release(id)
            retained.remove(id)
        }
        for room in rooms where !retained.contains(room.id()) {
            store.retain(room)
            retained.insert(room.id())
        }

        // `@Observable` fires on set, not on change, so assigning an identical
        // array would re-run the whole list body — the exact thing storing this
        // is meant to avoid. Same objects in the same order means nothing about
        // the *list* changed; each row observes its own room for the rest.
        let next = rooms.compactMap { store.model(for: $0.id()) }
        guard next.count != summaries.count || !zip(next, summaries).allSatisfy({ $0 === $1 }) else { return }
        summaries = next
    }
}

/// Forwards room list updates from the SDK's background threads.
/// Not private: reused by SpaceListModel's invited-spaces stream.
nonisolated final class RoomListEntriesBridge: RoomListEntriesListener {
    private let handler: @Sendable ([RoomListEntriesUpdate]) -> Void

    init(_ handler: @escaping @Sendable ([RoomListEntriesUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        handler(roomEntriesUpdate)
    }
}

/// Forwards one room's info updates (unread counts, name, …) from the SDK's
/// background threads. Not private: this is what `RoomStore` subscribes with.
nonisolated final class RoomInfoBridge: RoomInfoListener {
    private let handler: @Sendable (RoomInfo) -> Void

    init(_ handler: @escaping @Sendable (RoomInfo) -> Void) {
        self.handler = handler
    }

    func call(roomInfo: RoomInfo) {
        handler(roomInfo)
    }
}
