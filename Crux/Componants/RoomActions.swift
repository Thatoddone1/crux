//
//  RoomActions.swift
//  Crux
//

import SwiftUI

extension View {
    ///context menu for a room (with various actions)
    func roomContextMenu(_ room: RoomModel) -> some View {
        contextMenu {
            Button(room.isFavorite ? "Remove Favorite" : "Favorite",
                   systemImage: room.isFavorite ? "star.slash" : "star") {
                Task { await room.setFavorite(!room.isFavorite) }
            }
            Button(room.isMuted ? "Unmute" : "Mute",
                   systemImage: room.isMuted ? "bell" : "bell.slash") {
                Task { await room.setMuted(!room.isMuted) }
            }
            // A room can't be both favorite and low priority; `RoomModel` clears
            // the other end, so these two never need to agree with each other here.
            Button(room.isLowPriority ? "Normal Priority" : "Low Priority",
                   systemImage: room.isLowPriority ? "arrow.up.circle" : "arrow.down.circle") {
                Task { await room.setLowPriority(!room.isLowPriority) }
            }

            Divider()

            if room.hasUnread {
                Button("Mark as Read", systemImage: "envelope.open") {
                    Task { await room.markRead() }
                }
            } else {
                Button("Mark as Unread", systemImage: "envelope.badge") {
                    Task { await room.markUnread() }
                }
            }
        }
    }
}
