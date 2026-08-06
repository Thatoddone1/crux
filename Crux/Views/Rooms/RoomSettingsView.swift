//
//  RoomSettingsView.swift
//  Crux
//
//  Created by Joshua Kellman on 8/5/26.
//

import SwiftUI
import MatrixRustSDK


enum RoomSettingsRoute: Hashable {
    case editRoom
    case privacy
    case members
    case invite
    case memberDetail(id: String)
}

/// A room's preferences.
struct RoomSettingsView: View {
    let room: RoomModel
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var path = NavigationPath()
    @State private var showLeaveConfirmation = false
    @State private var profileTarget: ProfileTarget?

    private var isDM: Bool { room.isDirect }

    private struct ProfileTarget: Identifiable {
        let id: String
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationDestination(for: RoomSettingsRoute.self) { route in
                switch route {
                case .editRoom:
                    EditRoomView(room: room)
                case .privacy:
                    RoomPrivacyView(room: room)
                case .members:
                    RoomMembersView(room: room)
                case .invite:
                    InviteToRoomView(room: room)
                case .memberDetail(let id):
                    MemberDetailView(room: room, userId: id)
                }
            }
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
            NavigationLink("People", value: RoomSettingsRoute.members)
        }
        if room.canEditRoomDetails || room.canEditPrivacy {
            Section("Manage") {
                if room.canEditRoomDetails {
                    NavigationLink("Edit Room", value: RoomSettingsRoute.editRoom)
                }
                if room.canEditPrivacy {
                    NavigationLink("Privacy & Access", value: RoomSettingsRoute.privacy)
                }
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
