//
//  MountainCard.swift
//  Crux
//
//  Created by Joshua Kellman on 7/22/26.
//

import SwiftUI

struct MountainCard: View {

    let messages: [TimelineModel.Message]
    let roomName: String
    let isFavorite: Bool
    let isDirect: Bool
    let priorityScore: Int
    let onSend: (_ draft: String) -> Void

    var body: some View {
        VStack {
            HStack {
                Text(roomName)
                    .font(.headline)
                    .fontWeight(.heavy)
                Spacer()
                Text(priorityScore.description)
                    .fontWeight(.heavy)
                    .padding(.trailing, 0)
                Text("/100")
                    .fontWeight(.light)
                    .padding(.leading, 0)
            }
            ForEach(messages) { message in
                MessageBubble(message: message)
            }
            Composer(onSend: onSend)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding()
    }
}
#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    MountainCard(
        messages: [
            .sample(sender: "Person A", body: "This is a wonderful message"),
            .sample(sender: "Person A", body: "Message 2"),
        ],
        roomName: "Wonderful Group!",
        isFavorite: true,
        isDirect: false,
        priorityScore: 64,
        onSend: { draft in print("sent: \(draft)") }
    )
}
#endif
