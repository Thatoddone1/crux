//
//  MountainCardListView.swift
//  Crux
//

import SwiftUI


struct MountainCardListView: View {
    let summary: RoomListModel.Summary
    @State private var model: TimelineModel
    @State private var priorityScore = 0

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
            priorityScore: priorityScore,
            onSend: { text in Task { try? await model.send(text) } }
        )
        .task { try? await model.start() }
        // Keyed on the newest message's id, not `.count`: history pagination
        // prepends older messages without changing the last one.
        .task(id: latestMessages.last?.id) { priorityScore = await summary.priorityScore(messages: allMessages) }
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
