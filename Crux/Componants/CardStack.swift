//
//  CardStack.swift
//  Crux
//

import SwiftUI


struct CardStack<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// Swipe the centred card right to dismiss it; nil disables swiping.
    var onDismiss: ((Item) -> Void)? = nil
    /// Open the centred card (e.g. into the full room); nil disables it.
    var onOpen: ((Item) -> Void)? = nil
    /// `isFocused` is true only for the centred card; `onOpen` is non-nil only
    /// there, so a card's interactive content isn't fighting a card-wide tap.
    @ViewBuilder let card: (_ item: Item, _ isFocused: Bool, _ onOpen: (() -> Void)?) -> Card

    /// The centred card, tracked by id so an appended card can't shift which one
    /// you're looking at.
    @State private var focusedID: Item.ID?
    /// Live vertical paging drag.
    @State private var dragY: CGFloat = 0
    /// Live rightward dismiss drag (centred card only).
    @State private var dragX: CGFloat = 0
    /// Which axis this drag locked onto, decided from its first movement.
    @State private var axis: Axis?
    /// The card currently flying off after a dismiss.
    @State private var dismissingID: Item.ID?
    /// True while the dismiss drag is past threshold (drives one haptic).
    @State private var armedToDismiss = false

    private var focusedIndex: Int {
        items.firstIndex { $0.id == focusedID } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let step = geo.size.height * Stack.stepFraction
            GlassEffectContainer {
                ZStack {
                    // Only the focused card and its near neighbours are mounted,
                    // so we don't open every room's timeline at once.
                    ForEach(window(), id: \.element.id) { index, item in
                        cardSlot(item, distance: index - focusedIndex, step: step)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(pagingGesture(step: step))
            }
        }
        .onChange(of: items.map(\.id), initial: true) { _, ids in reconcileFocus(ids) }
        .sensoryFeedback(.selection, trigger: focusedID)                        // ratchet tick per card
        .sensoryFeedback(.impact(weight: .medium), trigger: armedToDismiss) { _, armed in armed }
        .sensoryFeedback(.success, trigger: dismissingID) { _, id in id != nil }
    }

    /// The focused card ± a couple of neighbours, as (index, item) pairs.
    private func window() -> [(offset: Int, element: Item)] {
        Array(items.enumerated())
            .filter { abs($0.offset - focusedIndex) <= Stack.windowRadius }
            .map { (offset: $0.offset, element: $0.element) }
    }

    private func cardSlot(_ item: Item, distance: Int, step: CGFloat) -> some View {
        let isFocused = distance == 0
        let dismissing = item.id == dismissingID
        let dx = dismissing ? Stack.flyOff : (isFocused && axis == .horizontal ? max(0, dragX) : 0)
        // A dismissing card stays centred as it flies right, so it clears out
        // while the next card rises into its place.
        let dy = dismissing ? 0 : CGFloat(distance) * step + (axis == .vertical ? dragY : 0)
        return ZStack(alignment: .leading) {
            if isFocused && dx > 1 {
                Label("Read", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .padding(.leading, 32)
                    .opacity(min(Double(dx / Stack.dismissDistance), 1))
            }
            card(item, isFocused, isFocused ? { onOpen?(item) } : nil)
                .offset(x: dx)
                .geometryGroup()   // isolate the swipe transform from the glass
        }
        // Neighbours only fade back — no scale, which glitched as cards of
        // different heights grew/shrank on paging.
        .opacity(isFocused ? 1 : Stack.neighbourOpacity)
        .offset(y: dy)
        .zIndex(dismissing ? 2 : (isFocused ? 1 : 0))
    }

    /// One drag handles both axes: it locks to whichever direction it starts
    /// moving. Vertical pages the deck; horizontal (on the centred card) marks
    /// it read.
    private func pagingGesture(step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if axis == nil {
                    axis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                switch axis {
                case .horizontal:
                    guard onDismiss != nil else { return }
                    dragX = value.translation.width
                    armedToDismiss = dragX > Stack.dismissDistance
                case .vertical:
                    dragY = damped(value.translation.height)
                case nil:
                    break
                }
            }
            .onEnded { value in
                defer { axis = nil; armedToDismiss = false }
                switch axis {
                case .horizontal:
                    if value.translation.width > Stack.dismissDistance,
                       let item = items[safe: focusedIndex] {
                        dismiss(item)
                    } else {
                        withAnimation(Stack.snap) { dragX = 0 }
                    }
                case .vertical:
                    // Advance one card per swipe (never lands between); a flick
                    // counts via its projected travel.
                    let projected = value.predictedEndTranslation.height
                    let move = projected < -Stack.pageThreshold ? 1 : (projected > Stack.pageThreshold ? -1 : 0)
                    page(by: move)
                case nil:
                    break
                }
            }
    }

    /// Resists dragging past the first/last card so the ends feel like a wall.
    private func damped(_ y: CGFloat) -> CGFloat {
        let atTop = focusedIndex == 0 && y > 0
        let atEnd = focusedIndex == items.count - 1 && y < 0
        return (atTop || atEnd) ? y * 0.3 : y
    }

    private func page(by move: Int) {
        let target = min(max(focusedIndex + move, 0), items.count - 1)
        withAnimation(Stack.snap) {
            dragY = 0
            if let id = items[safe: target]?.id { focusedID = id }
        }
    }

    /// Flies the card off to the right and hands removal to the caller. Focus
    /// slides to a neighbour in the same motion; the flown card is only dropped
    /// once the caller's list no longer contains it, so nothing pops back.
    private func dismiss(_ item: Item) {
        let nextID = items[safe: focusedIndex + 1]?.id ?? items[safe: focusedIndex - 1]?.id
        withAnimation(Stack.snap) {
            dismissingID = item.id       // flies off to the right
            dragX = 0
            if let nextID { focusedID = nextID }   // next card rises to centre meanwhile
        } completion: {
            // Only now hand removal to the caller — removing mid-flight would
            // blink the card out instead of letting it (and the Read reveal)
            // finish. `reconcileFocus` clears `dismissingID` once it's gone.
            onDismiss?(item)
        }
    }

    /// Keeps `focusedID` on a real card as the list changes (first load, an
    /// appended card, or the caller removing a dismissed one), and releases the
    /// fly-off state once that card is actually gone.
    private func reconcileFocus(_ ids: [Item.ID]) {
        if focusedID == nil || !ids.contains(where: { $0 == focusedID }) {
            focusedID = ids.first { $0 != dismissingID } ?? ids.first
        }
        if let dismissingID, !ids.contains(where: { $0 == dismissingID }) { self.dismissingID = nil }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The deck's feel knobs. Non-generic + `nonisolated` so they're usable from
/// the generic `CardStack` without each instantiation re-specializing them.
private nonisolated enum Stack {
    static let stepFraction: CGFloat = 0.72    // centre-to-centre gap, as a share of height (keeps cards clear of each other)
    static let windowRadius = 2                // how many neighbours each side to mount
    static let neighbourOpacity: CGFloat = 0.5 // peeking cards' opacity
    static let pageThreshold: CGFloat = 60     // projected travel (pt) to turn a page
    static let dismissDistance: CGFloat = 120  // rightward travel (pt) to mark read
    static let flyOff: CGFloat = 900           // off-screen resting x for a dismissed card
    static let snap: Animation = .spring(response: 0.32, dampingFraction: 0.82)
}

#if DEBUG //just for previews
private struct StackDemo: Identifiable {
    let id = UUID()
    let name: String
    let messages: [TimelineModel.Message]
}

private let stackDemos = [
    StackDemo(name: "Design", messages: [
        .sample(sender: "Ana", body: "ship it?"),
        .sample(sender: "You", body: "one sec", isOwn: true)]),
    StackDemo(name: "Weekend Plans", messages: [.sample(sender: "Kai", body: "hike sunday?")]),
    StackDemo(name: "Family", messages: [.sample(sender: "Mom", body: "call me when you can")]),
    StackDemo(name: "Work", messages: [.sample(sender: "Sam", body: "standup moved to 11")]),
    StackDemo(name: "Climbing", messages: [.sample(sender: "Jo", body: "gym at 6?")]),
]

#Preview {
    CardStack(items: stackDemos, onDismiss: { _ in }, onOpen: { _ in }) { room, isFocused, onOpen in
        MountainCard(messages: room.messages, roomName: room.name,
                     isFavorite: false, priorityScore: 0, isFocused: isFocused,
                     onSend: { _ in }, onOpen: onOpen)
    }
}
#endif
