//
//  SettingsButton.swift
//  Crux
//
//  Created by Joshua Kellman on 7/21/26.
//

import SwiftUI

struct SettingsButton: View {
    @Environment(UserSession.self) var session
    @State var profilePicture: UIImage? = nil
    @State var settingsIsPresented = false
    
    var body: some View {
            Button() {
                settingsIsPresented = true
            } label: {
                if let picture = profilePicture {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(.circle)
                } else {
                    Image(systemName: "gear")
                        .padding()
                }
            }
            .task {
                if let url = session.avatarUrl{
                   profilePicture = await MediaLoader.shared.avatar(for: url, client: session.client)
                }
            }
            .padding()
            .popover(isPresented: $settingsIsPresented) {
                SettingsView()
            }
    }
}
