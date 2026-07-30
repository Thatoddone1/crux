//
//  MountainView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/21/26.
//

import SwiftUI

struct MountainView: View {
    @Environment(UserSession.self) var session

    private enum Pile {
        case peak, slope
        var other: Pile { self == .peak ? .slope : .peak }
    }
    /// Which pile is open (accordion — only one at a time). Defaults to peak,
    /// the priority view; `effectiveExpanded` falls back to slope until something
    /// has scored high enough to land on the peak.
    @State private var expanded: Pile = .peak

    /// Show the swipe-to-read hint until the user dismisses their first card.
    @AppStorage("hasSeenSwipeHint") private var hasSeenSwipeHint = false

    /// Score at or above which a room is important enough to go to mountain
    private static let peakThreshold = 50

    private var pile: [RoomListModel.Summary] {
        session.roomList.summaries.filter(\.hasUnread)
    }

    var body: some View {
        Group {
            if pile.isEmpty {
                ContentUnavailableView("All caught up",
                                       systemImage: "checkmark.circle",
                                       description: Text("Unread rooms stack up here."))
            } else {
                VStack(spacing: 0) {
                    header(.peak, title: "Peak", icon: "mountain.2.fill", items: peakPile)
                    if effectiveExpanded == .peak { deck(peakPile) }

                    header(.slope, title: "Slope", icon: "arrow.down.forward", items: slopePile)
                    if effectiveExpanded == .slope { deck(slopePile) }

                    // Muted pile disabled for now, I'll add it in later
                }
            }
        }
        .overlay(SettingsButton(), alignment: .topTrailing)
    }

    // MARK: - Pieces

    private func deck(_ items: [RoomListModel.Summary]) -> some View {
        CardDeck(items: items, onDismiss: { summary in
            hasSeenSwipeHint = true      // they just learned the gesture
            Task { await session.roomList.markRead(summary) }
        }) { summary in
            MountainCardListView(summary: summary)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if !hasSeenSwipeHint {
                SwipeHint()
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: hasSeenSwipeHint)
        .transition(.opacity)
    }

   /// bar for each pile to open and close it
    private func header(_ target: Pile, title: String, icon: String,
                        items: [RoomListModel.Summary]) -> some View {
        let isOpen = effectiveExpanded == target
        return Button {
            withAnimation(.spring) { expanded = isOpen ? target.other : target }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.heavy)
                Text(items.count.description)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            // Clear of the SettingsButton overlaid at the top-trailing corner.
            .padding(.trailing, 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(items.isEmpty)
    }

    // MARK: - Buckets

    
    private var peakPile: [RoomListModel.Summary] {
        pile.filter { score(for: $0) >= Self.peakThreshold }
            .sorted { score(for: $0) > score(for: $1) }
    }

    private var slopePile: [RoomListModel.Summary] {
        pile.filter { score(for: $0) < Self.peakThreshold }
            .sorted { score(for: $0) > score(for: $1) }
    }

    private func score(for summary: RoomListModel.Summary) -> Int {
        session.roomList.priorityScores[summary.id] ?? 0
    }

    /// Never leaves an empty pile open (nothing to show): falls back to the other one so the screen is always filled.
    private var effectiveExpanded: Pile {
        switch expanded {
        case .peak: return peakPile.isEmpty ? .slope : .peak
        case .slope: return slopePile.isEmpty ? .peak : .slope
        }
    }
}

/// A gentle first-run nudge teaching the swipe-right-to-mark-read gesture.
private struct SwipeHint: View {
    @State private var nudge = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
            Text("Swipe a card right to mark it read")
                .font(.footnote.weight(.medium))
            Image(systemName: "arrow.right")
                .offset(x: nudge ? 5 : -3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.secondary.opacity(0.2)))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                nudge = true
            }
        }
    }
}
