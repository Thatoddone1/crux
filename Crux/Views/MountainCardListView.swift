//
//  MountainCardListView.swift
//  Crux
//

import SwiftUI


struct MountainCardListView: View {
    let summary: RoomListModel.Summary
    @Environment(UserSession.self) var session
    @State private var model: TimelineModel

    init(summary: RoomListModel.Summary) {
        self.summary = summary
        _model = State(initialValue: TimelineModel(room: summary.room))
    }

    var body: some View {
        MountainCard(
            messages: latestMessages,
            roomName: summary.name,
            isFavorite: summary.isFavorite,
            isDirect: summary.isDirect,
            priorityScore: session.roomList.priorityScores[summary.id] ?? 0,
            onSend: { text in Task { try? await model.send(text) } }
        )
        .task { try? await model.start() }
        // Keyed on the newest message's id, not `.count`: history pagination
        // prepends older messages without changing the last one.
        .task(id: latestMessages.last?.id) {
            await session.roomList.updateScore(for: summary, messages: allMessages)
        }
    }

    private var allMessages: [TimelineModel.Message] {
        model.entries.compactMap { entry -> TimelineModel.Message? in
            if case .message(let message) = entry { return message }
            return nil
        }
    }

    /// The last few messages (newest last), flattened to plain values for the card.
    private var latestMessages: [TimelineModel.Message] {
        Array(allMessages.suffix(4))
    }
}
