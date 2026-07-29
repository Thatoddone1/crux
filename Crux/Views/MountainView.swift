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
        case mountain, slope
        var other: Pile { self == .mountain ? .slope : .mountain }
    }
    /// Which pile is open (accordion — only one at a time). Defaults to mountain,
    /// the priority view; `effectiveExpanded` falls back to slope until something
    /// has scored high enough to land on the mountain.
    @State private var expanded: Pile = .mountain

    /// Score at or above which a room is important enough to go to mountain
    private static let mountainThreshold = 50

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
                    header(.mountain, title: "Mountain", icon: "mountain.2.fill", items: mountainPile)
                    if effectiveExpanded == .mountain { deck(mountainPile) }

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
        CardDeck(items: items) { summary in
            MountainCardListView(summary: summary)
        }
        .frame(maxHeight: .infinity)
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

    
    private var mountainPile: [RoomListModel.Summary] {
        pile.filter { score(for: $0) >= Self.mountainThreshold }
            .sorted { score(for: $0) > score(for: $1) }
    }

    private var slopePile: [RoomListModel.Summary] {
        pile.filter { score(for: $0) < Self.mountainThreshold }
            .sorted { score(for: $0) > score(for: $1) }
    }

    private func score(for summary: RoomListModel.Summary) -> Int {
        session.roomList.priorityScores[summary.id] ?? 0
    }

    /// Never leaves an empty pile open (nothing to show): falls back to the other one so the screen is always filled.
    private var effectiveExpanded: Pile {
        switch expanded {
        case .mountain: return mountainPile.isEmpty ? .slope : .mountain
        case .slope: return slopePile.isEmpty ? .mountain : .slope
        }
    }
}
