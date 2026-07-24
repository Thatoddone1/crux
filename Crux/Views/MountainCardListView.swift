//
//  MountainCardListView.swift
//  Crux
//

import SwiftUI


struct MountainCardListView: View {
    let summary: RoomListModel.Summary
    @State private var model: TimelineModel

    init(summary: RoomListModel.Summary) {
        self.summary = summary
        _model = State(initialValue: TimelineModel(room: summary.room))
    }

    var body: some View {
        MountainCard(
            messages: latestMessages,
            roomName: summary.name,
            onSend: { text in Task { try? await model.send(text) } }
        )
        .task { try? await model.start() }
    }

    /// The last few messages (newest last), flattened to plain values for the card.
    private var latestMessages: [TimelineModel.Message] {
        let messages = model.entries.compactMap { entry -> TimelineModel.Message? in
            if case .message(let message) = entry { return message }
            return nil
        }
        return Array(messages.suffix(4))
    }
}
