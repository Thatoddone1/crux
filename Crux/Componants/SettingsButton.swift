//
//  ProfileButton.swift
//  Crux
//
//  Created by Joshua Kellman on 7/21/26.
//

import SwiftUI

struct ProfileButton: View {
    
    @State var settingsIsPresented = false
    
    var body: some View {
            Button() {
                settingsIsPresented = true
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.glass)
            .padding()
            .popover(isPresented: $settingsIsPresented) {
                SettingsView()
            }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ProfileButton()
}

//I can't load the entire matrix backend in the preview, so don't enter settings view by clicking it :(
