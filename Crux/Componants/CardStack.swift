//
//  CardStack.swift
//  Crux
//

import SwiftUI


struct CardStack<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// Swipe the focused card right to dismiss it; nil disables swiping.
    var onDismiss: ((Item) -> Void)? = nil
    /// Open the focused card (e.g. into the full room); nil disables it.
    var onOpen: ((Item) -> Void)? = nil
    @ViewBuilder let card: (_ item: Item, _ isFocused: Bool, _ onOpen: (() -> Void)?) -> Card

    ///which card is focused?
    @State private var focusedID: Item.ID?
    @State private var dragY: CGFloat = 0
    @State private var dragX: CGFloat = 0
    /// Which axis this drag locked onto, decided from its first movement.
    @State private var axis: Axis?
    @State private var dismissingID: Item.ID?
    /// True while the dismiss drag is past threshold (drives one haptic).
    @State private var armedToDismiss = false
    ///heights of cards (to help determine position)
    @State private var heights: [Item.ID: CGFloat] = [:]
    @State private var dragCount = 0

    private var focusedIndex: Int {
        items.firstIndex { $0.id == focusedID } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            // so keyboard shifts everything correctly
            let available = geo.size.height - Stack.topInset
            let lift = max(0, height(at: focusedIndex) - available)
            GlassEffectContainer {
                ZStack(alignment: .top) {
                    ForEach(window(), id: \.element.id) { index, item in
                        cardSlot(item, distance: index - focusedIndex)
                    }
                }
                .padding(.top, Stack.topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -lift)
                .animation(.easeOut(duration: 0.25), value: lift)
                .contentShape(.rect)
                .gesture(pagingGesture())
                .environment(\.deckDragCount, dragCount)
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

    private func cardSlot(_ item: Item, distance: Int) -> some View {
        let isFocused = distance == 0
        let dismissing = item.id == dismissingID
        let dx = dismissing ? Stack.flyOff : (isFocused && axis == .horizontal ? max(0, dragX) : 0)
        // A dismissing card holds the focused slot as it flies right, so it. clears out while the next card rises into its place.
        let dy = dismissing ? 0 : restOffset(for: distance) + (axis == .vertical ? dragY : 0)
        return ZStack(alignment: .leading) {
            if isFocused && dx > 1 {
                Label("Read", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .padding(.leading, 32)
                    .opacity(min(Double(dx / Stack.dismissDistance), 1))
            }
            card(item, isFocused, isFocused ? { onOpen?(item) } : nil)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    heights[item.id] = height
                }
                .offset(x: dx)
                .geometryGroup()   // isolate the swipe transform from the glass
        }
        .overlay(alignment: .trailing) {
            if isFocused, onDismiss != nil, !dismissing, dx <= 1 {
                Image(systemName: "chevron.compact.right")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.25))
                    .padding(.trailing, 22)
                    .allowsHitTesting(false)
            }
        }
        .opacity(isFocused ? 1 : Stack.neighbourOpacity)
        .offset(y: dy)
        .zIndex(dismissing ? 2 : (isFocused ? 1 : 0))
    }

    ///relative position to the focused card
    private func restOffset(for distance: Int) -> CGFloat {
        guard distance != 0 else { return 0 }
        var y: CGFloat = 0
        if distance > 0 {
            for i in 0..<distance {
                y += height(at: focusedIndex + i) + Stack.cardGap
            }
        } else {
            for i in 1...(-distance) {
                y -= height(at: focusedIndex - i) + Stack.cardGap
            }
        }
        return y
    }

    /// Falls back to an estimate for the one frame between a card mounting and its `onGeometryChange` reporting a real height.
    private func height(at index: Int) -> CGFloat {
        guard let id = items[safe: index]?.id else { return Stack.fallbackHeight }
        return heights[id] ?? Stack.fallbackHeight
    }

    private func pagingGesture() -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if axis == nil {
                    axis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                    dragCount += 1
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

    /// Flies the card off to the right and hands removal to the caller. Focus slides to a neighbour in the same motion; the flown card is only dropped once the caller's list no longer contains it, so nothing pops back.
    private func dismiss(_ item: Item) {
        let nextID = items[safe: focusedIndex + 1]?.id ?? items[safe: focusedIndex - 1]?.id
        withAnimation(Stack.snap) {
            dismissingID = item.id       // flies off to the right
            dragX = 0
            if let nextID { focusedID = nextID }   // next card rises to centre meanwhile
        } completion: {
            onDismiss?(item)
        }
    }

    ///keep focus on a real card
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

private struct DeckDragCountKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Bumped when a deck drag starts. Cards watch it to drop keyboard focus —
    /// `CardStack` is generic over its content, so it can't do that itself.
    var deckDragCount: Int {
        get { self[DeckDragCountKey.self] }
        set { self[DeckDragCountKey.self] = newValue }
    }
}

///tuning for the stack
private nonisolated enum Stack {
   
    static let cardGap: CGFloat = 8            // this card's bottom -> next card's top
    static let topInset: CGFloat = 12          // clears the section bar above the deck
    static let fallbackHeight: CGFloat = 260   // estimate until a card is measured
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
    @FocusState var focus: Bool
    
    CardStack(items: stackDemos, onDismiss: { _ in }, onOpen: { _ in }) { room, isFocused, onOpen in
        VStack(alignment: .leading, spacing: 8) {
            MountainCardHeader(roomName: room.name, avatarUrl: nil, unreadCount: 0, isFavorite: false,
                               isDirect: true, isLowPriority: false, notification: nil, isMentioned: false,
                               score: 0, breakdown: nil, isFocused: isFocused, onOpen: onOpen)
            MountainCard(messages: room.messages, isFocused: isFocused, onSend: { _ in },
                         composerFocus: $focus)
        }
    }
}

#endif
