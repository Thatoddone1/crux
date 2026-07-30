//
//  NewRoomView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/28/26.
//

import SwiftUI

struct NewRoomView: View {

    enum RoomType: String, Identifiable, CaseIterable {
        case dm = "Direct Message"
        case group = "Group"

        var id: String { self.rawValue }
    }

    @Environment(UserSession.self) var session
    @Binding var path: NavigationPath

    @State var roomType = RoomType.dm
    @State var roomName = ""
    @State var dmUser = ""
    @State var groupUsers: [String] = [""]
    @State var isCreating = false
    @State var errorMessage: String?
    @State var isEncrypted = true
    @State var isPublic = false

    var body: some View {
        VStack {
            Picker("Room Type", selection: $roomType) {
                ForEach(RoomType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)


            if roomType == .group {
                TextField("Room Name", text: $roomName)
                    .textFieldStyle(.roundedBorder)
                    .glassEffect()
                Divider()


                Text("Users in room")
                    .font(.headline)
                    .fontWeight(.bold)
                ForEach($groupUsers.indices, id: \.self) { index in
                    HStack{
                        TextField("@person:example.com", text: $groupUsers[index])
                        Button() {
                            groupUsers.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                        }

                    }
                }
                Button("Add User") {
                    groupUsers.append("")
                }
                .buttonStyle(.glass)
                
                Toggle("Public", isOn: $isPublic)
            } else {
                TextField("User to message", text: $dmUser)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Encyrpted", isOn: $isEncrypted)
            
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            
            Spacer()

            Button {
                createChat()
            } label: {
                if isCreating {
                    ProgressView()
                } else {
                    Text("Create Chat")
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isCreating)
        }
        .padding()
        .navigationTitle("Create a Room")
        }

    private func createChat() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let roomId = roomType == .dm
                    ? try await session.createDM(with: dmUser, isEncrypted: isEncrypted)
                    : try await session.createRoom(name: roomName, isEncrypted: isEncrypted, isPublic: isPublic, invite: groupUsers.filter { !$0.isEmpty })
                path.removeLast()
                path.append(RoomListRoute.room(id: roomId))
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}
