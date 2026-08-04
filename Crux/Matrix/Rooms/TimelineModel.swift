//
//  TimelineModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

enum TimelineError: LocalizedError {
    case notYetSent
    var errorDescription: String? { "That message hasn't finished sending yet." }
}

/// list of every event inside a specific room (and all the structs needed for that)
@Observable
final class TimelineModel {
    enum Entry: Identifiable {
        case message(Message)
        case dayDivider(id: String, date: Date)

        var id: String {
            switch self {
            case .message(let message): message.id
            case .dayDivider(let id, _): id
            }
        }
    }

    /// a single message
    struct Message: Identifiable {
        let id: String
        let sender: String
        /// The sender's mxid, e.g. for reporting/blocking or opening their profile.
        let senderId: String
        /// mxc:// URL for the sender's avatar (as seen in this room), or nil if unknown.
        /// Resolve to an image with `MediaLoader`.
        let senderAvatarUrl: String?
        let body: String
        let date: Date
        let isOwn: Bool
        let isEdited: Bool
        let sendState: SendState
        let reactions: [Reaction]
        /// Intentional mentions (m.mentions) carried by this message, if any.
        let mentions: Mentions?
        /// Whether the local user is currently allowed to edit this message.
        let isEditable: Bool
        /// Whether this message can be replied to (only true once it has an event id).
        let canReply: Bool
        /// The message this one answers, or nil if it isn't a reply.
        let replyTo: ReplyPreview?

        /// Identifies the message to the SDK for edits, reactions and redaction.
        /// It's an event id for messages the server has accepted, or a local
        /// transaction id for ones still in the send queue.
        let itemID: EventOrTransactionId
    }

    /// status of a message
    enum SendState {
        /// Confirmed by the server
        case sent
        /// Still in the send queue, not yet acknowledged.
        case sending
        /// The server rejected it (e.g. you lack permission to post here, other errors)
        case failed
    }

    /// Enough of the replied-to message to draw a chip above a reply. Both
    /// fields are nil until the SDK has fetched the original event.
    struct ReplyPreview {
        let sender: String?
        let body: String?
    }

    /// One emoji reaction, aggregated across everyone who used it.
    struct Reaction: Identifiable {
        let key: String
        let count: Int
        /// Whether the local user is one of the reactors (for toggle UI).
        let includesMe: Bool

        var id: String { key }
    }

    private(set) var entries: [Entry] = []

    private let room: Room
    private let ownUserID: String
    private var timeline: Timeline?
    private var items: [TimelineItem] = []
    private var listenerHandle: TaskHandle?

    init(room: Room) {
        self.room = room
        self.ownUserID = room.ownUserId()
    }

    // MARK: - Lifecycle

    /// Opens the timeline and starts streaming updates into `entries`.
    func start() async throws {
        guard timeline == nil else { return }

        let timeline = try await room.timeline()
        self.timeline = timeline

        let listener = TimelineBridge { diffs in
            Task { @MainActor [weak self] in self?.apply(diffs) }
        }
        listenerHandle = await timeline.addListener(listener: listener)
        _ = try await timeline.paginateBackwards(numEvents: 30)
    }

    // MARK: - Actions

    /// Sends a Markdown message. This returns as soon as the message is queued:
    /// it appears immediately as a `.sending` entry, and if the server rejects
    /// it (e.g. no permission) it comes back as `.failed` through the listener —
    /// *not* as an error thrown here.
    func send(_ markdown: String) async throws {
        _ = try await timeline?.send(msg: messageEventContentFromMarkdown(md: markdown))
    }

    /// Sends a Markdown message as a reply to `message`.
    func reply(_ markdown: String, to message: Message) async throws {
        // You can only reply to a message the server has already accepted.
        guard case .eventId(let eventID) = message.itemID else { throw TimelineError.notYetSent }
        try await timeline?.sendReply(msg: messageEventContentFromMarkdown(md: markdown),
                                      eventId: eventID)
    }

    /// Replaces the text of one of your own messages.
    func edit(_ message: Message, to markdown: String) async throws {
        let newContent = EditedContent.roomMessage(content: messageEventContentFromMarkdown(md: markdown))
        try await timeline?.edit(eventOrTransactionId: message.itemID, newContent: newContent)
    }

    /// Redacts (deletes) a message. `reason` is optional and shown to other clients.
    func delete(_ message: Message, reason: String? = nil) async throws {
        try await timeline?.redactEvent(eventOrTransactionId: message.itemID, reason: reason)
    }

    /// Adds your reaction if you haven't used this emoji here, or removes it if you have. The updated reaction list arrives back through the listener.
    func toggleReaction(_ key: String, on message: Message) async throws {
        _ = try await timeline?.toggleReaction(itemId: message.itemID, key: key)
    }

    /// Marks the room read up to its latest message, clearing its unread badge.
    func markAsRead() async throws {
        try await timeline?.markAsRead(receiptType: .read)
    }

    /// Reports a message to the homeserver. `reason` is optional. Doesn't
    /// hide the message locally — only messages the server has accepted can
    /// be reported.
    func report(_ message: Message, reason: String? = nil) async throws {
        guard case .eventId(let eventID) = message.itemID else { return }
        try await room.reportContent(eventId: eventID, reason: reason)
    }

    /// Loads an older page of history. Call when the user scrolls near the top.
    /// Returns `true` once the very start of the room has been reached.
    @discardableResult
    func loadMore(_ count: UInt16 = 30) async throws -> Bool {
        try await timeline?.paginateBackwards(numEvents: count) ?? true
    }

    // MARK: - Mapping (SDK diffs -> display entries)

    /// Applies a batch of diffs to `items`, then rebuilds `entries` from it.
    private func apply(_ diffs: [TimelineDiff]) {
        for diff in diffs {
            switch diff {
            case .append(let values): items.append(contentsOf: values)
            case .clear: items.removeAll()
            case .pushFront(let value): items.insert(value, at: 0)
            case .pushBack(let value): items.append(value)
            case .popFront: items.removeFirst()
            case .popBack: items.removeLast()
            case .insert(let index, let value): items.insert(value, at: Int(index))
            case .set(let index, let value): items[Int(index)] = value
            case .remove(let index): items.remove(at: Int(index))
            case .truncate(let length): items.removeSubrange(Int(length)...)
            case .reset(let values): items = values
            }
        }
        entries = items.compactMap(map)
    }

    private func map(_ item: TimelineItem) -> Entry? {
        if let event = item.asEvent() {
            return message(from: item, event: event).map(Entry.message)
        }
        if case .dateDivider(let ts) = item.asVirtual() {
            return .dayDivider(id: item.uniqueId().id, date: Self.date(from: ts))
        }
        return nil
    }

    private func message(from item: TimelineItem, event: EventTimelineItem) -> Message? {
        guard case .msgLike(let content) = event.content,
              let body = Self.body(of: content.kind) else { return nil }

        let reactions = content.reactions.map { reaction in
            Reaction(key: reaction.key,
                     count: reaction.senders.count,
                     includesMe: reaction.senders.contains { $0.senderId == ownUserID })
        }

        return Message(id: item.uniqueId().id,
                       sender: Self.displayName(of: event),
                       senderId: event.sender,
                       senderAvatarUrl: Self.avatarUrl(of: event),
                       body: body,
                       date: Self.date(from: event.timestamp),
                       isOwn: event.isOwn,
                       isEdited: Self.isEdited(content.kind),
                       sendState: Self.sendState(of: event.localSendState),
                       reactions: reactions,
                       mentions: Self.mentions(of: content.kind),
                       isEditable: event.isEditable,
                       canReply: event.canBeRepliedTo,
                       replyTo: Self.replyPreview(of: content.inReplyTo),
                       itemID: event.eventOrTransactionId)
    }

    /// Flattens the SDK's reply details for display. The replied-to event often
    /// isn't loaded yet, in which case we still show a chip — just an empty one.
    private static func replyPreview(of details: InReplyToDetails?) -> ReplyPreview? {
        guard let details else { return nil }
        guard case .ready(let content, let sender, let profile, _, _) = details.event(),
              case .msgLike(let msgLike) = content else {
            return ReplyPreview(sender: nil, body: nil)
        }
        var name = sender
        if case .ready(let displayName, _, _) = profile, let displayName { name = displayName }
        return ReplyPreview(sender: name, body: body(of: msgLike.kind))
    }

    /// The text to show for a message, or nil for incompatible messages for now
    private static func body(of kind: MsgLikeKind) -> String? {
        switch kind {
        case .message(let content): content.body
        case .sticker(let body, _, _): body
        case .redacted: "(message deleted)"
        case .unableToDecrypt: "(unable to decrypt, please verify in settings!)"
        case .poll, .other, .liveLocation: nil
        }
    }

    private static func isEdited(_ kind: MsgLikeKind) -> Bool {
        if case .message(let content) = kind { return content.isEdited }
        return false
    }

    private static func mentions(of kind: MsgLikeKind) -> Mentions? {
        if case .message(let content) = kind { return content.mentions }
        return nil
    }

    private static func sendState(of state: EventSendState?) -> SendState {
        switch state {
        case .none, .sent: .sent           // remote events have no local state
        case .notSentYet: .sending
        case .sendingFailed: .failed
        }
    }

    private static func displayName(of event: EventTimelineItem) -> String {
        if case .ready(let displayName, _, _) = event.senderProfile, let displayName {
            return displayName
        }
        return event.sender
    }

    private static func avatarUrl(of event: EventTimelineItem) -> String? {
        if case .ready(_, _, let avatarUrl) = event.senderProfile {
            return avatarUrl
        }
        return nil
    }

    private static func date(from timestamp: UInt64) -> Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }
}

#if DEBUG
extension TimelineModel.Message {
    //for demo messages
    static func sample(id: String = UUID().uuidString,
                       sender: String,
                       senderId: String = "@sample:example.org",
                       senderAvatarUrl: String? = nil,
                       body: String,
                       isOwn: Bool = false,
                       isEdited: Bool = false,
                       sendState: TimelineModel.SendState = .sent,
                       reactions: [TimelineModel.Reaction] = [],
                       mentions: Mentions? = nil,
                       replyTo: TimelineModel.ReplyPreview? = nil) -> Self {
        .init(id: id, sender: sender, senderId: senderId, senderAvatarUrl: senderAvatarUrl, body: body, date: Date(),
              isOwn: isOwn, isEdited: isEdited, sendState: sendState,
              reactions: reactions, mentions: mentions, isEditable: isOwn, canReply: true,
              replyTo: replyTo, itemID: .eventId(eventId: id))
    }
}
#endif

/// Forwards timeline updates from the SDK's background threads.
private nonisolated final class TimelineBridge: TimelineListener {
    private let handler: @Sendable ([TimelineDiff]) -> Void

    init(_ handler: @escaping @Sendable ([TimelineDiff]) -> Void) {
        self.handler = handler
    }

    func onUpdate(diff: [TimelineDiff]) {
        handler(diff)
    }
}
