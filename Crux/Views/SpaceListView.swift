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
                                .leaveSwipe(session, roomId: invite.id, decline: true)
                        }
                    }
                }
                Section {
                    ForEach(session.spaces.nodes) { node in
                        NavigationLink(value: SpaceRoute.space(id: node.id)) {
                            SpaceRoomRow(spaceRoom: node.spaceRoom)
                        }
                        .leaveSwipe(session, roomId: node.id)
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
        .overlay (
            SettingsButton(),
            alignment: .topTrailing
        )	
    }
}

/// The page for a single top-level space: its own children, expandable inline
/// from here on down (SpaceNodeRow), matching the tree's natural recursion.
struct SpaceDetailView: View {
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
    @Environment(UserSession.self) private var session
    let node: SpaceNode
    @State private var isExpanded = false

    private var isJoined: Bool { node.spaceRoom.state == .joined }

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
            .leaveSwipeIf(isJoined, session: session, roomId: node.id)
        } else if isJoined {
            NavigationLink(value: SpaceRoute.room(id: node.id)) {
                SpaceRoomRow(spaceRoom: node.spaceRoom)
            }
            .leaveSwipe(session, roomId: node.id)
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
        HStack(spacing: 12) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                Text(spaceRoom.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isJoining {
                ProgressView()
            } else if !isJoined {
                Button("Join") { join() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
        .opacity(isJoined || isJoining ? 1 : 0.5)
        .task {
            guard let url = spaceRoom.avatarUrl else { return }
            avatar = await MediaLoader.shared.avatar(for: url, client: session.client)
        }
    }

    /// The topic if there is one; otherwise the counts, which are the only other
    /// thing `SpaceRoom` knows without joining.
    private var subtitle: String {
        if let topic = spaceRoom.topic, !topic.isEmpty { return topic }
        let members = "\(spaceRoom.numJoinedMembers) \(spaceRoom.numJoinedMembers == 1 ? "member" : "members")"
        guard spaceRoom.roomType == .space else { return members }
        return "\(spaceRoom.childrenCount) rooms · \(members)"
    }

    @ViewBuilder private var avatarView: some View {
        if let avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(.circle)
        } else {
            Image(systemName: spaceRoom.roomType == .space ? "square.stack.3d.up.fill" : "bubble.left.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
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
