//
//  RoomMembersView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

struct RoomMembersView: View {
    let room: RoomModel
    @Environment(UserSession.self) private var session

    @State private var errorMessage: String?
    @State private var workingId: String?

    
    private var active: [RoomModel.Member] {
        room.members.filter { $0.membership == .join || $0.membership == .invite }
    }
    private var banned: [RoomModel.Member] {
        room.members.filter { $0.membership == .ban }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Section {
                if room.canInvite() {
                    NavigationLink(value: RoomSettingsRoute.invite) {
                        Label("Invite People", systemImage: "person.badge.plus")
                    }
                }
                ForEach(active) { member in
                    row(for: member)
                }
            }
            if !banned.isEmpty {
                Section("Banned") {
                    ForEach(banned) { member in
                        row(for: member)
                    }
                }
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if room.members.isEmpty { ProgressView() }
        }
    }

    @ViewBuilder
    private func row(for member: RoomModel.Member) -> some View {
        NavigationLink(value: RoomSettingsRoute.memberDetail(id: member.id)) {
            MemberRow(member: member, isWorking: workingId == member.id)
        }
        .disabled(workingId == member.id)
        .swipeActions(edge: .trailing) { actions(for: member) }
    }

    @ViewBuilder
    private func actions(for member: RoomModel.Member) -> some View {
        let isSelf = member.id == session.userId
        if !isSelf {
            switch member.membership {
            case .ban:
                if room.canBan() {
                    Button("Unban") { perform(member.id) { try await room.unban(member.id) } }
                        .tint(.blue)
                }
            default:
                if room.canBan() {
                    Button("Ban", role: .destructive) { perform(member.id) { try await room.ban(member.id) } }
                }
                if room.canKick(), member.membership == .join {
                    Button("Kick") { perform(member.id) { try await room.kick(member.id) } }
                        .tint(.orange)
                }
            }
        }
    }

    private func perform(_ userId: String, _ action: @escaping () async throws -> Void) {
        workingId = userId
        errorMessage = nil
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
            workingId = nil
        }
    }
}

struct MemberRow: View {
    let member: RoomModel.Member
    var isWorking: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: member.avatarUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).lineLimit(1)
                if member.displayName != nil {
                    Text(member.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isWorking {
                ProgressView()
            } else if member.membership == .invite {
                Text("Invited").font(.caption).foregroundStyle(.secondary)
            } else {
                roleChip
            }
        }
    }

    @ViewBuilder
    private var roleChip: some View {
        switch member.role {
        case .creator:
            Chip(icon: "crown.fill", label: "Creator", color: .yellow)
        case .administrator:
            Chip(icon: "shield.fill", label: "Admin", color: .red)
        case .moderator:
            Chip(icon: "checkmark.shield.fill", label: "Mod", color: .orange)
        case .user:
            EmptyView()
        }
    }
}
