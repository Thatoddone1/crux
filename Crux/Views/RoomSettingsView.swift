//
//  RoomSettingsView.swift
//  Crux
//
//  Created by Joshua Kellman on 8/5/26.
//

import SwiftUI
import MatrixRustSDK

/// A room's preferences.
struct RoomSettingsView: View {
    let room: RoomModel
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showMembers = false
    @State private var showInvite = false
    @State private var showLeaveConfirmation = false
    @State private var profileTarget: ProfileTarget?

    private var isDM: Bool { room.isDirect }

    private struct ProfileTarget: Identifiable {
        let id: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("Your settings") {
                    priorityPicker
                    notificationPicker
                }

                if isDM { directSection } else { groupSection }

                Section {
                    Button(isDM ? "Leave conversation" : "Leave room", role: .destructive) {
                        showLeaveConfirmation = true
                    }
                }
            }
            .navigationTitle(isDM ? "Conversation" : "Room Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await room.loadMembers() }
            .sheet(isPresented: $showMembers) { RoomMembersView(room: room) }
            .sheet(isPresented: $showInvite) { InviteToRoomView(room: room) }
            .sheet(item: $profileTarget) { target in
                UserProfileView(userId: target.id, session: session, room: room.room)
            }
            .confirmationDialog("Leave \(room.name)?",
                                isPresented: $showLeaveConfirmation,
                                titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    Task {
                        try? await room.leave()
                        dismiss()
                    }
                }
            } message: {
                Text("You'll stop receiving messages from this room.")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var groupSection: some View {
        Section("Room") {
            if let topic = room.topic, !topic.isEmpty {
                LabeledContent("Topic", value: topic)
            }
            LabeledContent("Members", value: room.joinedMembersCount.description)
            LabeledContent("Encrypted", value: room.isEncrypted ? "Yes" : "No")
            Button("View members") { showMembers = true }
            if room.canInvite() {
                Button("Invite people") { showInvite = true }
            }
        }
    }

    
    @ViewBuilder
    private var directSection: some View {
        Section("Conversation") {
            LabeledContent("Encrypted", value: room.isEncrypted ? "Yes" : "No")
            if let heroId = room.directHeroId {
                LabeledContent("User", value: heroId)
                Button("View profile") { profileTarget = ProfileTarget(id: heroId) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            AvatarView(avatarUrl: room.avatarUrl, size: 110)
            Text(room.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if !isDM {
                Text("\(room.joinedMembersCount) \(room.joinedMembersCount == 1 ? "member" : "members")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            RoomChips(room)
        }
        .padding(.vertical, 8)
    }

    // MARK: Notifications

    /// "Default" is its own option rather than a mode: a room either follows the
    /// account setting or overrides it, and picking `.allMessages` explicitly is
    /// not the same as inheriting it.
    private var notificationPicker: some View {
        Picker("Notify me about", selection: notificationSelection) {
            Text("Default (\(room.notificationDefaults.mode(isEncrypted: room.isEncrypted, isOneToOne: room.isOneToOne).name))")
                .tag(NotificationChoice.followDefault)
            ForEach(NotificationChoice.overrides, id: \.self) { choice in
                Text(choice.label).tag(choice)
            }
        }
    }

    private enum NotificationChoice: Hashable {
        case followDefault
        case mode(RoomNotificationMode)

        static let overrides: [NotificationChoice] = [
            .mode(.allMessages), .mode(.mentionsAndKeywordsOnly), .mode(.mute)
        ]

        var label: String {
            switch self {
            case .followDefault: "Default"
            case .mode(let mode): mode.name
            }
        }
    }

    private var notificationSelection: Binding<NotificationChoice> {
        Binding {
            room.hasNotificationOverride ? .mode(room.notificationMode) : .followDefault
        } set: { choice in
            Task {
                switch choice {
                case .followDefault: await room.followDefaultNotificationMode()
                // Unmuting goes through the SDK's own inverse rather than writing
                // `.allMessages` over the mute rule, so `setMuted` owns both ends.
                case .mode(.mute): await room.setMuted(true)
                case .mode(let mode) where room.isMuted:
                    await room.setMuted(false)
                    await room.setNotificationMode(mode)
                case .mode(let mode): await room.setNotificationMode(mode)
                }
            }
        }
    }

    // MARK: Priority

    private var priorityPicker: some View {
        Picker("Priority", selection: priority) {
            Label("Favorite", systemImage: "star").tag(Priority.favorite)
            Text("Normal").tag(Priority.normal)
            Label("Low", systemImage: "arrow.down.circle").tag(Priority.low)
        }
    }

    private enum Priority: Hashable { case favorite, normal, low }

    private var priority: Binding<Priority> {
        Binding {
            if room.isFavorite { return .favorite }
            if room.isLowPriority { return .low }
            return .normal
        } set: { new in
            Task {
                switch new {
                case .favorite: await room.setFavorite(true)
                case .low: await room.setLowPriority(true)
                case .normal:
                    if room.isFavorite { await room.setFavorite(false) }
                    if room.isLowPriority { await room.setLowPriority(false) }
                }
            }
        }
    }
}

/// Invites by mxid. The SDK reports a bad or unreachable id as a thrown error
/// rather than up front, so the field stays open until one lands.
private struct InviteToRoomView: View {
    let room: RoomModel
    @Environment(\.dismiss) private var dismiss

    @State private var userId = ""
    @State private var isInviting = false
    @State private var errorMessage: String?
    @State private var invited: [String] = []

    private var isValid: Bool {
        let trimmed = userId.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("@") && trimmed.contains(":")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("@someone:example.org", text: $userId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { if isValid { invite() } }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("Matrix IDs look like @name:server.org")
                    }
                }

                Section {
                    Button("Send invite") { invite() }
                        .disabled(!isValid || isInviting)
                }

                if !invited.isEmpty {
                    Section("Invited") {
                        ForEach(invited, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Invite to \(room.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func invite() {
        let target = userId.trimmingCharacters(in: .whitespaces)
        isInviting = true
        errorMessage = nil
        Task {
            do {
                try await room.invite(userId: target)
                invited.append(target)
                userId = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isInviting = false
        }
    }
}

/// The member list, loaded once by `RoomModel`.
private struct RoomMembersView: View {
    let room: RoomModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(room.members) { member in
                VStack(alignment: .leading) {
                    Text(member.name)
                    if member.displayName != nil {
                        Text(member.id).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if room.members.isEmpty { ProgressView() }
            }
        }
    }
}
