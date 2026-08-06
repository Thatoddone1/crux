//
//  ProfileSettingsView.swift
//  Crux
//

import SwiftUI
import PhotosUI

/// for own user profile, not others'
struct ProfileSettingsView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var avatar: UIImage?
    @State private var pickedItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var hasNameChange: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != (session.displayName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        avatarPicker
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Display name") {
                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .onSubmit(saveName)
                }

                Section {
                    LabeledContent("Matrix ID", value: session.userId)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Save", action: saveName)
                            .disabled(!hasNameChange)
                    }
                }
            }
            .onAppear { displayName = session.displayName ?? "" }
            .task(id: session.avatarUrl) {
                guard let url = session.avatarUrl else { avatar = nil; return }
                avatar = await MediaLoader.shared.avatar(for: url, client: session.client, pixelSize: 256)
            }
            .onChange(of: pickedItem) { _, newItem in
                Task { await applyPicked(newItem) }
            }
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatar {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(.circle)

                Image(systemName: "camera.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(.background, in: .circle)
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .contextMenu {
            if avatar != nil {
                Button("Remove Photo", systemImage: "trash", role: .destructive, action: removeAvatar)
            }
        }
    }

    private func applyPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.85) else {
                errorMessage = "Couldn't read that image."
                return
            }
            avatar = image
            try await session.setAvatar(data: jpeg, mimeType: "image/jpeg")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeAvatar() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await session.removeAvatar()
                avatar = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func saveName() {
        guard hasNameChange else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await session.setDisplayName(trimmed)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
