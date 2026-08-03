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

    /// Opening a room pushes onto this stack's own nav, so "back" returns here.
    @State private var path = NavigationPath()

    /// The scored, frozen deck. Owned here so it survives tab switches without
    /// re-sorting — only a fresh launch starts it over.
    @State private var model = MountainModel()

    private var unread: [RoomListModel.Summary] { session.roomList.summaries.filter(\.hasUnread) }
    private var peakPile: [RoomListModel.Summary] { model.peak }
    private var slopePile: [RoomListModel.Summary] { model.slope }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .overlay(SettingsButton(), alignment: .topTrailing)
                .sensoryFeedback(.selection, trigger: expanded)
                .navigationDestination(for: String.self) { roomId in
                    RoomView(roomId: roomId)
                }
                .task {
                    // Wait for room info, or the first sort freezes an empty deck.
                    await session.roomList.awaitRoomsReady()
                    await model.loadIfNeeded(unread: unread)
                }
                .onChange(of: unread.map(\.id)) { _, _ in
                    model.syncNewCards(unread: unread)   // newly-unread rooms trickle in, scored one by one
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            DeckLoadingView()
        case .ready where peakPile.isEmpty && slopePile.isEmpty:
            ContentUnavailableView("All caught up",
                                   systemImage: "checkmark.circle",
                                   description: Text("Unread rooms stack up here."))
        case .ready:
            VStack(spacing: 0) {
                header(.peak, title: "Peak", icon: "mountain.2.fill", items: peakPile)
                if effectiveExpanded == .peak { deck(peakPile) }

                header(.slope, title: "Slope", icon: "arrow.down.forward", items: slopePile)
                if effectiveExpanded == .slope { deck(slopePile) }

                // Muted pile disabled for now, I'll add it in later
            }
        }
    }

    // MARK: - Pieces

    private func deck(_ items: [RoomListModel.Summary]) -> some View {
        CardStack(items: items, onDismiss: { summary in
            hasSeenSwipeHint = true      // they just learned the gesture
            model.dismiss(summary)       // drop from the pile...
            Task { await session.roomList.markRead(summary) }   // ...and mark it read
        }, onOpen: { summary in
            path.append(summary.id)
        }) { summary, isFocused, onOpen in
            MountainCardCell(summary: summary, score: model.scores[summary.id] ?? 0,
                             isFocused: isFocused, onOpen: onOpen)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
        // Opaque bar so peeking cards slide cleanly underneath, keeping the
        // title readable; lifted above the deck's overflow.
        .background(.ultraThinMaterial)
        .zIndex(1)
    }

    // MARK: - Buckets

    /// Never leaves an empty pile open (nothing to show): falls back to the other one so the screen is always filled.
    private var effectiveExpanded: Pile {
        switch expanded {
        case .peak: return peakPile.isEmpty ? .slope : .peak
        case .slope: return slopePile.isEmpty ? .peak : .slope
        }
    }
}

/// The split-second sort screen: a pulsing peak, a spinner, and status text that
/// cycles so the wait reads as deliberate work, not a hang.
private struct DeckLoadingView: View {
    private static let phrases = ["Sorting your mountain…", "Reading the rooms…", "Ranking your peaks…"]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            ProgressView()
                .controlSize(.large)
            Text(Self.phrases[index])
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.1))
                withAnimation(.easeInOut) { index = (index + 1) % Self.phrases.count }
            }
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
