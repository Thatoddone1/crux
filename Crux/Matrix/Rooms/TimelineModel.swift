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
        /// The file attached to this message, or nil for a plain text one.
        let media: MediaAttachment?
        ///when crux cant show message as text or other type (like image).
        let notice: Notice?

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

    /// Enough of the replied-to message to draw a chip above a reply. Everything
    /// but `eventId` is nil until the SDK has fetched the original event.
    struct ReplyPreview {
        /// Always known — it's what the reply points at, and what we jump to.
        let eventId: String
        let senderId: String?
        let sender: String?
        let body: String?
    }

    struct MediaAttachment: Identifiable {
        enum Kind {
            case image, video, audio, file
        }

        /// The attachment's mxc URL.
        let id: String
        let kind: Kind
        ///attachment itself including all the encryption keys
        let source: MediaSource
        ///small preview
        let thumbnailSource: MediaSource?
        let filename: String
        let caption: String?
        ///reserve space before image comes
        let width: UInt64?
        let height: UInt64?

        var isImage: Bool { kind == .image }
    }

    /// A compact explanation shown in place of a message's body. Tapping it
    /// reveals `detail`.
    struct Notice {
        let icon: String
        let title: String
        let detail: String
        /// True for a deleted message, whose leftover reactions (if the SDK
        /// still reports any) shouldn't be shown alongside it.
        var isRedaction: Bool = false
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


    func stop() {
        listenerHandle = nil
        timeline = nil
        items = []
        entries = []
    }

    // MARK: - Actions

    func send(_ markdown: String, mentioning userIds: [String] = []) async throws {
        let content = attachMentions(to: messageEventContentFromMarkdown(md: markdown), userIds)
        _ = try await timeline?.send(msg: content)
    }

    /// Sends a Markdown message as a reply to `message`.
    func reply(_ markdown: String, to message: Message, mentioning userIds: [String] = []) async throws {
        // You can only reply to a message the server has already accepted.
        guard case .eventId(let eventID) = message.itemID else { throw TimelineError.notYetSent }
        let content = attachMentions(to: messageEventContentFromMarkdown(md: markdown), userIds)
        try await timeline?.sendReply(msg: content, eventId: eventID)
    }

    private func attachMentions(to content: RoomMessageEventContentWithoutRelation,
                                 _ userIds: [String]) -> RoomMessageEventContentWithoutRelation {
        guard !userIds.isEmpty else { return content }
        return content.withMentions(mentions: Mentions(userIds: userIds, room: false))
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
        guard case .msgLike(let content) = event.content else { return nil }

        let reactions = content.reactions.map { reaction in
            Reaction(key: reaction.key,
                     count: reaction.senders.count,
                     includesMe: reaction.senders.contains { $0.senderId == ownUserID })
        }

        return Message(id: item.uniqueId().id,
                       sender: Self.displayName(of: event),
                       senderId: event.sender,
                       senderAvatarUrl: Self.avatarUrl(of: event),
                       body: Self.body(of: content.kind),
                       date: Self.date(from: event.timestamp),
                       isOwn: event.isOwn,
                       isEdited: Self.isEdited(content.kind),
                       sendState: Self.sendState(of: event.localSendState),
                       reactions: reactions,
                       mentions: Self.mentions(of: content.kind),
                       isEditable: event.isEditable,
                       canReply: event.canBeRepliedTo,
                       replyTo: Self.replyPreview(of: content.inReplyTo),
                       media: Self.media(of: content.kind),
                       notice: Self.notice(of: content.kind),
                       itemID: event.eventOrTransactionId)
    }

    /// Flattens the SDK's reply details for display. The replied-to event often
    /// isn't loaded yet, in which case we still show a chip — just an empty one.
    private static func replyPreview(of details: InReplyToDetails?) -> ReplyPreview? {
        guard let details else { return nil }
        let eventId = details.eventId()
        guard case .ready(let content, let sender, let profile, _, _) = details.event(),
              case .msgLike(let msgLike) = content else {
            return ReplyPreview(eventId: eventId, senderId: nil, sender: nil, body: nil)
        }
        var name = sender
        if case .ready(let displayName, _, _) = profile, let displayName { name = displayName }
        return ReplyPreview(eventId: eventId, senderId: sender, sender: name, body: Self.body(of: msgLike.kind))
    }

    /// Finds the entry holding `eventId`, for scrolling to a reply's target.
    /// Nil when it hasn't been paginated in yet.
    func entryID(forEvent eventId: String) -> String? {
        entries.first { entry in
            guard case .message(let message) = entry,
                  case .eventId(let id) = message.itemID else { return false }
            return id == eventId
        }?.id
    }

    
    /// Plain-text form of a message, for reply chips and as the `Message.body`
    /// fallback. Always succeeds, even for kinds the timeline shows as a `Notice`.
    static func body(of kind: MsgLikeKind) -> String {
        switch kind {
        case .message(let content): content.body
        case .sticker(let body, _, _): body
        case .redacted: "Message deleted"
        case .unableToDecrypt: "Unable to decrypt"
        case .poll(let question, _, _, _, _, _, _): "Poll: \(question)"
        case .liveLocation: "Live location"
        case .other(let eventType): "Unsupported message (\(Self.label(for: eventType)))"
        }
    }

    /// Explains a message the timeline can't show as normal text. Nil for
    /// ordinary text messages and images/stickers, which render as usual.
    private static func notice(of kind: MsgLikeKind) -> Notice? {
        switch kind {
        case .redacted:
            return Notice(icon: "trash", title: "Message deleted",
                          detail: "This message was removed by its sender or a room moderator.",
                          isRedaction: true)
        case .unableToDecrypt(let msg):
            return Notice(icon: "lock.trianglebadge.exclamationmark", title: "Unable to decrypt",
                          detail: Self.explanation(for: msg))
        case .poll(let question, _, _, _, _, _, _):
            return Notice(icon: "chart.bar", title: "Poll: \(question)",
                          detail: "Polls aren't supported in Crux yet — open this room in another client to vote.")
        case .liveLocation:
            return Notice(icon: "location", title: "Live location",
                          detail: "Live location sharing isn't supported in Crux yet.")
        case .other(let eventType):
            return Notice(icon: "questionmark.square", title: "Unsupported message",
                          detail: "Crux doesn't know how to show this yet (\(Self.label(for: eventType))).")
        case .message, .sticker:
            return nil
        }
    }

    /// A short, human name for an event type the timeline falls back to a notice for.
    private static func label(for eventType: MessageLikeEventType) -> String {
        switch eventType {
        case .callInvite, .callAnswer, .callCandidates, .callHangup, .callNegotiate,
             .callNotify, .callReject, .callSdpStreamMetadataChanged, .callSelectAnswer,
             .rtcDecline, .rtcNotification:
            "call"
        case .keyVerificationAccept, .keyVerificationCancel, .keyVerificationDone,
             .keyVerificationKey, .keyVerificationMac, .keyVerificationReady, .keyVerificationStart:
            "verification"
        case .pollEnd, .pollResponse, .unstablePollEnd, .unstablePollResponse, .unstablePollStart:
            "poll"
        case .beacon, .location:
            "location"
        case .other(let raw):
            raw
        default:
            "unknown type"
        }
    }

    /// A plain-language reason for a UTD, from the SDK's best guess at its cause.
    private static func explanation(for msg: EncryptedMessage) -> String {
        guard case .megolmV1AesSha2(_, let cause) = msg else {
            return "This message couldn't be decrypted."
        }
        switch cause {
        case .sentBeforeWeJoined:
            return "Sent before you joined this room, so your device never received the keys."
        case .verificationViolation:
            return "Sent by someone whose identity has changed since you last verified them."
        case .unsignedDevice:
            return "Sent from a device that isn't signed by its owner."
        case .unknownDevice:
            return "Sent from a device Crux can't verify — it may have since been removed."
        case .historicalMessageAndBackupIsDisabled:
            return "Sent before this device existed, and key backup is turned off."
        case .historicalMessageAndDeviceIsUnverified:
            return "Sent before this device existed — verify this device in Settings to retrieve the keys."
        case .withheldForUnverifiedOrInsecureDevice:
            return "The sender withheld the keys because this device doesn't meet their security requirements."
        case .withheldBySender:
            return "The sender didn't share the keys with this device."
        case .unknown:
            return "Crux doesn't have an explanation for this one — it may be a temporary sync issue."
        }
    }

    /// get attachment from message, or nil if it's text-only
    private static func media(of kind: MsgLikeKind) -> MediaAttachment? {
        switch kind {
        case .sticker(_, let info, let source):
            return MediaAttachment(id: source.url(), kind: .image, source: source,
                                   thumbnailSource: info.thumbnailSource,
                                   filename: "", caption: nil, width: info.width, height: info.height)

        case .message(let content):
            switch content.msgType {
            case .image(let image):
                return MediaAttachment(id: image.source.url(), kind: .image, source: image.source,
                                       thumbnailSource: image.info?.thumbnailSource,
                                       filename: image.filename, caption: image.caption,
                                       width: image.info?.width, height: image.info?.height)
            case .video(let video):
                return MediaAttachment(id: video.source.url(), kind: .video, source: video.source,
                                       thumbnailSource: video.info?.thumbnailSource,
                                       filename: video.filename, caption: video.caption,
                                       width: video.info?.width, height: video.info?.height)
            case .audio(let audio):
                return MediaAttachment(id: audio.source.url(), kind: .audio, source: audio.source,
                                       thumbnailSource: nil,
                                       filename: audio.filename, caption: audio.caption,
                                       width: nil, height: nil)
            case .file(let file):
                return MediaAttachment(id: file.source.url(), kind: .file, source: file.source,
                                       thumbnailSource: file.info?.thumbnailSource,
                                       filename: file.filename, caption: file.caption,
                                       width: nil, height: nil)
            default:
                return nil
            }

        default:
            return nil
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
                       replyTo: TimelineModel.ReplyPreview? = nil,
                       media: TimelineModel.MediaAttachment? = nil,
                       notice: TimelineModel.Notice? = nil) -> Self {
        .init(id: id, sender: sender, senderId: senderId, senderAvatarUrl: senderAvatarUrl, body: body, date: Date(),
              isOwn: isOwn, isEdited: isEdited, sendState: sendState,
              reactions: reactions, mentions: mentions, isEditable: isOwn, canReply: true,
              replyTo: replyTo, media: media, notice: notice, itemID: .eventId(eventId: id))
    }
}

extension TimelineModel.MediaAttachment {
    static func sample(kind: Kind = .image,
                       filename: String = "IMG_4032.jpeg",
                       caption: String? = nil,
                       width: UInt64? = 1600,
                       height: UInt64? = 1200) -> Self {
        .init(id: "mxc://example.org/sample",
              kind: kind,
              source: try! MediaSource.fromUrl(url: "mxc://example.org/sample"),
              thumbnailSource: nil,
              filename: filename,
              caption: caption,
              width: width,
              height: height)
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
