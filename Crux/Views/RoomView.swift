//
//  RoomView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

struct RoomView: View {
    let roomId: String
    @Environment(UserSession.self) private var session

    @State private var name: String?
    @State private var room: Room?
    @State private var isDirect = false
    @State private var model: TimelineModel?
    @State private var errorMessage: String?
    @State private var profileTarget: ProfileTarget?
    @State private var showMemberMenu = false
    @State private var members: [RoomMember] = []
    @State private var reportTarget: TimelineModel.Message?

    private struct ProfileTarget: Identifiable {
        let id: String
    }

    var body: some View {
        Group {
            if let model {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.entries) { entry in
                            row(for: entry)
                        }
                    }
                    .padding(.horizontal)
                }
                .defaultScrollAnchor(.bottom)
                .onLongPressGesture(perform: openTitleAction)
                .safeAreaInset(edge: .bottom) { Composer(
                    onSend: send,
                    errorMessage: errorMessage
                ) }
            } else if let errorMessage {
                ContentUnavailableView("Couldn't Open Room",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: openTitleAction) {
                    HStack(spacing: 4) {
                        Text(name ?? "")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
        }
        .task {
            do {
                let room = try session.room(id: roomId)
                self.room = room
                name = room.displayName() ?? room.id()
                isDirect = await room.isDirect()
                let model = TimelineModel(room: room)
                self.model = model
                try await model.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $profileTarget) { target in
            profileSheet(for: target)
        }
        .sheet(isPresented: $showMemberMenu) {
            memberMenu
        }
        .sheet(item: $reportTarget) { message in
            reportSheet(for: message)
        }
    }

    @ViewBuilder
    private func reportSheet(for message: TimelineModel.Message) -> some View {
        if let model {
            ReportMessageView(message: message, model: model)
        }
    }

    /// Tapping the title (or holding anywhere in the room) opens the other
    /// participant's profile directly for a DM, or a simple member picker
    /// for group rooms.
    private func openTitleAction() {
        guard let room else { return }
        if isDirect, let heroId = room.heroes().first?.userId {
            profileTarget = ProfileTarget(id: heroId)
        } else {
            showMemberMenu = true
        }
    }

    @ViewBuilder
    private func profileSheet(for target: ProfileTarget) -> some View {
        UserProfileView(userId: target.id, session: session, room: room)
    }

    @ViewBuilder
    private var memberMenu: some View {
        NavigationStack {
            List(members, id: \.userId) { member in
                Button {
                    showMemberMenu = false
                    profileTarget = ProfileTarget(id: member.userId)
                } label: {
                    Text(member.displayName ?? member.userId)
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showMemberMenu = false }
                }
            }
            .task {
                guard members.isEmpty, let room else { return }
                if let iterator = try? await room.members() {
                    members = iterator.nextChunk(chunkSize: 500) ?? []
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: TimelineModel.Entry) -> some View {
        switch entry {
        case .message(let message):
            MessageBubble(message: message,
                          onReport: { reportTarget = message },
                          onViewProfile: { profileTarget = ProfileTarget(id: message.senderId) })
        case .dayDivider(_, let date):
            Text(date, style: .date)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func send(_ draft: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let model else { return }
        errorMessage = nil

        Task {
            do {
                try await model.send(text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
