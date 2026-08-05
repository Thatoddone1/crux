//
//  NotificationSettingsView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

struct NotificationSettingsView: View {
    @Environment(PushModel.self) private var push
    @Environment(UserSession.self) private var session

    @State private var model: NotificationSettingsModel?

    @AppStorage(AppConfiguration.Push.timeSensitiveMentionsKey, store: AppConfiguration.defaults)
    private var timeSensitiveMentions = true

    var body: some View {
        List {
            Section {
                permissionRow
                Toggle("Time Sensitive Mentions", isOn: $timeSensitiveMentions)
            } footer: {
                Text("Time Sensitive mentions break through Focus and Do Not Disturb. This device only.")
            }

            if let model, model.isLoaded {
                Section {
                    modePicker("Direct Messages", value: model.directMessages) {
                        await model.setDirectMessages($0)
                    }
                    modePicker("Group Chats", value: model.groupChats) {
                        await model.setGroupChats($0)
                    }
                } header: {
                    Text("Notify Me For")
                } footer: {
                    Text("Applies to every device you're signed in on.")
                }

                Section {
                    toggle("Mentions", isOn: model.mentions) { await model.setMentions($0) }
                    toggle("Invites", isOn: model.invites) { await model.setInvites($0) }
                    toggle("Calls", isOn: model.calls) { await model.setCalls($0) }
                } footer: {
                    Text("Mentions and invites still come through when a chat is set to Nothing.")
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Notifications")
        .task {
            await push.refresh()
            let model = model ?? NotificationSettingsModel(client: session.client, store: session.rooms)
            self.model = model
            await model.load()
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            LabeledContent("Permission", value: "Granted")
        case .denied:
            Link("Turn On in Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
        default:
            Button("Turn On Notifications") {
                Task { await push.requestAuthorization() }
            }
        }
    }

    private func modePicker(_ title: String,
                            value: RoomNotificationMode,
                            set: @escaping (RoomNotificationMode) async -> Void) -> some View {
        Picker(title, selection: Binding(get: { value }, set: { mode in Task { await set(mode) } })) {
            ForEach([RoomNotificationMode.allMessages, .mentionsAndKeywordsOnly, .mute], id: \.self) {
                Text($0.name).tag($0)
            }
        }
    }

    private func toggle(_ title: String,
                        isOn: Bool,
                        set: @escaping (Bool) async -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { on in Task { await set(on) } }))
    }
}
