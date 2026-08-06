//
//  ContentView.swift
//  Crux
//

import SwiftUI

struct ContentView: View {
    @Environment(MatrixService.self) private var matrix
    @Environment(AppRouter.self) private var router
    @Environment(PushModel.self) private var push
    @State var settingsIsPresented = false

    var body: some View {
        @Bindable var router = router

        Group {
            switch matrix.state {
            case .restoring:
                ProgressView()
            case .signedOut:
                SignedOutView()
            case .signedIn(let session):
                TabView(selection: $router.selectedTab) {
                    Tab("Mountain", systemImage: "mountain.2", value: AppRouter.Tab.mountain) {
                        MountainView()
                    }
                    Tab("Rooms", systemImage: "house.fill", value: AppRouter.Tab.rooms) {
                        RoomListView()
                    }
                    Tab("Spaces", systemImage: "person.3.fill", value: AppRouter.Tab.spaces) {
                        SpaceListView()
                    }
                    Tab(value: AppRouter.Tab.search, role: .search) {
                        SearchView()
                    }
                }
                .environment(session)
                // A tapped notification waits here until there's a session to open it with.
                .task(id: router.pendingRoomId) { router.openPendingRoom() }
                .task { await push.requestAuthorizationIfNeeded() }
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
