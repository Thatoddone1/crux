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
    var replyingTo: TimelineModel.Message? = nil
    var onReply: ((_ draft: String, _ message: TimelineModel.Message) -> Void)? = nil
    var onCancelReply: (() -> Void)? = nil
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
            if let replyingTo {
                replyBanner(for: replyingTo)
            }
            HStack(spacing: 8) {
                TextField(replyingTo == nil ? "Message" : "Reply", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(focus)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(in: shape)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: replyingTo == nil ? "arrow.up" : "arrowshape.turn.up.left.fill")
                        .font(.title2)
                }
                .buttonStyle(.glassProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .animation(.snappy(duration: 0.22), value: replyingTo?.id)
    }

    private func replyBanner(for message: TimelineModel.Message) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to \(message.sender)")
                    .font(.caption.weight(.semibold))
                Text(message.body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Cancel reply", systemImage: "xmark") { onCancelReply?() }
                .labelStyle(.iconOnly)
                .font(.caption.weight(.bold))
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: shape)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let replyingTo, let onReply {
            onReply(text, replyingTo)
        } else {
            onSend(text)
        }
        draft = ""
    }
}


#if DEBUG
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

            Composer(
                onSend: {(_ draft: String) in},
                replyingTo: .sample(sender: "PersonA",
                                    body: "A long message being replied to, which gets truncated."),
                onReply: { _, _ in },
                onCancelReply: {},
                focus: $focus
            )
            .padding()
    }
}
#endif
