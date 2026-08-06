//
//  EditRoomView.swift
//  Crux
//

import SwiftUI
import PhotosUI
import MatrixRustSDK

/// Name, topic, and avatar.
struct EditRoomView: View {
    let room: RoomModel
    @Environment(UserSession.self) private var session

    @State private var name = ""
    @State private var topic = ""
    @State private var avatar: UIImage?
    @State private var pickedItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var hasNameChange: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != room.name
    }
    private var hasTopicChange: Bool {
        topic.trimmingCharacters(in: .whitespacesAndNewlines) != (room.topic ?? "")
    }
    private var hasChanges: Bool { hasNameChange || hasTopicChange }

    var body: some View {
        Form {
            if room.canSendState(.roomAvatar) {
                Section {
                    HStack {
                        Spacer()
                        avatarPicker
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if room.canSendState(.roomName) {
                Section("Name") {
                    TextField("Room name", text: $name)
                }
            }

            if room.canSendState(.roomTopic) {
                Section("Topic") {
                    TextField("Topic", text: $topic, axis: .vertical)
                        .lineLimit(3...6)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit Room")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(!hasChanges)
                }
            }
        }
        .onAppear {
            name = room.name
            topic = room.topic ?? ""
        }
        .task(id: room.avatarUrl) {
            guard let url = room.avatarUrl else { avatar = nil; return }
            avatar = await MediaLoader.shared.avatar(for: url, client: session.client, pixelSize: 256)
        }
        .onChange(of: pickedItem) { _, newItem in
            Task { await applyPicked(newItem) }
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatar {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo.circle.fill")
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
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't read that image."
                return
            }
            avatar = image
            try await room.setAvatar(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeAvatar() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await room.removeAvatar()
                avatar = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func save() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                if hasNameChange {
                    try await room.setName(name.trimmingCharacters(in: .whitespaces))
                }
                if hasTopicChange {
                    try await room.setTopic(topic.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
