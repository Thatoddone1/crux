//
//  SpaceListView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK


private enum SpaceRoute: Hashable {
    case space(id: String)
    case room(id: String)
}

struct SpaceListView: View {
    @Environment(UserSession.self) var session

    var body: some View {
        NavigationStack {
            List {
                if !session.spaces.invites.isEmpty {
                    Section("Invites") {
                        ForEach(session.spaces.invites) { invite in
                            SpaceInviteRow(invite: invite)
                        }
                    }
                }
                Section {
                    ForEach(session.spaces.nodes) { node in
                        NavigationLink(value: SpaceRoute.space(id: node.id)) {
                            SpaceRoomRow(spaceRoom: node.spaceRoom)
                        }
                    }
                }
            }
            .navigationTitle("Spaces")
            .overlay {
                if session.spaces.nodes.isEmpty && session.spaces.invites.isEmpty {
                    ContentUnavailableView("No Spaces Yet", systemImage: "square.stack.3d.up",
                                           description: Text("Spaces you've joined appear here."))
                }
            }
            .navigationDestination(for: SpaceRoute.self) { route in
                switch route {
                case .space(let id):
                    if let node = session.spaces.nodes.first(where: { $0.id == id }) {
                        SpaceDetailView(node: node)
                    }
                case .room(let id):
                    RoomView(roomId: id)
                }
            }
        }
    }
}

/// The page for a single top-level space: its own children, expandable inline
/// from here on down (SpaceNodeRow), matching the tree's natural recursion.
private struct SpaceDetailView: View {
    let node: SpaceNode

    var body: some View {
        List(node.children.sortedJoinedFirst) { child in
            SpaceNodeRow(node: child)
        }
        .navigationTitle(node.spaceRoom.displayName)
        .task { try? await node.expand() }
    }
}

/// One row below the top level — a nested space (expands in place) or a room
/// (opens if joined, otherwise just offers to join).
private struct SpaceNodeRow: View {
    let node: SpaceNode
    @State private var isExpanded = false

    var body: some View {
        if node.isSpace {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children.sortedJoinedFirst) { child in
                    SpaceNodeRow(node: child)
                }
            } label: {
                SpaceRoomRow(spaceRoom: node.spaceRoom)
            }
            .task(id: isExpanded) {
                if isExpanded { try? await node.expand() }
            }
        } else if node.spaceRoom.state == .joined {
            NavigationLink(value: SpaceRoute.room(id: node.id)) {
                SpaceRoomRow(spaceRoom: node.spaceRoom)
            }
        } else {
            SpaceRoomRow(spaceRoom: node.spaceRoom)
        }
    }
}

private extension [SpaceNode] {
    /// Rooms/spaces you're already in float to the top; stable otherwise since
    /// there's no meaningful server-side ordering to begin with.
    var sortedJoinedFirst: [SpaceNode] {
        sorted { $0.isJoined && !$1.isJoined }
    }
}

/// An invited-but-not-joined space: dimmed row with a Join button, no navigation
/// (you can't browse the space until you're in it).
private struct SpaceInviteRow: View {
    @Environment(UserSession.self) private var session
    let invite: SpaceListModel.Invite
    @State private var avatar: UIImage?
    @State private var isJoining = false

    var body: some View {
        HStack {
            avatarView
            Text(invite.name)
            Spacer()
            if isJoining {
                ProgressView()
            } else {
                Button("Join") { join() }
                    .buttonStyle(.bordered)
            }
        }
        .opacity(isJoining ? 1 : 0.5)
        .task {
            guard let url = invite.avatarUrl else { return }
            avatar = await MediaLoader.shared.avatar(for: url, client: session.client)
        }
    }

    @ViewBuilder private var avatarView: some View {
        if let avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(.circle)
        } else {
            Image(systemName: "square.stack.3d.up.fill")
                .frame(width: 28, height: 28)
        }
    }

    private func join() {
        isJoining = true
        Task {
            try? await invite.room.join()
            isJoining = false
        }
    }
}

/// Icon + name for a space or room, dimmed with a Join button when the
/// signed-in user isn't a member of it yet.
private struct SpaceRoomRow: View {
    @Environment(UserSession.self) private var session
    let spaceRoom: SpaceRoom
    @State private var avatar: UIImage?
    @State private var isJoining = false

    private var isJoined: Bool { spaceRoom.state == .joined }

    var body: some View {
        HStack {
            avatarView
            Text(spaceRoom.displayName)
            Spacer()
            if isJoining {
                ProgressView()
            } else if !isJoined {
                Button("Join") { join() }
                    .buttonStyle(.bordered)
            }
        }
        .opacity(isJoined || isJoining ? 1 : 0.5)
        .task {
            guard let url = spaceRoom.avatarUrl else { return }
            avatar = await MediaLoader.shared.avatar(for: url, client: session.client)
        }
    }

    @ViewBuilder private var avatarView: some View {
        if let avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(.circle)
        } else {
            Image(systemName: spaceRoom.roomType == .space ? "square.stack.3d.up.fill" : "bubble.left.fill")
                .frame(width: 28, height: 28)
        }
    }

    private func join() {
        isJoining = true
        Task {
            _ = try? await session.client.joinRoomById(roomId: spaceRoom.roomId)
            isJoining = false
        }
    }
}

#Preview {
    SpaceListView()
}
