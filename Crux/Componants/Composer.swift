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
    var focus: FocusState<Bool>.Binding

    ///shape of the composer
    private var shape: some Shape { .rect(cornerRadius: 20) }

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
                    .lineLimit(1...5)
                    .focused(focus)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(in: shape)
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
    @FocusState var focus: Bool
        VStack {
            Composer(
                onSend: {(_ draft: String) in},
                focus: $focus
            )
            .padding()

            Composer(
                onSend: {(_ draft: String) in},
                errorMessage: "ERROR!",
                focus: $focus
            )
            .padding()
    }
}
