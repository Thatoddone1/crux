//
//  ReplySwipe.swift
//  Crux
//

import SwiftUI

extension View {
    @ViewBuilder
    func replySwipe(if enabled: Bool, perform action: (() -> Void)?) -> some View {
        if enabled, let action {
            modifier(ReplySwipe(action: action))
        } else {
            self
        }
    }
}

private struct ReplySwipe: ViewModifier {
    let action: () -> Void

    @State private var offset: CGFloat = 0
    /// True once pulled far enough that releasing fires the reply.
    @State private var isArmed = false

    /// Rightward travel (pt) needed to arm.
    private let armDistance: CGFloat = 60
    /// Travel before the arrow starts fading in — it sits under the sender name until then.
    private let arrowAppearsAt: CGFloat = 20

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.callout)
                .foregroundStyle(isArmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .scaleEffect(isArmed ? 1.2 : 0.85)
                .opacity(progress)
                .animation(.snappy(duration: 0.2), value: isArmed)
                .allowsHitTesting(false)

            content.offset(x: offset)
        }
        .contentShape(.rect)
        // The scroll view can steal the drag, so onEnded isn't guaranteed to land.
        .onDisappear { reset() }
        .simultaneousGesture(drag)
        .sensoryFeedback(trigger: isArmed) { _, armed in armed ? .impact(flexibility: .rigid) : nil }
    }

    private var progress: Double {
        let span = armDistance - arrowAppearsAt
        return min(max((offset - arrowAppearsAt) / span, 0), 1)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                // Leave vertical drags to the scroll view.
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    if offset != 0 { reset() }
                    return
                }
                let x = max(0, value.translation.width)
                // Resist past the arm point so it feels like it has caught.
                offset = x > armDistance ? armDistance + (x - armDistance) * 0.25 : x
                isArmed = x >= armDistance
            }
            .onEnded { _ in
                if isArmed { action() }
                reset()
            }
    }

    private func reset() {
        isArmed = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
    }
}
