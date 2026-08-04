//
//  MountainCardCell.swift
//  Crux
//

import SwiftUI

/// Connects one room summary to its shared `RoomDetailsModel` and feeds it to
/// `MountainCardHeader` + `MountainCard`.
struct MountainCardCell: View {
    let summary: RoomListModel.Summary
    var score: Int = 0
    var breakdown: MountainModel.ScoreBreakdown? = nil
    var isFocused: Bool = true
    var onOpen: (() -> Void)? = nil
    @Environment(UserSession.self) var session
    @Environment(\.deckDragCount) private var deckDragCount
    @State private var details: RoomDetailsModel?
    @FocusState private var isComposing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MountainCardHeader(
                roomName: summary.name,
                avatarUrl: summary.avatarUrl,
                unreadCount: summary.unreadMessages,
                isFavorite: summary.isFavorite,
                isDirect: summary.isDirect,
                isLowPriority: summary.isLowPriority,
                isMuted: summary.isMuted,
                isMentioned: summary.unreadMentions > 0,
                score: score,
                breakdown: breakdown,
                isFocused: isFocused,
                onOpen: onOpen
            )
            MountainCard(
                messages: latestMessages,
                isFocused: isFocused,
                canSend: canSend,
                onSend: { text in Task { try? await details?.timeline.send(text) } },
                onReact: { message, key in Task { try? await details?.timeline.toggleReaction(key, on: message) } },
                composerFocus: $isComposing
            )
        }
        .onChange(of: deckDragCount) { _, _ in isComposing = false }
        .onChange(of: isFocused) { _, focused in if !focused { isComposing = false } }
        .task {
            guard let details = try? session.roomDetails(for: summary.id) else { return }
            self.details = details
            await details.start()
        }
    }

    private var canSend: Bool {
        guard let details, details.info != nil else { return true }
        return details.canSendMessage()
    }

    private var allMessages: [TimelineModel.Message] {
        details?.timeline.entries.compactMap { entry -> TimelineModel.Message? in
            if case .message(let message) = entry { return message }
            return nil
        } ?? []
    }

    /// The last few messages (newest last), flattened to plain values for the card.
    private var latestMessages: [TimelineModel.Message] {
        Array(allMessages.suffix(4))
    }
}
