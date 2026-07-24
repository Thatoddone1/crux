//
//  SearchView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/23/26.
//

import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""
    var body: some View {
        NavigationStack{
            List{
                ContentUnavailableView{
                    Label("Coming Soon", systemImage: "questionmark")
                } description: {
                    Text("Search is stil being worked on, and will be here soon! Reach out if you need support")
                }
                Text("Demo Text: \(searchText)")
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search anything")
        }
    }
}

#Preview {
    SearchView(
        searchText: ""
    )
}
