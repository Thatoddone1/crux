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
    
    @State private var path = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $path) {
            List(session.roomList.summaries) { summary in
                Group {
                    if summary.isInvite {
                        RoomInviteRow(summary: summary)
                    } else {
                        NavigationLink(summary.name, value: RoomListRoute.room(id: summary.id))
                    }
                }
                .leaveSwipe(session, roomId: summary.id, decline: summary.isInvite)
            }
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
                    NewRoomView(path: $path)
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

/// An invited-but-not-joined room: shown dimmed with a Join button rather than
/// a navigation link, since the room can't be opened until the invite's accepted.
private struct RoomInviteRow: View {
    let summary: RoomListModel.Summary
    @State private var isJoining = false
    
    var body: some View {
        HStack {
            Text(summary.name)
            Spacer()
            if isJoining {
                ProgressView()
            } else {
                Button("Join") { join() }
                    .buttonStyle(.bordered)
            }
        }
        .opacity(isJoining ? 1 : 0.5)
    }
    
    private func join() {
        isJoining = true
        Task {
            try? await summary.room.join()
            isJoining = false
        }
    }
}
