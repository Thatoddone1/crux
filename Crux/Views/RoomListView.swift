//
//  RoomListView.swift
//  Crux
//

import SwiftUI

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
                NavigationLink(summary.name, value: RoomListRoute.room(id: summary.id))
            }
            .navigationTitle("Rooms")
            .overlay {
                    if session.roomList.summaries.isEmpty {
                        ContentUnavailableView("No Rooms Yet",
                                               systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Rooms appear here as the first sync completes."))
                    }
                }
            .overlay(
                NavigationLink(value: RoomListRoute.newRoom) {
                   Image(systemName: "plus")
                }
                    .padding()
                    .buttonStyle(.glass),
                alignment: .topTrailing
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
        .overlay(
            SettingsButton(),
            alignment: .topTrailing
        )
        }
    }
