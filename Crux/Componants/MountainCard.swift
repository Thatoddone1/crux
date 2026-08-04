//
//  MountainCard.swift
//  Crux
//
//  Created by Joshua Kellman on 7/22/26.
//

import SwiftUI

/// Just the message content and composer — the room's name, avatar and sort
/// badges live above it in `MountainCardHeader`, a separate floating pill.
struct MountainCard: View {

    let messages: [TimelineModel.Message]
    /// True only when this card is front-and-center in its stack.
    var isFocused: Bool = true
    var canSend: Bool = true
    let onSend: (_ draft: String) -> Void
    var onReact: ((_ message: TimelineModel.Message, _ key: String) -> Void)? = nil
    var composerFocus: FocusState<Bool>.Binding

    private var shape: some Shape { .rect(cornerRadius: 24) }

    var body: some View {
        content
            .glassEffect(isFocused ? .regular.interactive() : .regular, in: shape)
            .padding()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { message in
                    MessageBubble(message: message,
                                  onReact: onReact.map { react in { key in react(message, key) } },
                                  maxLines: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { composerFocus.wrappedValue = false }
            if canSend {
                Composer(onSend: onSend, focus: composerFocus)
            } else {
                Text("You don't have permission to send here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    @FocusState var focus: Bool
        VStack {
            MountainCard(
                messages: [
                    .sample(sender: "Person A", body: "This is a wonderful message"),
                    .sample(sender: "Person A", body: "Message 2"),
                ],
                isFocused: true,
                onSend: { draft in print("sent: \(draft)") },
                composerFocus: $focus
            )
            MountainCard(
                messages: [.sample(sender: "Person A", body: "A receding, unfocused card")],
                isFocused: false,
                onSend: { draft in print("sent: \(draft)") },
                composerFocus: $focus
            )
        }
}

#endif
