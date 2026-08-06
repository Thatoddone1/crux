//
//  Composer.swift
//  Crux
//
//  Created by Joshua Kellman on 7/20/26.
//

import SwiftUI


struct Composer: View{

    var onSend: (_ draft: String, _ mentions: [String]) -> Void
    @State var draft = ""
    var members: [RoomModel.Member] = []
    var errorMessage: String? = nil
    var replyingTo: TimelineModel.Message? = nil
    var onReply: ((_ draft: String, _ message: TimelineModel.Message, _ mentions: [String]) -> Void)? = nil
    var onCancelReply: (() -> Void)? = nil
    var focus: FocusState<Bool>.Binding

    //inserted token mapped to user id
    @State private var mentionedUserIds: [String: String] = [:]

    ///shape of the composer
    private var shape: some Shape { .rect(cornerRadius: 20) }

    private var mentionTrigger: (range: Range<String.Index>, query: String)? {
        guard let atRange = draft.range(of: "@", options: .backwards) else { return nil }
        if atRange.lowerBound != draft.startIndex {
            let before = draft[draft.index(before: atRange.lowerBound)]
            guard before.isWhitespace || before.isNewline else { return nil }
        }
        let query = draft[atRange.upperBound...]
        guard !query.contains(where: \.isWhitespace) else { return nil }
        return (atRange.lowerBound..<draft.endIndex, String(query))
    }

    private var mentionSuggestions: [RoomModel.Member] {
        guard let trigger = mentionTrigger else { return [] }
        return members
            .compactMap { member in FuzzyMatch.score(trigger.query, in: member.name).map { ($0, member) } }
            .sorted { $0.0 > $1.0 }
            .prefix(5)
            .map(\.1)
    }

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
            if !mentionSuggestions.isEmpty {
                mentionSuggestionsBar
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

    private var mentionSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(mentionSuggestions) { member in
                    Button { pickMention(member) } label: {
                        HStack(spacing: 4) {
                            AvatarView(avatarUrl: member.avatarUrl, size: 20)
                            Text(member.name)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 4)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }


    private func stillPresent(_ token: String, in text: String) -> Bool {
        text.contains(token)
    }


    private func pickMention(_ member: RoomModel.Member) {
        guard let trigger = mentionTrigger else { return }
        let name = member.name.replacingOccurrences(of: "]", with: "\\]")
        let link = "[\(name)](https://matrix.to/#/\(member.id))"
        draft.replaceSubrange(trigger.range, with: link + " ")
        mentionedUserIds[link] = member.id
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
        // Only mentions whose inserted token survived any later edits still ping.
        let mentions = mentionedUserIds.filter { stillPresent($0.key, in: text) }.map(\.value)
        if let replyingTo, let onReply {
            onReply(text, replyingTo, mentions)
        } else {
            onSend(text, mentions)
        }
        draft = ""
        mentionedUserIds = [:]
    }
}


#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    @FocusState var focus: Bool
        VStack {
            Composer(
                onSend: {(_ draft: String, _ mentions: [String]) in},
                focus: $focus
            )
            .padding()

            Composer(
                onSend: {(_ draft: String, _ mentions: [String]) in},
                errorMessage: "ERROR!",
                focus: $focus
            )
            .padding()

            Composer(
                onSend: {(_ draft: String, _ mentions: [String]) in},
                replyingTo: .sample(sender: "PersonA",
                                    body: "A long message being replied to, which gets truncated."),
                onReply: { _, _, _ in },
                onCancelReply: {},
                focus: $focus
            )
            .padding()
    }
}
#endif
