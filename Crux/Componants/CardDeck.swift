//
//  CardDeck.swift
//  Crux
//

import SwiftUI

/// A vertical deck of cards (usually the MountainCards). The focused card sits in front at full size; the
/// others tuck behind it—above and below—receding in scale, fading, and
/// dropping in z the farther they are from focus. Drag vertically (with
/// momentum) or tap a peeking card to change focus.
struct CardDeck<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// When true the pile tightens into a compact stack (for showing several
    /// piles at once); when false it's the browsable deck.
    var collapsed: Bool = false
    @ViewBuilder let card: (Item) -> Card

    /// Tracked by the item's own id, not a raw array position: if `items` reorders
    /// (e.g. a background score finishes and re-sorts the deck) the same card stays
    /// focused instead of the front slot silently showing a different room.
    @State private var focusedID: Item.ID?
    /// Live finger movement during a drag; resets to 0 automatically on release.
    @GestureState private var dragTranslation: CGFloat = 0

    private var focusedIndex: Int {
        guard let focusedID, let index = items.firstIndex(where: { $0.id == focusedID }) else { return 0 }
        return index
    }

    var body: some View {
        // A continuous focus position: an integer at rest, fractional mid-drag,
        // so every card slides smoothly under your finger. Dragging up (negative
        // translation) advances toward later cards.
        let position = CGFloat(focusedIndex) - dragTranslation / Deck.dragDistance

        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let distance = CGFloat(index) - position     // 0 == focused/front
                card(item)
                    .scaleEffect(scale(distance))
                    .offset(y: distance * peek)              // later cards below, earlier above
                    .opacity(opacity(distance))
                    .zIndex(-abs(distance))                  // focused (0) draws on top
                    .allowsHitTesting(abs(distance) < 1.5)   // only front-ish cards are tappable
                    .onTapGesture { snap(to: index) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)                                 // whole area is draggable
        .gesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    // Use the projected (momentum) end so a flick travels.
                    let moved = -value.predictedEndTranslation.height / Deck.dragDistance
                    snap(to: Int((CGFloat(focusedIndex) + moved).rounded()))
                }
        )
        .animation(.spring, value: focusedIndex)
        .animation(.spring, value: collapsed)
    }

    // MARK: - Transforms

    private var peek: CGFloat { collapsed ? Deck.peekCollapsed : Deck.peekExpanded }

    private func scale(_ distance: CGFloat) -> CGFloat {
        max(Deck.minScale, 1 - abs(distance) * Deck.scaleStep)
    }

    private func opacity(_ distance: CGFloat) -> CGFloat {
        max(0, 1 - abs(distance) * Deck.opacityStep)
    }

    private func snap(to index: Int) {
        let clamped = min(max(index, 0), items.count - 1)
        guard items.indices.contains(clamped) else { return }
        withAnimation(.spring) {
            focusedID = items[clamped].id
        }
    }
}

/// The deck's feel knobs. Non-generic + `nonisolated` for the same reasons as
/// `CardStack`'s `Tuning`.
private nonisolated enum Deck {
    static let dragDistance: CGFloat = 120   // finger travel (pt) to move one card
    static let peekExpanded: CGFloat = 80    // vertical gap between stacked cards
    static let peekCollapsed: CGFloat = 14   // tight stack when collapsed
    static let scaleStep: CGFloat = 0.09     // how fast far cards shrink
    static let minScale: CGFloat = 0.6
    static let opacityStep: CGFloat = 0.28   // how fast far cards fade (hidden past ~3.5)
}

#if DEBUG //just for previews
private struct DeckDemo: Identifiable {
    let id = UUID()
    let name: String
    let messages: [TimelineModel.Message]
}

private let deckDemos = [
    DeckDemo(name: "Design", messages: [
        .sample(sender: "Ana", body: "ship it?"),
        .sample(sender: "You", body: "one sec", isOwn: true)]),
    DeckDemo(name: "Weekend Plans", messages: [.sample(sender: "Kai", body: "hike sunday?")]),
    DeckDemo(name: "Family", messages: [.sample(sender: "Mom", body: "call me when you can")]),
    DeckDemo(name: "Work", messages: [.sample(sender: "Sam", body: "standup moved to 11")]),
    DeckDemo(name: "Climbing", messages: [.sample(sender: "Jo", body: "gym at 6?")]),
]

#Preview {
    @Previewable @State var collapsed = false
    VStack {
        Toggle("Collapsed", isOn: $collapsed).padding()
        CardDeck(items: deckDemos, collapsed: collapsed) { room in
            MountainCard(messages: room.messages, roomName: room.name,
                         isFavorite: false, isDirect: false, priorityScore: 0,
                         onSend: { _ in })
        }
    }
}
#endif
