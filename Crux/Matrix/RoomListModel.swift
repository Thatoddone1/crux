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

        /// Whether we've joined this room or are only invited to it. Invites live
        /// in the same list but can't be entered until accepted.
        let membership: Membership

        ///MXC for room's avatar/picture
        let avatarUrl: String?

        let room: Room

        /// if there is at least one unread message in the entire room list
        var hasUnread: Bool { unreadMessages > 0 || isMarkedUnread }

        var isInvite: Bool { membership == .invited }

        func priorityScore(messages: [TimelineModel.Message]) async -> Int {
            var score = 0

            if unreadMentions > 0 {
                score += 40 //getting directly mentioned is treated as a high priority thing
                print("[priorityScore] \(name): +80 for \(unreadMentions) unread mention(s) -> \(score)") // DEBUG/TUNING
            }

            if isFavorite {score += 30}
            if isDirect {score += 10} else { score -= 10}
            if isLowPriority {score -= 60}
            print("[priorityScore] \(name): isFavorite=\(isFavorite) isDirect=\(isDirect) isLowPriority=\(isLowPriority) -> \(score)") // DEBUG: remove

            let transcript = messages.suffix(10)
                .map { "\($0.sender) (\($0.date.formatted(date: .abbreviated, time: .shortened))): \($0.body)" }
                .joined(separator: "\n")
            print("[priorityScore] \(name): transcript fed to LLM:\n\(transcript)") // DEBUG: remove

            let lmsession = LanguageModelSession()

            let response = try? await lmsession.respond(
                to: """
                You are an expert inbox triage assistant for a messaging client. Your job is to read a chat log (which includes timestamps) and assign a Priority Score from 0 to 40 based ONLY on the urgency of the MOST RECENT unread state.

                You will receive up to the last 10 messages. The older messages are strictly provided for context to help you understand the newest ones. 

                STEP 1: TIME & CONTEXT ANALYSIS
                Before scoring, mentally evaluate:
                - Recency Bias: Focus your score on the last 1 to 3 messages. If there was a crisis three days ago but the latest message is "All good now," the current priority is low. 
                - Contextual Meaning: A single word like "Okay" or "Done" is usually low priority. However, if the prior message was "I'm outside, come down now!", an "Okay" means an event is actively happening.
                - Actionability: Does the *most recent* message require the user to drop what they are doing and reply or act today?

                STEP 2: FIND THE CLOSEST ANCHOR SCORE
                Match the current state of the conversation to one of these strict anchor points. Adjust slightly up or down, but stay close to these baselines:

                Anchor 0: Resolved or Pure Noise
                - The conversation is resolved (e.g., "Thanks!", "Done", "See ya").
                - Emojis, reactions, or automated alerts.

                Anchor 10: Casual Banter / FYI
                - Greetings ("Hey", "Morning!").
                - Statements sharing info without needing a reply.
                - Memes or casual links.

                Anchor 20: Standard Conversation (Non-Urgent)
                - Normal chit-chat.
                - Long-term planning ("Let's get lunch next week").
                - Questions that are not time-sensitive.

                Anchor 30: Important & Actionable
                - Direct questions directed at the user that need a response today.
                - Work-related updates or project questions.
                - Short-term logistics ("Where are we meeting tonight?", "Are you on your way?").

                Anchor 40: Urgent / Emergency
                - Time-sensitive crises or emergencies happening right now.
                - Explicit demands for immediate attention ("Call me NOW", "Server is down").
                - Critical, last-minute cancellations or schedule changes.

                STEP 3: ASSIGN THE SCORE
                Based on the MOST RECENT context, provide the final integer score (0-40). 

                CONVERSATION TRANSCRIPT:
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

    /// LLM priority scores keyed by room id, computed by whichever card is currently displaying that room, as to not spam llm calls
    private(set) var priorityScores: [String: Int] = [:]

    /// newest message id that has been scored
    private var lastScoredMessageID: [String: String] = [:]

    /// Recomputes a room's priority score, but only when its newest message has actually changed since we last scored it.
    func updateScore(for summary: Summary, messages: [TimelineModel.Message]) async {
        guard let newest = messages.last?.id, lastScoredMessageID[summary.id] != newest else { return }
        
        lastScoredMessageID[summary.id] = newest
        priorityScores[summary.id] = await summary.priorityScore(messages: messages)
    }

    /// Marks a room read, clearing both its unread receipts and any manual unread flag.
    func markRead(_ summary: Summary) async {
        try? await summary.room.markAsRead(receiptType: .read)
        if summary.isMarkedUnread { try? await summary.room.setUnreadFlag(newValue: false) }
    }

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
                           membership: info?.membership ?? room.membership(),
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
