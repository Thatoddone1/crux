//
//  MountainCard.swift
//  Crux
//
//  Created by Joshua Kellman on 7/22/26.
//

import SwiftUI

struct MountainCard: View {

    let messages: [TimelineModel.Message]
    let roomName: String
    let isFavorite: Bool
    let priorityScore: Int
    /// True only when this card is front-and-center in its stack.
    var isFocused: Bool = true
    var canSend: Bool = true
    let onSend: (_ draft: String) -> Void
    var onReact: ((_ message: TimelineModel.Message, _ key: String) -> Void)? = nil
    /// Tapping the header opens the real room. Nil for receding/peeking cards.
    var onOpen: (() -> Void)? = nil

    private var shape: some Shape { .rect(cornerRadius: 24) }

    var body: some View {
        content
            .glassEffect(isFocused ? .regular.interactive() : .regular, in: shape)
            .padding()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(messages) { message in
                MessageBubble(message: message,
                              onReact: onReact.map { react in { key in react(message, key) } })
            }
            if canSend {
                Composer(onSend: onSend)
            } else {
                Text("You don't have permission to send here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        Group {
            if let onOpen {
                headerRow.contentShape(.rect).onTapGesture(perform: onOpen)
            } else {
                headerRow
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            Text(roomName)
                .font(.headline)
                .fontWeight(.heavy)
                .lineLimit(1)
            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            scoreBadge
        }
    }

    private var scoreBadge: some View {
        HStack(spacing: 2) {
            Text(priorityScore.description).fontWeight(.bold)
            Text("/100").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.15), in: .capsule)
    }
}
#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    VStack {
        MountainCard(
            messages: [
                .sample(sender: "Person A", body: "This is a wonderful message"),
                .sample(sender: "Person A", body: "Message 2"),
            ],
            roomName: "Wonderful Group!",
            isFavorite: true,
            priorityScore: 64,
            isFocused: true,
            onSend: { draft in print("sent: \(draft)") }
        )
        MountainCard(
            messages: [.sample(sender: "Person A", body: "A receding, unfocused card")],
            roomName: "Background Room",
            isFavorite: false,
            priorityScore: 12,
            isFocused: false,
            onSend: { draft in print("sent: \(draft)") }
        )
    }
}
#endif
