//
//  SearchView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK

private enum SearchRoute: Hashable {
    case room(id: String)
    case space(id: String)
}

struct SearchView: View {
    @Environment(UserSession.self) private var session

    @State private var searchText = ""
    @State private var scope: SearchModel.Scope = .global
    @State private var model: SearchModel?
    @State private var path = NavigationPath()
    @State private var profileTarget: ProfileTarget?
    @State private var joiningId: String?
    @State private var messagingId: String?
    @State private var errorMessage: String?

    private struct ProfileTarget: Identifiable { let id: String }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if !searchText.isEmpty {
                    Picker("Scope", selection: $scope) {
                        Text("Mine").tag(SearchModel.Scope.mine)
                        Text("Global").tag(SearchModel.Scope.global)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
                ForEach(model?.results ?? []) { result in
                    row(for: result)
                }
                if model?.isSearchingUsers == true {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Rooms, people, or a matrix.to link")
            .overlay {
                if searchText.isEmpty {
                    ContentUnavailableView("Search Crux", systemImage: "magnifyingglass",
                        description: Text("Find rooms and spaces, look up people, or paste a matrix.to link."))
                } else if let model, model.results.isEmpty, !model.isSearchingUsers {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .onAppear { if model == nil { model = SearchModel(session: session) } }
            .onChange(of: searchText) { _, new in model?.search(new, scope: scope) }
            .onChange(of: scope) { _, new in model?.search(searchText, scope: new) }
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case .room(let id):
                    RoomView(roomId: id)
                case .space(let id):
                    if let node = session.spaces.nodes.first(where: { $0.id == id }) {
                        SpaceDetailView(node: node)
                    }
                }
            }
            .sheet(item: $profileTarget) { target in
                UserProfileView(userId: target.id, session: session)
            }
        }
        .overlay(SettingsButton(), alignment: .topTrailing)
    }

    @ViewBuilder
    private func row(for result: SearchModel.Result) -> some View {
        switch result {
        case .room(let room):
            NavigationLink(value: SearchRoute.room(id: room.id)) {
                SearchResultRow(title: room.name, subtitle: room.canonicalAlias,
                                avatarUrl: room.avatarUrl, systemImage: "bubble.left.fill",
                                showsJoinedChip: scope == .global)
            }
        case .space(let node):
            NavigationLink(value: SearchRoute.space(id: node.id)) {
                SearchResultRow(title: node.spaceRoom.displayName, subtitle: node.spaceRoom.canonicalAlias,
                                avatarUrl: node.spaceRoom.avatarUrl, systemImage: "square.stack.3d.up.fill",
                                showsJoinedChip: scope == .global)
            }
        case .person(let user):
            personRow(user)
        case .unjoinedRoom(let idOrAlias):
            Button {
                join(idOrAlias)
            } label: {
                SearchResultRow(title: idOrAlias, subtitle: "Not joined — tap to join",
                                avatarUrl: nil, systemImage: "arrow.right.circle",
                                isWorking: joiningId == idOrAlias)
            }
            .tint(.primary)
            .disabled(joiningId != nil)
        }
    }

    ///without a dm yet
    private func personRow(_ user: UserProfile) -> some View {
        HStack(spacing: 12) {
            SearchResultRow(title: user.displayName ?? user.userId, subtitle: user.userId,
                            avatarUrl: user.avatarUrl, systemImage: "person.crop.circle.fill")
            if messagingId == user.userId {
                ProgressView()
            } else {
                Button {
                    profileTarget = ProfileTarget(id: user.userId)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .buttonStyle(.borderless)
                Button {
                    message(user.userId)
                } label: {
                    Image(systemName: "message.fill")
                }
                .buttonStyle(.borderless)
            }
        }
        ///disable this row while joining
        .disabled(messagingId == user.userId)
    }

    private func join(_ idOrAlias: String) {
        guard let model else { return }
        joiningId = idOrAlias
        errorMessage = nil
        Task {
            do {
                let roomId = try await model.join(idOrAlias)
                //rerun search
                model.search(searchText, scope: scope)
                path.append(SearchRoute.room(id: roomId))
            } catch {
                errorMessage = "Couldn't join \(idOrAlias): \(error.localizedDescription)"
            }
            joiningId = nil
        }
    }

    private func message(_ userId: String) {
        guard let model else { return }
        messagingId = userId
        errorMessage = nil
        Task {
            do {
                let roomId = try await model.startDM(with: userId)
                model.search(searchText, scope: scope)
                path.append(SearchRoute.room(id: roomId))
            } catch {
                errorMessage = "Couldn't message them: \(error.localizedDescription)"
            }
            messagingId = nil
        }
    }
}

/// One line of any search result
private struct SearchResultRow: View {
    let title: String
    let subtitle: String?
    let avatarUrl: String?
    let systemImage: String
    var isWorking: Bool = false
    var showsJoinedChip: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if avatarUrl != nil {
                AvatarView(avatarUrl: avatarUrl, size: 44)
            } else {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if showsJoinedChip {
                Chip(icon: "checkmark.circle.fill", label: "Joined", color: .green)
            }
            if isWorking { ProgressView() }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SearchView()
}
