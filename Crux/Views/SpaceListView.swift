//
//  SpaceListView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/23/26.
//

import SwiftUI

struct SpaceListView: View {
    var body: some View {
        ContentUnavailableView{
            Label("Coming Soon", systemImage: "questionmark")
        } description: {
            Text("Browsing spaces should be avaliable soon. For now, you can see all rooms, including those in spaces, within the room list")
        }
    }
}

#Preview {
    SpaceListView()
}
