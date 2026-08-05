//
//  Chip.swift
//  Crux
//
//  Created by Joshua Kellman on 8/5/26.
//

import SwiftUI

/// A small tinted capsule tagging one fact about a room.
struct Chip: View {
    let icon: String
    let label: String
    let color: Color
    /// Dropped when a row has more chips than fit; the glyph and tint still say
    /// which one it is.
    var showsLabel = true

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .imageScale(.small)
            if showsLabel { Text(label) }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, showsLabel ? 7 : 5)
        .padding(.vertical, 3)
        .glassEffect(.regular.tint(color.opacity(0.2)), in: .capsule)
        .fixedSize()
        .accessibilityLabel(label)
    }

    func showingLabel(_ shows: Bool) -> Chip {
        Chip(icon: icon, label: label, color: color, showsLabel: shows)
    }

    enum Presets {
        static let muted = Chip(icon: "bell.slash.fill", label: "Muted", color: .secondary)
        static let lowPriority = Chip(icon: "arrow.down.circle.fill", label: "Low", color: .gray)
        static let group = Chip(icon: "person.2.fill", label: "Group", color: .purple)
        static let direct = Chip(icon: "person.fill", label: "Direct", color: .blue)
        static let favorite = Chip(icon: "star.fill", label: "Favorite", color: .yellow)
        /// Unread messages that mention you. Kept visually distinct from the
        /// notification-setting chips below — `@` and red for "someone said your
        /// name", a bell for "this is how the room notifies you" — since
        /// "Mentioned" and "Mentions Only" otherwise read as the same thing.
        static let mentioned = Chip(icon: "at", label: "Mentioned", color: .red)
        static let mentionsOnly = Chip(icon: "bell.badge.fill", label: "Mentions Only", color: .orange)
        static let allMessages = Chip(icon: "bell.fill", label: "All Messages", color: .teal)

        static func notification(_ label: RoomModel.NotificationLabel) -> Chip {
            switch label {
            case .muted: muted
            case .mentionsOnly: mentionsOnly
            case .allMessages: allMessages
            }
        }
    }

}


struct RoomChips: View {
    var isMentioned = false
    var isFavorite = false
    var isDirect = false
    var isLowPriority = false
    /// How the room notifies, when that's worth showing. See
    /// `RoomModel.notificationLabel` for what "worth showing" means.
    var notification: RoomModel.NotificationLabel?

    var body: some View {
        //default to smaller view if it doesnt fit
        ViewThatFits(in: .horizontal) {
            row(showsLabels: true)
            row(showsLabels: false)
        }
    }

    private func row(showsLabels: Bool) -> some View {
        HStack(spacing: 5) {
            (isDirect ? Chip.Presets.direct : Chip.Presets.group).showingLabel(showsLabels)
            if isMentioned { Chip.Presets.mentioned.showingLabel(showsLabels) }
            if isFavorite { Chip.Presets.favorite.showingLabel(showsLabels) }
            if isLowPriority { Chip.Presets.lowPriority.showingLabel(showsLabels) }
            if let notification {
                Chip.Presets.notification(notification).showingLabel(showsLabels)
            }
        }
    }
}

extension RoomChips {
    @MainActor
    init(_ room: RoomModel) {
        self.init(isMentioned: room.unreadMentions > 0,
                  isFavorite: room.isFavorite,
                  isDirect: room.isDirect,
                  isLowPriority: room.isLowPriority,
                  notification: room.notificationLabel)
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 12) {
        RoomChips(isDirect: true)
        RoomChips(isMentioned: true, isFavorite: true)
        RoomChips(isMentioned: true, isDirect: true, notification: .muted)
        RoomChips(isLowPriority: true, notification: .mentionsOnly)
        RoomChips(isFavorite: true, notification: .allMessages)
    }
    .padding()
}
#endif
