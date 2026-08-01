//
//  RoomView.swift
//  Crux
//

import SwiftUI

struct RoomView: View {
    let roomId: String
    @Environment(UserSession.self) private var session

    @State private var details: RoomDetailsModel? //all details about the room
    @State private var errorMessage: String?
    @State private var profileTarget: ProfileTarget?
    @State private var showMemberMenu = false
    @State private var reportTarget: TimelineModel.Message?
    @State private var editTarget: TimelineModel.Message?
    @State private var editContent: String = ""
    @State private var showEdit: Bool = false
    
    
    private struct ProfileTarget: Identifiable {
        let id: String
    }

    var body: some View {
        Group {
            if let details {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(details.timeline.entries) { entry in
                            row(for: entry)
                        }
                    }
                    .padding(.horizontal)
                }
                .defaultScrollAnchor(.bottom)
                .onLongPressGesture(perform: openTitleAction)
                .safeAreaInset(edge: .bottom) {
                    if (details.canSendMessage()) {
                        Composer(
                            onSend: send,
                            errorMessage: errorMessage
                        )
                    } else {
                        Text("You don't have permission to send here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
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
                        Text(details?.name ?? "")
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
                let details = try RoomDetailsModel(session: session, roomId: roomId)
                self.details = details
                await details.start()
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
        .alert("Edit Message", isPresented: $showEdit) {
            TextField("Edited message", text: $editContent)
            
            if let editTarget {
                Button("Save") {
                    Task {try await details?.timeline.edit(editTarget, to: editContent)}
                }
            }
            
            Button("Cancel", role: .cancel) {
                editTarget = nil
                showEdit = false
                editContent = ""
            }
        } message: {
            Text("Edit the contents of this message")
        }
    }

    @ViewBuilder
    private func reportSheet(for message: TimelineModel.Message) -> some View {
        if let details {
            ReportMessageView(message: message, model: details.timeline)
        }
    }

    /// Tapping the title (or holding anywhere in the room) opens the other
    /// participant's profile directly for a DM, or a simple member picker
    /// for group rooms.
    private func openTitleAction() {
        guard let details else { return }
        if details.isDirect, let heroId = details.directHeroId {
            profileTarget = ProfileTarget(id: heroId)
        } else {
            showMemberMenu = true
        }
    }

    @ViewBuilder
    private func profileSheet(for target: ProfileTarget) -> some View {
        UserProfileView(userId: target.id, session: session, room: details?.room)
    }

    @ViewBuilder
    private var memberMenu: some View {
        NavigationStack {
            List(details?.members ?? []) { member in
                Button {
                    showMemberMenu = false
                    profileTarget = ProfileTarget(id: member.id)
                } label: {
                    Text(member.name)
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showMemberMenu = false }
                }
            }
            .task { await details?.loadMembers() }
        }
    }

    @ViewBuilder
    private func row(for entry: TimelineModel.Entry) -> some View {
        switch entry {
        case .message(let message):
            MessageBubble(message: message,
                          onReport: { reportTarget = message },
                          onViewProfile: { profileTarget = ProfileTarget(id: message.senderId) },
                          onDelete: deleteAction(for: message),
                          onEdit: editAction(for: message)
            )
        case .dayDivider(_, let date):
            Text(date, style: .date)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    ///if user has permissions return the deletion closure
    private func deleteAction(for message: TimelineModel.Message) -> (() -> Void)? {
        guard let details else { return nil }
        let canRedact = message.isOwn ? details.canRedactOwn() : details.canRedactOther()
        guard canRedact else { return nil }
        return {
            Task {
                do {
                    try await details.timeline.delete(message)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func editAction(for message: TimelineModel.Message) -> (() -> Void)? {
        guard let details else {return nil}
        if message.isOwn {
            return {
                editTarget = message
                editContent = message.body
                showEdit = true
            }
        } else {
            return nil
        }
    }
    
    private func send(_ draft: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let details else { return }
        errorMessage = nil

        Task {
            do {
                try await details.timeline.send(text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
