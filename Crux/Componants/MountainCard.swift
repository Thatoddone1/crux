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
    let onSend: (_ draft: String) -> Void

    var body: some View {
        VStack {
            HStack {
                Text(roomName)
                    .font(.headline)
                    .fontWeight(.heavy)
                Spacer()
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
#Preview {
    MountainCard(
        messages: [
            .sample(sender: "Person A", body: "This is a wonderful message"),
            .sample(sender: "Person A", body: "Message 2"),
        ],
        roomName: "Wonderful Group!",
        onSend: { draft in print("sent: \(draft)") }
    )
}
#endif
