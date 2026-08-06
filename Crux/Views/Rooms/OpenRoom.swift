//
//  OpenRoom.swift
//  Crux
//

import SwiftUI

extension View {
    /// Binds a view's lifetime to a room's shared `RoomModel` and **opens its
    /// timeline** — for views that show messages.
    ///
    /// The pairing matters both ways: the model is freed when nothing holds it,
    /// and a timeline nothing is showing is what the store is allowed to close.
    /// Rooms in the list deliberately don't go through here, which is what keeps
    /// a few hundred listed rooms from opening a few hundred timelines.
    func openRoom(_ session: UserSession, roomId: String, into model: Binding<RoomModel?>) -> some View {
        modifier(OpenRoomModifier(session: session, roomId: roomId, model: model))
    }
}

private struct OpenRoomModifier: ViewModifier {
    let session: UserSession
    let roomId: String
    @Binding var model: RoomModel?

    /// The room actually being held, which lags `roomId` by a frame when the view
    /// is reused for a different room — releasing the wrong one would unbalance
    /// the session's count.
    @State private var held: String?

    func body(content: Content) -> some View {
        content
            // `onAppear`/`onDisappear` are the symmetric pair, so the hold can't
            // be dropped without being taken again. `task` only re-runs `hold`
            // for the case it uniquely covers: `roomId` changing while on screen.
            .onAppear(perform: hold)
            .onDisappear(perform: release)
            .task(id: roomId) {
                hold()
                await session.rooms.openTimeline(roomId)
            }
    }

    private func hold() {
        guard held != roomId else { return }
        release()
        model = try? session.roomModel(for: roomId)
        held = model == nil ? nil : roomId
    }

    private func release() {
        guard let held else { return }
        session.rooms.closeTimeline(held)
        session.releaseRoom(held)
        self.held = nil
    }
}
