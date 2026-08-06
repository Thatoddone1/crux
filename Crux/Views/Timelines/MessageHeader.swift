//
//  MessageHeader.swift
//  Crux
//

import SwiftUI

extension TimelineModel.Message {
    ///whether this messages starts a group of close together messages from the same sender
    func startsGroup(after previous: TimelineModel.Message?) -> Bool {
        guard let previous else { return true }
        if replyTo != nil { return true }
        if previous.senderId != senderId { return true }
        return date.timeIntervalSince(previous.date) > 60
    }
}


struct MessageHeader: View {
    let message: TimelineModel.Message
    var onViewProfile: (() -> Void)? = nil
    /// Scrolls to the message being answered. Nil where there's nothing to scroll.
    var onJumpToReply: (() -> Void)? = nil

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                if let reply = message.replyTo {
                    tappable(onJumpToReply) { quoteChip(reply) }
                }
                tappable(onViewProfile) { senderChip }
            }
        }
    }

    ///wrap chip in button
    @ViewBuilder
    private func tappable<Chip: View>(_ action: (() -> Void)?,
                                      @ViewBuilder chip: () -> Chip) -> some View {
        if let action {
            Button(action: action, label: chip).buttonStyle(.plain)
        } else {
            chip()
        }
    }

    private var senderChip: some View {
        HStack(spacing: 5) {
            AvatarView(avatarUrl: message.senderAvatarUrl, size: 18)
            Text(message.sender)
                .fontWeight(.semibold)
                .foregroundStyle(Color.sender(for: message.senderId))
                .lineLimit(1)
        }
        .modifier(ChipShape())
    }

    private func quoteChip(_ reply: TimelineModel.ReplyPreview) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(reply.senderId.map(Color.sender(for:)) ?? .secondary)
                .frame(width: 2.5, height: 11)
            Text(reply.sender ?? "Message")
                .fontWeight(.medium)
                .lineLimit(1)
                .layoutPriority(1)
            if let body = reply.body {
                Text(body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if onJumpToReply != nil {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .modifier(ChipShape())
    }
}

private struct ChipShape: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(in: .capsule)
    }
}

extension Color {
    private static let senderPalette: [Color] = [.blue, .purple, .pink, .orange,
                                                 .green, .teal, .indigo, .mint]

    /// A stable colour per mxid, so a name stays recognisable down a long room.
    static func sender(for id: String) -> Color {
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return senderPalette[Int(hash % UInt64(senderPalette.count))]
    }
}
