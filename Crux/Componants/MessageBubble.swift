//
//  MessageBubble.swift
//  Crux
//
//  Created by Joshua Kellman on 7/20/26.
//

import SwiftUI



struct MessageBubble: View {
    let message: TimelineModel.Message

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.sender)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(message.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                // Dim while queued; the SDK confirms it via the listener.
                .opacity(message.sendState == .sending ? 0.6 : 1)

            if message.isEdited {
                Text("edited")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if message.sendState == .failed {
                Text("Failed to send")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if !message.reactions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(message.reactions) { reaction in
                        Text("\(reaction.key) \(reaction.count)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(reaction.includesMe ? Color.accentColor.opacity(0.25)
                                                            : Color(.systemGray5),
                                        in: .capsule)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

//some sample messages
#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        MessageBubble(message: .sample(sender: "PersonA",
            body: "This is a wonderful test message. The point of this is to test Crux."))

        MessageBubble(message: .sample(sender: "PersonB", body: "This message was edited.",
            isOwn: true, isEdited: true,
            reactions: [.init(key: "👍", count: 2, includesMe: true),
                        .init(key: "🎉", count: 1, includesMe: false)]))

        MessageBubble(message: .sample(sender: "PersonB", body: "This one hasn't sent yet.",
            isOwn: true, sendState: .sending))

        MessageBubble(message: .sample(sender: "PersonB", body: "This one was rejected by the server.",
            isOwn: true, sendState: .failed))
    }
    .padding()
}
