//
//  RoomView.swift
//  Crux
//

import SwiftUI

struct RoomView: View {
    let roomId: String
    @Environment(UserSession.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var details: RoomDetailsModel? //all details about the room
    @State private var errorMessage: String?
    @State private var profileTarget: ProfileTarget?
    @State private var showMemberMenu = false
    @State private var reportTarget: TimelineModel.Message?
    @State private var editTarget: TimelineModel.Message?
    @State private var editContent: String = ""
    @State private var showEdit: Bool = false
    @State private var replyTarget: TimelineModel.Message?
    /// The entry a jump just landed on, flashed briefly then cleared.
    @State private var highlightedEntryID: String?
    @State private var highlightTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool
    
    
    private struct ProfileTarget: Identifiable {
        let id: String
    }
    
    var body: some View {
        Group {
            if let details {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(details.timeline.entries.enumerated()), id: \.element.id) { index, entry in
                            row(for: entry,
                                after: previousMessage(before: index, in: details.timeline.entries),
                                proxy: proxy)
                                .onAppear {
                                    if entry.id == details.timeline.entries.first?.id {
                                        Task {
                                            try? await details.timeline.loadMore()
                                        }
                                    }
                                    if entry.id == details.timeline.entries.last?.id {
                                        Task {
                                            try? await details.timeline.markAsRead()
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.immediately)
                .onLongPressGesture(perform: openTitleAction)
                .safeAreaInset(edge: .bottom) {
                    if (details.canSendMessage()) {
                        Composer(
                            onSend: send,
                            errorMessage: errorMessage,
                            replyingTo: replyTarget,
                            onReply: sendReply,
                            onCancelReply: { replyTarget = nil },
                            focus: $composerFocused
                        )
                    } else {
                        Text("You don't have permission to send here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
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
                let details = try session.roomDetails(for: roomId)
                self.details = details
                await details.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        // Suppresses notification banners for the room already on screen.
        .onAppear { router.visibleRoomId = roomId }
        .onDisappear { if router.visibleRoomId == roomId { router.visibleRoomId = nil } }
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
    
    /// The message directly above `index`, or nil when a day divider (or the top
    /// of the timeline) breaks the run.
    private func previousMessage(before index: Int, in entries: [TimelineModel.Entry]) -> TimelineModel.Message? {
        guard index > 0, case .message(let message) = entries[index - 1] else { return nil }
        return message
    }

    /// Scrolls to the message a reply answers and flashes it, so the landing is
    /// legible. Older history may not be paginated in yet — say so rather than
    /// doing nothing.
    private func jump(to eventId: String, using proxy: ScrollViewProxy) {
        guard let entryID = details?.timeline.entryID(forEvent: eventId) else {
            errorMessage = "That message hasn't loaded yet — scroll up to load more."
            return
        }
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(entryID, anchor: .center)
            highlightedEntryID = entryID
        }
        highlightTask?.cancel()
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            highlightedEntryID = nil
        }
    }

    @ViewBuilder
    private func row(for entry: TimelineModel.Entry,
                     after previous: TimelineModel.Message?,
                     proxy: ScrollViewProxy) -> some View {
        switch entry {
        case .message(let message):
            MessageBubble(message: message,
                          onReport: { reportTarget = message },
                          onViewProfile: { profileTarget = ProfileTarget(id: message.senderId) },
                          onDelete: deleteAction(for: message),
                          onEdit: editAction(for: message),
                          onReact: {key in Task { try await details?.timeline.toggleReaction(key, on: message) }  },
                          onReply: replyAction(for: message),
                          swipeToReply: canSendMessage,
                          showsHeader: message.startsGroup(after: previous),
                          onJumpToReply: message.replyTo.map { reply in
                              { jump(to: reply.eventId, using: proxy) }
                          },
                          isHighlighted: highlightedEntryID == message.id
            )
        case .dayDivider(_, let date):
            Text(date, style: .date)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
    }
    
    /// A reply is just another message, so it needs the same permission —
    /// without a composer there'd be nowhere to draft it or cancel out of it.
    private var canSendMessage: Bool {
        details?.canSendMessage() ?? false
    }

    private func replyAction(for message: TimelineModel.Message) -> (() -> Void)? {
        guard canSendMessage else { return nil }
        return {
            replyTarget = message
            composerFocused = true
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

    private func sendReply(_ draft: String, to message: TimelineModel.Message) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let details else { return }
        errorMessage = nil
        replyTarget = nil

        Task {
            do {
                try await details.timeline.reply(text, to: message)
            } catch TimelineError.notYetSent {
                // The target slipped out from under us — send the text plainly
                // rather than throwing away what they typed.
                errorMessage = "Sent without a reply — \(message.sender)'s message hadn't landed yet."
                try? await details.timeline.send(text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
