//
//  SettingsView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/20/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(MatrixService.self) var matrix
    
    
    var body: some View {
        NavigationStack {
            List{
                Section() {
                    Button("Log out", role: .destructive) {
                        Task { await matrix.logOut() }
                    }
                }
                Section("About") {
                    Link("Reach out for support", destination: URL(string: "mailto:hello@joshuarocks.me")!)
                    Text("Created by [Joshua K](https://joshuarocks.me) with ❤️")
                }
            }
            .navigationTitle("Settings")
        }

    }
}

