//
//  InviteToRoomView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

/// Invites by MXID
struct InviteToRoomView: View {
    let room: RoomModel
    @Environment(UserSession.self) private var session

    @State private var userId = ""
    @State private var isInviting = false
    @State private var errorMessage: String?
    @State private var invited: [String] = []
    @State private var suggestions: [UserProfile] = []
    @State private var searchTask: Task<Void, Never>?

    private var isValid: Bool {
        let trimmed = userId.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("@") && trimmed.contains(":")
    }

    var body: some View {
        Form {
            Section {
                TextField("@someone:example.org", text: $userId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { if isValid { invite(userId) } }
                    .onChange(of: userId) { _, new in search(new) }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else {
                    Text("Matrix IDs look like @name:server.org")
                }
            }

            if !suggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(suggestions, id: \.userId) { user in
                        Button {
                            invite(user.userId)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(avatarUrl: user.avatarUrl, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName ?? user.userId)
                                    if user.displayName != nil {
                                        Text(user.userId).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }

            Section {
                Button("Send invite") { invite(userId) }
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
    }


    private func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, !isValid else {
            suggestions = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let results = await session.searchUsers(trimmed, limit: 6)
            guard !Task.isCancelled else { return }
            suggestions = results
        }
    }

    private func invite(_ target: String) {
        let target = target.trimmingCharacters(in: .whitespaces)
        isInviting = true
        errorMessage = nil
        Task {
            do {
                try await room.invite(userId: target)
                invited.append(target)
                userId = ""
                suggestions = []
            } catch {
                errorMessage = error.localizedDescription
            }
            isInviting = false
        }
    }
}
