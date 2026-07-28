//
//  UserProfileModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// A Matrix user's profile: display info, room membership (if scoped to a
/// room), and moderation/verification state. Every mxid has one of these,
/// whether or not the SDK has anything cached about them yet.
@Observable
final class UserProfileModel {
    let userId: String
    /// Whether this profile is the signed-in user's own — hide block/report UI for it.
    var isSelf: Bool { userId == session.userId }

    private(set) var displayName: String?
    private(set) var avatarUrl: String?
    private(set) var membership: MembershipState?
    private(set) var isIgnored: Bool = false
    private(set) var isVerified: Bool = false

    private let session: UserSession
    private let room: Room?

    init(userId: String, session: UserSession, room: Room? = nil) {
        self.userId = userId
        self.session = session
        self.room = room
    }

    /// Fetches profile, membership and verification info. Safe to call even
    /// for a user the SDK knows nothing about yet.
    func load() async throws {
        if let room, let member = try? await room.member(userId: userId) {
            displayName = member.displayName
            avatarUrl = member.avatarUrl
            membership = member.membership
            isIgnored = member.isIgnored
        } else {
            if let profile = try? await session.client.getProfile(userId: userId) {
                displayName = profile.displayName
                avatarUrl = profile.avatarUrl
            }
            isIgnored = (try? await session.client.ignoredUsers().contains(userId)) ?? false
        }

        if let identity = try? await session.client.encryption()
            .userIdentity(userId: userId, fallbackToServer: true) {
            isVerified = identity.isVerified()
        }
    }

    func ignore() async throws {
        try await session.client.ignoreUser(userId: userId)
        isIgnored = true
    }

    func unignore() async throws {
        try await session.client.unignoreUser(userId: userId)
        isIgnored = false
    }
}
