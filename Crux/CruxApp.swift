//
//  CruxApp.swift
//  Crux
//
//  Created by Joshua Kellman on 7/7/26.
//

import SwiftUI

@main
struct CruxApp: App {
    // The delegate owns the session and the router: notifications can arrive
    // before there's a scene to hold them.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(delegate.matrix)
                .environment(delegate.push)
                .environment(delegate.router)
        }
    }
}
