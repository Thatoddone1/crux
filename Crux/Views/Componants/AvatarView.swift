//
//  AvatarView.swift
//  Crux
//

import SwiftUI

/// A circular MXC avatar with a person glyph as fallback. Used for rooms in the
/// deck header and for message senders.
struct AvatarView: View {
    let avatarUrl: String?
    var size: CGFloat = 36
    /// Drawn as a red corner badge when above zero.
    var unreadCount: Int = 0

    @Environment(UserSession.self) private var session: UserSession?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(alignment: .topTrailing) { unreadBadge }
        .task(id: avatarUrl) {
            guard let avatarUrl, let session else { image = nil; return }
            image = await MediaLoader.shared.avatar(for: avatarUrl, client: session.client)
        }
    }

    @ViewBuilder private var unreadBadge: some View {
        if unreadCount > 0 {
            Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(.red, in: .capsule)
                .offset(x: 4, y: -4)
        }
    }
}
