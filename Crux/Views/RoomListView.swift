//
//  RoomListView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

enum RoomListRoute: Hashable {
    case newRoom
    case room(id: String)
}

struct RoomListView: View {
    @Environment(MatrixService.self) private var matrix
    @Environment(UserSession.self) var session
    /// The stack lives on the router so a notification tap can push onto it.
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.roomsPath) {
            List(session.roomList.summaries) { room in
                Group {
                    if room.isInvite {
                        RoomInviteRow(room: room)
                    } else {
                        NavigationLink(value: RoomListRoute.room(id: room.id)) {
                            RoomRow(room: room)
                        }
                        .roomContextMenu(room)
                    }
                }
                .leaveSwipe(session, roomId: room.id, decline: room.isInvite)
            }
            .listStyle(.plain)
            .navigationTitle("Rooms")
            .overlay {
                if session.roomList.summaries.isEmpty {
                    ContentUnavailableView("No Rooms Yet",
                                           systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Go and join some rooms!"))
                }
            }
            .overlay(
                NavigationLink(value: RoomListRoute.newRoom) {
                    Image(systemName: "plus")
                }
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .buttonBorderShape(.circle)
                    .padding(),
                alignment: .bottomTrailing
            )
            .navigationDestination(for: RoomListRoute.self) { route in
                switch route {
                case .newRoom:
                    NewRoomView(path: $router.roomsPath)
                case .room(let id):
                    RoomView(roomId: id)
                }
                
            }
        }
        .overlay (
            SettingsButton(),
            alignment: .topTrailing
        )
    }
}

/// A joined room: avatar, name, the last thing said in it, and whatever chips apply.
private struct RoomRow: View {
    let room: RoomModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(avatarUrl: room.avatarUrl, size: 52, unreadCount: room.unreadMessages)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(room.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let latest = room.latestMessage {
                        Text(latest.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let latest = room.latestMessage {
                    Text(preview(latest))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .opacity(latest.isPending ? 0.5 : 1)
                }
                RoomChips(room)
            }
        }
        .padding(.vertical, 6)
    }

    
    private func preview(_ latest: RoomModel.LatestMessage) -> AttributedString {
        let body = AttributedString(latest.body)
        guard !(room.isOneToOne && !latest.isOwn) else { return body }
        var name = AttributedString(latest.isOwn ? "You: " : "\(latest.sender): ")
        name.foregroundColor = .primary
        return name + body
    }
}

/// An invited-but-not-joined room: shown dimmed with a Join button rather than
/// a navigation link, since the room can't be opened until the invite's accepted.
private struct RoomInviteRow: View {
    let room: RoomModel
    @State private var isJoining = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: room.avatarUrl, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).font(.headline).lineLimit(1)
                Text("Invited you").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if isJoining {
                ProgressView()
            } else {
                Button("Join") { join() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
        .opacity(isJoining ? 1 : 0.5)
    }

    private func join() {
        isJoining = true
        Task {
            try? await room.join()
            isJoining = false
        }
    }
}
