//
//  LeaveSwipe.swift
//  Crux
//

import SwiftUI

extension View {
    /// Trailing swipe action to leave a room/space (or decline an invite).
    func leaveSwipe(_ session: UserSession, roomId: String, decline: Bool = false) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(decline ? "Decline" : "Leave", role: .destructive) {
                Task { await session.leave(roomId) }
            }
        }
    }

    /// Same, but only when `joined` — you can't leave a space you're not in.
    @ViewBuilder
    func leaveSwipeIf(_ joined: Bool, session: UserSession, roomId: String) -> some View {
        if joined { leaveSwipe(session, roomId: roomId) } else { self }
    }
}
