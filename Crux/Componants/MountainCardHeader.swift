//
//  MountainCardHeader.swift
//  Crux
//

import SwiftUI

/// The glass pill that floats above a `MountainCard`: avatar, room name, and a
/// row of chips that show why the deck sorted it here. Tapping the name opens
/// the room; tapping the score explains it.
struct MountainCardHeader: View {
    let roomName: String
    let avatarUrl: String?
    let unreadCount: Int
    let isFavorite: Bool
    let isDirect: Bool
    let isLowPriority: Bool
    let isMuted: Bool
    let isMentioned: Bool
    let score: Int
    let breakdown: MountainModel.ScoreBreakdown?
    var isFocused: Bool = true
    var onOpen: (() -> Void)? = nil

    private var shape: some Shape { .rect(cornerRadius: 20) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarView(avatarUrl: avatarUrl, unreadCount: unreadCount)
                Text(roomName)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                if onOpen != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                if isMentioned { Chip.Presets.mentioned }
                if isFavorite { Chip.Presets.favorite }
                if isDirect { Chip.Presets.direct }
                else { Chip.Presets.group }
                if isLowPriority { Chip.Presets.lowPriority }
                if isMuted { Chip.Presets.muted }
                Spacer()
                ScoreChip(score: score, breakdown: breakdown, isInteractive: isFocused)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .glassEffect(isFocused ? .regular.interactive() : .regular, in: shape)
        .padding(.horizontal)   // matches MountainCard's outer padding, so widths line up
        .contentShape(.rect)
        .onTapGesture { onOpen?() }
    }
}

/// The score badge. Only the focused card's is tappable — a peeking neighbour
/// is partly offscreen, so its popover would anchor somewhere wrong.
private struct ScoreChip: View {
    let score: Int
    let breakdown: MountainModel.ScoreBreakdown?
    let isInteractive: Bool
    @State private var showBreakdown = false

    var body: some View {
        Group {
            if isInteractive, let breakdown {
                Button { showBreakdown = true } label: { label }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showBreakdown, arrowEdge: .top) {
                        ScoreBreakdownView(breakdown: breakdown)
                            .presentationCompactAdaptation(.popover)
                    }
            } else {
                label
            }
        }
    }

    private var label: some View {
        HStack(spacing: 3) {
            Text(score.description).fontWeight(.bold)
            Text("/100").foregroundStyle(.secondary)
            if isInteractive {
                Image(systemName: "info.circle").font(.caption2)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.18), in: .capsule)
    }

    /// Bands off the actual peak/slope cutoff, so the color says roughly where
    /// a card landed.
    private var color: Color {
        switch score {
        case 70...100: .red
        case MountainModel.peakThreshold..<70: .orange
        case 30..<MountainModel.peakThreshold: .yellow
        default: .green
        }
    }
}

private struct ScoreBreakdownView: View {
    let breakdown: MountainModel.ScoreBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Priority score").font(.subheadline.weight(.bold))
            row("Mention", breakdown.mention)
            row(breakdown.directness >= 0 ? "Direct message" : "Group chat", breakdown.directness)
            row("Favorite", breakdown.favorite)
            row("Low priority", breakdown.lowPriority)
            row("Tone (AI)", breakdown.tone)
            Divider()
            HStack {
                Text("Total").fontWeight(.semibold)
                Spacer()
                Text("\(breakdown.total)/100").fontWeight(.bold)
            }
        }
        .padding()
        .frame(width: 230)
    }

    private func row(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value >= 0 ? "+\(value)" : "\(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(value > 0 ? .green : (value < 0 ? .red : .secondary))
        }
    }
}


#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        MountainCardHeader(
            roomName: "Wonderful Group!",
            avatarUrl: nil,
            unreadCount: 3,
            isFavorite: true,
            isDirect: false,
            isLowPriority: false,
            isMuted: false,
            isMentioned: true,
            score: 82,
            breakdown: .init(mention: 40, favorite: 30, directness: -10, lowPriority: 0, tone: 22),
            onOpen: {}
        )
        MountainCardHeader(
            roomName: "Quiet DM",
            avatarUrl: nil,
            unreadCount: 0,
            isFavorite: false,
            isDirect: true,
            isLowPriority: true,
            isMuted: true,
            isMentioned: false,
            score: 12,
            breakdown: .init(mention: 0, favorite: 0, directness: 10, lowPriority: -60, tone: 8),
            onOpen: {}
        )
    }
}
#endif
