//
//  MessageBubble.swift
//  Crux
//
//  Created by Joshua Kellman on 7/20/26.
//

import SwiftUI



struct MessageBubble: View {
    let message: TimelineModel.Message
    var onReport: (() -> Void)? = nil
    var onViewProfile: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onReact: ((_ key: String) -> Void)? = nil
    
    let defaultEmojis  = ["❤️", "👍️", "👎️", "😀", "🚡", "❓️", "🤔", "😱", "😲", "😴", "😵", "😷", "😸", "😹", "😺", "😻", "😼", "😽", "😾", "😿", "🙀", "👻", "🎃", "👹", "👺", "🤡", "👽", "👾", "🤖", "🤡", "👻", "🎃", "👹", "🤡", "👽", "👾", "🤖", "🤡", "👻"]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.sender)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(LocalizedStringKey(message.body))
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
                        Button("\(reaction.key) \(reaction.count)") {
                            onReact?(reaction.key)
                        }
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
        .contextMenu {
            //reactions pallete
            if let onReact {
                ControlGroup {
                    ForEach(defaultEmojis, id: \.self) { emoji in
                        
                        //is that emoji already selected?
                        let isSelected = message.reactions.contains(where: { $0.key == emoji })
                        
                        Button {
                            onReact(emoji)
                        } label: {
                            if isSelected {
                                Text("\(emoji) ✓")
                            } else {
                                Text(emoji)
                            }
                        }
                    }
                    
                }
                .controlGroupStyle(.palette) // <-- This modifier prevents the vertical stacking
            }
            
            // 2. Existing Vertical Menu Items
            if let onDelete {
                Button("Delete Message", systemImage: "delete.left", role: .destructive, action: onDelete)
            }
            
            if let onEdit {
                Button("Edit Message", systemImage: "pencil", action: onEdit)
            }
            
            if let onViewProfile {
                Button("View Profile", systemImage: "person.crop.circle", action: onViewProfile)
            }
            
            if let onReport {
                if !message.isOwn {
                    Button("Report Message", systemImage: "flag", role: .destructive, action: onReport)
                }
            }
            
            Button("Copy Message", systemImage: "document.on.document") {
                UIPasteboard.general.string = message.body
            }
        }
    }
}

#if DEBUG
//some sample messages
#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        MessageBubble(
            message: .sample(sender: "PersonA", body: "This is a wonderful test message. The point of this is to test Crux.")
        )

        MessageBubble(message: .sample(sender: "PersonB", body: "This message was edited.",
            isOwn: false, isEdited: true,
            reactions: [.init(key: "👍", count: 2, includesMe: true),
                        .init(key: "🎉", count: 1, includesMe: false)]),
                      onReport: {}, onViewProfile:{}, onDelete: {}, onEdit: {}, onReact: {key in}
        )

        MessageBubble(message: .sample(sender: "PersonB", body: "This one hasn't sent yet.",
            isOwn: true, sendState: .sending),
                      onReport: {}, onViewProfile:{})

        MessageBubble(message: .sample(sender: "PersonB", body: "This one was rejected by the server.",
            isOwn: true, sendState: .failed),
                      onReport: {}, onViewProfile:{})
    }
    .padding()
}
#endif
