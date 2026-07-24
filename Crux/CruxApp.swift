//
//  CruxApp.swift
//  Crux
//
//  Created by Joshua Kellman on 7/7/26.
//

import SwiftUI

@main
struct CruxApp: App {
    @State private var matrix = MatrixService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(matrix)
        }
    }
}
