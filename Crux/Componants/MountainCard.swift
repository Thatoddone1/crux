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
   /// no option to swipe to reply, only from the context menu
    var onReply: ((_ draft: String, _ message: TimelineModel.Message) -> Void)? = nil
    var composerFocus: FocusState<Bool>.Binding

    @State private var replyTarget: TimelineModel.Message?

    private var shape: some Shape { .rect(cornerRadius: 24) }

    var body: some View {
        content
            .glassEffect(isFocused ? .regular.interactive() : .regular, in: shape)
            .padding()
            .onChange(of: isFocused) { _, focused in if !focused { replyTarget = nil } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    MessageBubble(message: message,
                                  onReact: onReact.map { react in { key in react(message, key) } },
                                  onReply: (canSend ? onReply : nil).map { _ in
                                      { replyTarget = message; composerFocus.wrappedValue = true }
                                  },
                                  showsHeader: message.startsGroup(after: index > 0 ? messages[index - 1] : nil),
                                  maxLines: 3,
                                  mediaMaxHeight: 120,
                                  allowsFullScreenMedia: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { composerFocus.wrappedValue = false }
            if canSend {
                Composer(onSend: onSend,
                         replyingTo: replyTarget,
                         onReply: { draft, message in
                             replyTarget = nil
                             onReply?(draft, message)
                         },
                         onCancelReply: { replyTarget = nil },
                         focus: composerFocus)
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
                    .sample(sender: "Person B", senderId: "@b:example.org", body: "A different sender"),
                ],
                isFocused: true,
                onSend: { draft in print("sent: \(draft)") },
                onReply: { draft, message in print("replied \(draft) to \(message.sender)") },
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
