//
//  Composer.swift
//  Crux
//
//  Created by Joshua Kellman on 7/20/26.
//

import SwiftUI


struct Composer: View{
    
    var onSend: (_ draft: String) -> Void
    @State var draft = ""
    var errorMessage: String? = nil
    
    
    var body: some View {
        VStack(spacing: 4) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.headline)
                    .fontWeight(.heavy)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background()
                    .backgroundStyle(.secondary)
                    .clipShape(.capsule)
            }
            HStack(spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect()
                    .background(Color(.systemGray6), in: .capsule)
                    .onSubmit({onSend(draft); draft = ""})
                Button(action: {onSend(draft); draft = ""}) {
                    Image(systemName: "arrow.up")
                        .font(.title2)
                }
                .buttonStyle(.glassProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}


#Preview(traits: .sizeThatFitsLayout) {
    VStack {
        Composer(
            onSend: {(_ draft: String) in},
        )
        .padding()
        
        Composer(
            onSend: {(_ draft: String) in},
            errorMessage: "ERROR!"
        )
        .padding()
    }
}
