//
//  RoomPrivacyView.swift
//  Crux
//

import SwiftUI
import MatrixRustSDK


struct RoomPrivacyView: View {
    let room: RoomModel
    @Environment(UserSession.self) private var session

    @State private var isWorking = false
    @State private var errorMessage: String?

    @State private var canonicalLocalPart = ""
    @State private var altAliases: [String] = []
    @State private var newAliasLocalPart = ""
    @State private var isSavingAliases = false
    @State private var aliasError: String?

    // for space restricted join options
    @State private var parentSpaces: [SpaceRoom] = []
    @State private var pendingJoinOption: JoinRuleOption?
    @State private var selectedSpaceIds: Set<String> = []

    @State private var isListed: Bool?
    @State private var visibilityError: String?

    //of the user's homeserver
    private var homeserver: String {
        room.serverName ?? session.userId.split(separator: ":").last.map(String.init) ?? ""
    }

    private func localPart(of alias: String) -> String? {
        guard alias.hasPrefix("#"), alias.hasSuffix(":\(homeserver)") else { return nil }
        return String(alias.dropFirst().dropLast(homeserver.count + 1))
    }

    private func fullAlias(_ localPart: String) -> String { "#\(localPart):\(homeserver)" }

    private var hasAliasChanges: Bool {
        let trimmed = canonicalLocalPart.trimmingCharacters(in: .whitespaces)
        let newCanonical: String? = trimmed.isEmpty ? nil : fullAlias(trimmed)
        return newCanonical != room.canonicalAlias || altAliases != room.alternativeAliases
    }

    var body: some View {
        Form {
            if room.canSendState(.roomJoinRules) {
                joinRuleSection
            }
            if room.canSendState(.roomHistoryVisibility) {
                historyVisibilitySection
            }
            if room.canSendState(.roomCanonicalAlias) {
                aliasesSection
            }
            if room.canEditPrivacy {
                directorySection
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Privacy & Access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if room.canSendState(.roomCanonicalAlias) {
                ToolbarItem(placement: .confirmationAction) {
                    if isSavingAliases {
                        ProgressView()
                    } else {
                        Button("Save", action: saveAliases)
                            .disabled(!hasAliasChanges)
                    }
                }
            }
        }
        .onAppear {
            canonicalLocalPart = room.canonicalAlias.flatMap(localPart) ?? ""
            altAliases = room.alternativeAliases
        }
        .onChange(of: room.joinRule) { _, _ in pendingJoinOption = nil }
        .task {
            parentSpaces = await session.spaces.parentSpaces(of: room.id)
            isListed = (try? await room.getVisibility()).map { $0 == .public }
        }
    }

    // MARK: Join rule

    private enum JoinRuleOption: CaseIterable, Identifiable {
        case publicRoom, invite, knock, restricted, knockRestricted
        var id: Self { self }

        var label: String {
            switch self {
            case .publicRoom: "Public"
            case .invite: "Invite Only"
            case .knock: "Ask to Join"
            case .restricted: "Space Members Only"
            case .knockRestricted: "Space Members (or Ask to Join)"
            }
        }
        var sdkValue: JoinRule? {
            switch self {
            case .publicRoom: .public
            case .invite: .invite
            case .knock: .knock
            case .restricted, .knockRestricted: nil
            }
        }
        var needsSpaces: Bool { self == .restricted || self == .knockRestricted }

        init?(_ rule: JoinRule) {
            switch rule {
            case .public: self = .publicRoom
            case .invite: self = .invite
            case .knock: self = .knock
            case .restricted: self = .restricted
            case .knockRestricted: self = .knockRestricted
            case .private, .custom: return nil
            }
        }
    }

    @ViewBuilder
    private var joinRuleSection: some View {
        Section {
            if let current = room.joinRule, let option = JoinRuleOption(current) {
                Picker("Who can join", selection: joinRuleBinding(current: option)) {
                    ForEach(JoinRuleOption.allCases) { candidate in
                        // Always keep the room's actual current rule selectable,
                        // even if we have no parent spaces on record for it.
                        if !candidate.needsSpaces || !parentSpaces.isEmpty || candidate == option {
                            Text(candidate.label).tag(candidate)
                        }
                    }
                }
                .disabled(isWorking)

                if pendingJoinOption?.needsSpaces == true {
                    if parentSpaces.isEmpty {
                        Text("This room isn't in any space you've joined, so there's nothing to restrict it to.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(parentSpaces, id: \.roomId) { space in
                            Toggle(space.displayName, isOn: spaceSelectionBinding(space.roomId))
                        }
                    }
                    HStack {
                        Button("Apply", action: applyRestrictedJoinRule)
                            .disabled(selectedSpaceIds.isEmpty || isWorking)
                        Spacer()
                        Button("Cancel", role: .cancel) { pendingJoinOption = nil }
                            .disabled(isWorking)
                    }
                }
            } else {
                LabeledContent("Who can join", value: joinRuleDescription)
            }
        } footer: {
            if room.joinRule.flatMap(JoinRuleOption.init) == nil {
                Text("This room's join rule is custom, and can't be changed here.")
            }
        }
    }

    private var joinRuleDescription: String {
        switch room.joinRule {
        case .custom(let repr): repr
        case .public, .invite, .knock, .restricted, .knockRestricted, .private, .none: "Unknown"
        }
    }

    private func spaceSelectionBinding(_ spaceId: String) -> Binding<Bool> {
        Binding(get: { selectedSpaceIds.contains(spaceId) }) { isOn in
            if isOn { selectedSpaceIds.insert(spaceId) } else { selectedSpaceIds.remove(spaceId) }
        }
    }

    private func joinRuleBinding(current: JoinRuleOption) -> Binding<JoinRuleOption> {
        Binding(get: { pendingJoinOption ?? current }) { new in
            guard let value = new.sdkValue else {
                pendingJoinOption = new
                selectedSpaceIds = Self.currentAllowedSpaces(room.joinRule, matching: new)
                return
            }
            pendingJoinOption = nil
            isWorking = true
            errorMessage = nil
            Task {
                do { try await room.updateJoinRule(value) }
                catch { errorMessage = error.localizedDescription }
                isWorking = false
            }
        }
    }

    private static func currentAllowedSpaces(_ current: JoinRule?, matching option: JoinRuleOption) -> Set<String> {
        let rules: [AllowRule]
        switch (current, option) {
        case (.restricted(let r), .restricted): rules = r
        case (.knockRestricted(let r), .knockRestricted): rules = r
        default: rules = []
        }
        return Set(rules.compactMap { if case .roomMembership(let id) = $0 { id } else { nil } })
    }

    private func applyRestrictedJoinRule() {
        guard let pendingJoinOption else { return }
        let rules = selectedSpaceIds.map { AllowRule.roomMembership(roomId: $0) }
        let rule: JoinRule = pendingJoinOption == .knockRestricted
            ? .knockRestricted(rules: rules) : .restricted(rules: rules)
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await room.updateJoinRule(rule)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    // MARK: History visibility

    private enum HistoryOption: CaseIterable, Identifiable {
        case invited, joined, shared, worldReadable
        var id: Self { self }

        var label: String {
            switch self {
            case .invited: "Since Invited"
            case .joined: "Since Joined"
            case .shared: "Members, All History"
            case .worldReadable: "Anyone, No Membership"
            }
        }
        ///user readable descriptions
        var detail: String {
            switch self {
            case .invited: "New members can read messages from when they were invited onward."
            case .joined: "New members can only read messages sent after they joined."
            case .shared: "Any member can read the room's entire history, even messages sent before they joined."
            case .worldReadable: "Anyone can read every message — even people who've never joined the room at all."
            }
        }
        var sdkValue: RoomHistoryVisibility {
            switch self {
            case .invited: .invited
            case .joined: .joined
            case .shared: .shared
            case .worldReadable: .worldReadable
            }
        }
        init(_ visibility: RoomHistoryVisibility) {
            switch visibility {
            case .invited: self = .invited
            case .joined: self = .joined
            case .shared, .custom: self = .shared
            case .worldReadable: self = .worldReadable
            }
        }
    }

    private var historyVisibilitySection: some View {
        Section {
            Picker("Who can read history", selection: historyBinding) {
                ForEach(HistoryOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .disabled(isWorking)
        } footer: {
            Text(HistoryOption(room.historyVisibility).detail)
        }
    }

    private var historyBinding: Binding<HistoryOption> {
        Binding(get: { HistoryOption(room.historyVisibility) }) { new in
            isWorking = true
            errorMessage = nil
            Task {
                do { try await room.updateHistoryVisibility(new.sdkValue) }
                catch { errorMessage = error.localizedDescription }
                isWorking = false
            }
        }
    }

    // MARK: Aliases

    ///localpart
    private var aliasesSection: some View {
        Section {
            aliasField("main", text: $canonicalLocalPart)
            ForEach(altAliases, id: \.self) { alias in
                Text(alias)
            }
            .onDelete { altAliases.remove(atOffsets: $0) }
            HStack {
                aliasField("another", text: $newAliasLocalPart, onSubmit: addAlias)
                Button("Add", action: addAlias)
                    .disabled(newAliasLocalPart.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Addresses")
        } footer: {
            if let aliasError {
                Text(aliasError).foregroundStyle(.red)
            } else if let existing = room.canonicalAlias, localPart(of: existing) == nil {
                Text("Currently \(existing), on another server. Set one above (on \(homeserver)) to replace it.")
            } else {
                Text("The first address is this room's primary one. New addresses can only be on \(homeserver).")
            }
        }
    }

    private func aliasField(_ placeholder: String, text: Binding<String>, onSubmit: (() -> Void)? = nil) -> some View {
        HStack(spacing: 2) {
            Text("#")
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { onSubmit?() }
            Text(":\(homeserver)").foregroundStyle(.secondary)
        }
    }

    private func addAlias() {
        let trimmed = newAliasLocalPart.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let alias = fullAlias(trimmed)
        guard !altAliases.contains(alias) else { return }
        altAliases.append(alias)
        newAliasLocalPart = ""
    }

    private func saveAliases() {
        let trimmed = canonicalLocalPart.trimmingCharacters(in: .whitespaces)
        let newCanonical: String? = trimmed.isEmpty ? nil : fullAlias(trimmed)
        isSavingAliases = true
        aliasError = nil
        Task {
            do {
                let existing = Set(room.alternativeAliases + [room.canonicalAlias].compactMap { $0 })
                let toCreate = Set((altAliases + [newCanonical].compactMap { $0 }).filter { !existing.contains($0) })
                for alias in toCreate {
                    try await room.createAlias(alias)
                }
                try await room.updateAliases(canonical: newCanonical, alternatives: altAliases)
            } catch {
                aliasError = error.localizedDescription
            }
            isSavingAliases = false
        }
    }

    // MARK: Room directory

    ///should it published in the server's room directory
    private var directorySection: some View {
        Section {
            if let isListed {
                Toggle("List in Room Directory", isOn: visibilityBinding(current: isListed))
                    .disabled(isWorking)
            } else {
                HStack {
                    Text("List in Room Directory")
                    Spacer()
                    ProgressView()
                }
            }
        } footer: {
            if let visibilityError {
                Text(visibilityError).foregroundStyle(.red)
            } else {
                Text("Listed rooms are discoverable by anyone searching this homeserver's public directory, regardless of who can join.")
            }
        }
    }

    private func visibilityBinding(current: Bool) -> Binding<Bool> {
        Binding(get: { current }) { new in
            isWorking = true
            visibilityError = nil
            Task {
                do {
                    try await room.updateVisibility(new ? .public : .private)
                    isListed = new
                } catch {
                    visibilityError = error.localizedDescription
                    // The toggle already flipped optimistically via the binding —
                    // put it back so the UI doesn't claim a state the server rejected.
                    isListed = current
                }
                isWorking = false
            }
        }
    }
}
