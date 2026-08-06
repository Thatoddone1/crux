//
//  MemberDetailView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK


struct MemberDetailView: View {
    let room: RoomModel
    let userId: String
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showsFullProfile = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var member: RoomModel.Member? { room.members.first { $0.id == userId } }
    private var isSelf: Bool { userId == session.userId }
    private var viewerPowerLevel: Int64 { room.powerLevel(of: session.userId) }
    private var targetPowerLevel: Int64 { room.powerLevel(of: userId) }


    private var canEditRole: Bool {
        room.canEditPowerLevels() && !isSelf && member?.role != .creator && targetPowerLevel < viewerPowerLevel
    }

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if let member {
                if canEditRole {
                    Section("Role") {
                        Picker("Role", selection: roleBinding(current: RoleOption(member.role))) {
                            ForEach(RoleOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }
                } else {
                    Section {
                        LabeledContent("Role", value: RoleOption(member.role).label)
                    }
                }

                if !isSelf, (room.canKick() || room.canBan()) {
                    Section {
                        actions(for: member)
                    }
                }
            }

            Section {
                Button("View Full Profile") { showsFullProfile = true }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(member?.name ?? userId)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsFullProfile) {
            UserProfileView(userId: userId, session: session, room: room.room)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            AvatarView(avatarUrl: member?.avatarUrl, size: 88)
            Text(member?.name ?? userId).font(.title3.weight(.semibold))
            if member?.displayName != nil {
                Text(userId).font(.caption).foregroundStyle(.secondary)
            }
            if member?.membership == .invite {
                Chip(icon: "envelope.fill", label: "Invited", color: .blue)
            } else if member?.membership == .ban {
                Chip(icon: "nosign", label: "Banned", color: .red)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func actions(for member: RoomModel.Member) -> some View {
        if isWorking {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else {
            switch member.membership {
            case .ban:
                if room.canBan() {
                    Button("Unban") { perform { try await room.unban(userId) } }
                }
            default:
                if room.canKick(), member.membership == .join {
                    Button("Kick", role: .destructive) { perform { try await room.kick(userId) } }
                }
                if room.canBan() {
                    Button("Ban", role: .destructive) { perform { try await room.ban(userId) } }
                }
            }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await action()
                // Kick/ban remove the member from `room.members` — if they're
                // gone there's nothing left to show here.
                if room.members.first(where: { $0.id == userId }) == nil { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func roleBinding(current: RoleOption) -> Binding<RoleOption> {
        Binding(get: { current }) { new in
            isWorking = true
            errorMessage = nil
            Task {
                do { try await room.setPowerLevel(of: userId, to: new.powerLevel) }
                catch { errorMessage = error.localizedDescription }
                isWorking = false
            }
        }
    }
}

private enum RoleOption: CaseIterable, Identifiable {
    case user, moderator, administrator
    var id: Self { self }

    var label: String {
        switch self {
        case .user: "Member"
        case .moderator: "Moderator"
        case .administrator: "Admin"
        }
    }
    var powerLevel: Int64 {
        switch self {
        case .user: 0
        case .moderator: 50
        case .administrator: 100
        }
    }
    init(_ role: RoomMemberRole) {
        switch role {
        case .creator, .administrator: self = .administrator
        case .moderator: self = .moderator
        case .user: self = .user
        }
    }
}
