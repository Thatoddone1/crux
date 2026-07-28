//
//  RoomView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

struct RoomView: View {
    let roomId: String
    @Environment(UserSession.self) private var session

    @State private var name: String?
    @State private var model: TimelineModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.entries) { entry in
                            switch entry {
                            case .message(let message):
                                MessageBubble(message: message)
                            case .dayDivider(_, let date):
                                Text(date, style: .date)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .defaultScrollAnchor(.bottom)
                .safeAreaInset(edge: .bottom) { Composer(
                    onSend: send,
                    errorMessage: errorMessage
                ) }
            } else if let errorMessage {
                ContentUnavailableView("Couldn't Open Room",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let room = try session.room(id: roomId)
                name = room.displayName() ?? room.id()
                let model = TimelineModel(room: room)
                self.model = model
                try await model.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func send(_ draft: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let model else { return }
        errorMessage = nil

        Task {
            do {
                try await model.send(text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
