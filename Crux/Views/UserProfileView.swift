//
//  UserProfileView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

/// Minimal per-user profile: avatar, name, mxid, and a block/unblock button.
struct UserProfileView: View {
    let userId: String
    let session: UserSession

    @Environment(\.dismiss) private var dismiss
    @State private var model: UserProfileModel
    @State private var avatar: UIImage?
    @State private var errorMessage: String?
    @State private var isWorking = false

    init(userId: String, session: UserSession, room: Room? = nil) {
        self.userId = userId
        self.session = session
        _model = State(initialValue: UserProfileModel(userId: userId, session: session, room: room))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(.circle)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .foregroundStyle(.secondary)
                }

                Text(model.displayName ?? userId)
                    .font(.title2.bold())
                Text(userId)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !model.isSelf {
                    Button {
                        toggleBlock()
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(model.isIgnored ? "Unblock" : "Block")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isIgnored ? .accentColor : .red)
                    .disabled(isWorking)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                try? await model.load()
                if let url = model.avatarUrl {
                    avatar = await MediaLoader.shared.avatar(for: url, client: session.client)
                }
            }
        }
    }

    private func toggleBlock() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                if model.isIgnored { try await model.unignore() } else { try await model.ignore() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
