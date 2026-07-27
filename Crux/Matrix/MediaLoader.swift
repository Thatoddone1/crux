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

    private init() {}

    /// Fetches a square, server-scaled thumbnail for `mxcUrl`, or `nil` if there's no
    /// avatar or the fetch fails. `pixelSize` is the desired image size *in pixels*
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
