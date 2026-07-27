//
//  MediaLoader.swift
//  Crux
//

import Foundation
import MatrixRustSDK
import UIKit

/// Downloads and caches avatar images from `mxc://` URLs.
///
/// Room/user avatars only ever surface as `mxc://` identifiers (from
/// `Room.avatarUrl()`, `UserProfile.avatarUrl`, etc.) — that's a pointer into
/// the homeserver's (authenticated) media repo, not something `AsyncImage` can
/// load directly. This resolves one through the `Client` that owns the
/// session and keeps the result around so scrolling a list doesn't refetch.
final class MediaLoader {
    static let shared = MediaLoader()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    /// Fetches a square, server-scaled thumbnail for `mxcUrl`, or `nil` if there's no
    /// avatar or the fetch fails. `pixelSize` is the desired image size *in pixels*
    /// (multiply by the view's display scale, since this has no access to it);
    /// images are cached per `mxcUrl` + `pixelSize`.
    func avatar(for mxcUrl: String, client: Client, pixelSize: UInt64 = 96) async -> UIImage? {
        let key = "\(mxcUrl)#\(pixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = try? MediaSource.fromUrl(url: mxcUrl),
              let data = try? await client.getMediaThumbnail(mediaSource: source, width: pixelSize, height: pixelSize),
              let image = UIImage(data: data) else { return nil }

        cache.setObject(image, forKey: key)
        return image
    }
}
