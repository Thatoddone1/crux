//
//  ContentView.swift
//  Crux
//

import SwiftUI

struct ContentView: View {
    @Environment(MatrixService.self) private var matrix
    @State var settingsIsPresented = false

    var body: some View {
        Group {
            switch matrix.state {
            case .restoring:
                ProgressView()
            case .signedOut:
                SignedOutView()
            case .signedIn(let session):
                TabView {
                    Tab("Mountain", systemImage: "mountain.2") {
                        MountainView()
                    }
                    Tab("Rooms", systemImage: "house.fill") {
                        RoomListView()
                    }
                    Tab("Spaces", systemImage: "person.3.fill") {
                        SpaceListView()
                    }
                    //Tab(role: .search) {
                        //SearchView()
                    //}
                }
                .environment(session)
            }
        }
        .task { await matrix.restoreSession() }
    }
}

///what to show when signed out
private struct SignedOutView: View {
    @State private var showOnboarding = true

    var body: some View {
        LoginView()
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView()
            }
    }
}
