//
//  MountainView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/21/26.
//

import SwiftUI

struct MountainView: View {
    @Environment(UserSession.self) var session

    var body: some View {
        let pile = session.roomList.summaries.filter(\.hasUnread)

        if pile.isEmpty {
            ContentUnavailableView("All caught up",
                                   systemImage: "checkmark.circle",
                                   description: Text("Unread rooms stack up here."))
            .overlay(
                SettingsButton(),
                alignment: .topTrailing
            )
        } else {
            CardDeck(items: pile) { summary in
                MountainCardListView(summary: summary)
            }
            .overlay(
                SettingsButton(),
                alignment: .topTrailing
            )
        }
    }
}
