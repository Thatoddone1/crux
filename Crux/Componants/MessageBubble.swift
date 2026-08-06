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
    /// Starts a reply to this message. Offered in the context menu wherever it's set.
    var onReply: (() -> Void)? = nil
    /// whether to allow swiping to reply (off in places like mountain stack where that makes no sense)
    var swipeToReply: Bool = false
    /// False for a message grouped under the one above it — see `startsGroup(after:)`.
    var showsHeader: Bool = true
    /// Scrolls to the message this one replies to. Nil where there's no scroll view.
    var onJumpToReply: (() -> Void)? = nil
    /// Briefly flashed after something jumped here, so the landing is legible.
    var isHighlighted: Bool = false
    var maxLines: Int? = nil
    var mediaMaxHeight: CGFloat = 260
    var allowsFullScreenMedia: Bool = true

    let defaultEmojis  = ["❤️", "👍️", "👎️", "😀", "🚡", "❓️", "🤔", "😱", "😲", "😴", "😵", "😷"]

   ///of media
    private var showsBodyText: Bool {
        guard let media = message.media else { return true }
        return media.caption != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsHeader {
                MessageHeader(message: message,
                              onViewProfile: onViewProfile,
                              onJumpToReply: onJumpToReply)
                    .padding(.leading, 4)
            }

            if let media = message.media {
                MediaAttachmentView(media: media,
                                    maxHeight: mediaMaxHeight,
                                    allowsFullScreen: allowsFullScreenMedia)
                    .opacity(message.sendState == .sending ? 0.6 : 1)
                    .padding(.top, 4)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if showsBodyText {
                    Text(LocalizedStringKey(message.body))
                        .lineLimit(maxLines)
                        // dim while queued, confirmed by SDK and updated
                        .opacity(message.sendState == .sending ? 0.6 : 1)
                }
                Spacer(minLength: 8)
                Text(message.date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : .clear,
                    in: .rect(cornerRadius: 14))
        .animation(.easeOut(duration: 0.25), value: isHighlighted)
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
            if let onReply, message.canReply {
                Button("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
            }

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
        .replySwipe(if: swipeToReply && message.canReply, perform: onReply)
        .padding(.top, showsHeader ? 6 : 0)
    }

}

#if DEBUG
//some sample messages
#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 2) {
        MessageBubble(
            message: .sample(sender: "PersonA", senderId: "@a:example.org", body: "This is a wonderful test message. The point of this is to test Crux.")
        )

        // Grouped under the message above it — no header of its own.
        MessageBubble(message: .sample(sender: "PersonA", senderId: "@a:example.org", body: "And a second one, right underneath."),
                      showsHeader: false)

        MessageBubble(message: .sample(sender: "PersonA", senderId: "@a:example.org", body: "And a third."),
                      showsHeader: false)

        MessageBubble(message: .sample(sender: "PersonB", senderId: "@b:example.org", body: "This message was edited.",
            isOwn: false, isEdited: true,
            reactions: [.init(key: "👍", count: 2, includesMe: true),
                        .init(key: "🎉", count: 1, includesMe: false)]),
                      onReport: {}, onViewProfile:{}, onDelete: {}, onEdit: {}, onReact: {key in}
        )

        MessageBubble(message: .sample(sender: "PersonB", senderId: "@b:example.org", body: "This one hasn't sent yet.",
            isOwn: true, sendState: .sending),
                      onReport: {}, onViewProfile:{})

        MessageBubble(message: .sample(sender: "PersonB", senderId: "@b:example.org", body: "This one was rejected by the server.",
            isOwn: true, sendState: .failed),
                      onReport: {}, onViewProfile:{})

        MessageBubble(message: .sample(sender: "PersonA", senderId: "@a:example.org", body: "Yes, ship it.",
            replyTo: .init(eventId: "$1", senderId: "@b:example.org", sender: "PersonB",
                           body: "Are we happy with the new stack? It's a long quote, so it ellipses.")),
                      onReply: {}, swipeToReply: true, onJumpToReply: {})

        MessageBubble(message: .sample(sender: "PersonA", senderId: "@a:example.org", body: "A reply whose original hasn't loaded.",
            replyTo: .init(eventId: "$2", senderId: nil, sender: nil, body: nil)))
        /// body hidden since it is filename
        MessageBubble(message: .sample(sender: "PersonB", senderId: "@b:example.org",
                                       body: "IMG_4032.jpeg", media: .sample()))

        MessageBubble(message: .sample(sender: "PersonB", senderId: "@b:example.org",
                                       body: "the view from the summit",
                                       media: .sample(caption: "the view from the summit")))

        MessageBubble(message: .sample(sender: "PersonA", senderId: "@a:example.org",
                                       body: "route-notes.pdf",
                                       media: .sample(kind: .file, filename: "route-notes.pdf")))
    }
    .padding()
}
#endif
