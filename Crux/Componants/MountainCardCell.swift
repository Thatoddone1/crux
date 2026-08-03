//
//  MountainCardCell.swift
//  Crux
//

import SwiftUI

/// Connects one room summary to its shared `RoomDetailsModel` and feeds it to `MountainCard`.
struct MountainCardCell: View {
    let summary: RoomListModel.Summary
    var score: Int = 0
    var isFocused: Bool = true
    var onOpen: (() -> Void)? = nil
    @Environment(UserSession.self) var session
    @State private var details: RoomDetailsModel?

    var body: some View {
        MountainCard(
            messages: latestMessages,
            roomName: summary.name,
            isFavorite: summary.isFavorite,
            priorityScore: score,
            isFocused: isFocused,
            canSend: canSend,
            onSend: { text in Task { try? await details?.timeline.send(text) } },
            onReact: { message, key in Task { try? await details?.timeline.toggleReaction(key, on: message) } },
            onOpen: onOpen
        )
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
