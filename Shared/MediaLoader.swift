//
//  MediaLoader.swift
//  Crux
//

import Foundation
import MatrixRustSDK
import UIKit


///downloads MXC media adresses and sends them back as UIImages
final class MediaLoader {
    //shared static instance of MediaLoader to use
    static let shared = MediaLoader()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// Fetches a square, server-scaled thumbnail for `mxcUrl`, or `nil` if there's no
    /// avatar or the fetch fails. `pixelSize` is the desired image size *in pixels*
    func avatar(for mxcUrl: String, client: Client, pixelSize: UInt64 = 96) async -> UIImage? {
        await load(key: "\(mxcUrl)#\(pixelSize)") {
            guard let source = try? MediaSource.fromUrl(url: mxcUrl) else { return nil }
            return try? await client.getMediaThumbnail(mediaSource: source, width: pixelSize, height: pixelSize)
        }
    }

   ///smaller preview files (if availble, often not)
    func preview(from source: MediaSource,
                 uploaderThumbnail: MediaSource? = nil,
                 client: Client) async -> UIImage? {
        guard let uploaderThumbnail else {
            return await fullImage(from: source, client: client)
        }
        return await load(key: "\(uploaderThumbnail.url())#full") {
            try? await client.getMediaContent(mediaSource: uploaderThumbnail)
        }
    }

    /// Fetches the attachment at its original resolution
    func fullImage(from source: MediaSource, client: Client) async -> UIImage? {
        await load(key: "\(source.url())#full") {
            try? await client.getMediaContent(mediaSource: source)
        }
    }

    private func load(key: String, fetch: () async -> Data?) async -> UIImage? {
        let key = key as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let data = await fetch(), let image = UIImage(data: data) else { return nil }

        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }
}
