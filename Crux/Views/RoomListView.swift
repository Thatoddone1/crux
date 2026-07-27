//
//  RoomListView.swift
//  Crux
//

import SwiftUI

struct RoomListView: View {
    @Environment(MatrixService.self) private var matrix
    
    @Environment(UserSession.self) var session
    
    var body: some View {
        NavigationStack {
            List(session.roomList.summaries) { summary in
                NavigationLink(summary.name) {
                    RoomView(summary: summary)
                }
            }
            .navigationTitle("Rooms")
            .overlay {
                    if session.roomList.summaries.isEmpty {
                        ContentUnavailableView("No Rooms Yet",
                                               systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Rooms appear here as the first sync completes."))
                    }
                }
            }
        .overlay(
            SettingsButton(),
            alignment: .topTrailing
        )

        }
    }
