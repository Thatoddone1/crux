//
//  RoomView.swift
//  Crux
//

import SwiftUI

struct RoomView: View {
    private let name: String
    @State private var model: TimelineModel
    @State private var errorMessage: String?

    init(summary: RoomListModel.Summary) {
        name = summary.name
        _model = State(initialValue: TimelineModel(room: summary.room))
    }

    var body: some View {
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
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                try await model.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    

    private func send(_ draft: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
