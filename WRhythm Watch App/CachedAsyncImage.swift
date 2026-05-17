//
//  CachedAsyncImage.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/25/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
#if canImport(UIKit)
        self.init(uiImage: platformImage)
#else
        self.init(nsImage: platformImage)
#endif
    }
}

#if canImport(AppKit) && !canImport(UIKit)
private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

// Image cache manager using decoded memory cache plus URLCache for persistence.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let decodedCache = NSCache<NSURL, PlatformImage>()
    private var inFlightRequests: [URL: [(PlatformImage?) -> Void]] = [:]

    private init() {
        // Configure URLCache with larger capacity for image caching
        // 50MB memory cache, 200MB disk cache
        let cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: nil
        )
        URLCache.shared = cache
        decodedCache.countLimit = 1_000
    }

    func getImage(for url: URL) -> PlatformImage? {
        if let image = decodedCache.object(forKey: url as NSURL) {
            return image
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)

        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = PlatformImage(data: cachedResponse.data) {
            decodedCache.setObject(image, forKey: url as NSURL)
            return image
        }
        return nil
    }

    func loadImage(for url: URL, completion: @escaping (PlatformImage?) -> Void) {
        if let image = getImage(for: url) {
            completion(image)
            return
        }

        if inFlightRequests[url] != nil {
            inFlightRequests[url]?.append(completion)
            return
        }

        inFlightRequests[url] = [completion]

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let loadedImage = data.flatMap(PlatformImage.init(data:))

            DispatchQueue.main.async {
                if let data, let loadedImage {
                    self.cacheImage(loadedImage, data: data, response: response, for: url)
                }

                let completions = self.inFlightRequests.removeValue(forKey: url) ?? []
                completions.forEach { $0(loadedImage) }
            }
        }.resume()
    }

    func cacheImage(_ image: PlatformImage, for url: URL) {
        guard let data = image.pngData() else { return }
        cacheImage(image, data: data, response: nil, for: url)
    }

    private func cacheImage(_ image: PlatformImage, data: Data, response: URLResponse?, for url: URL) {
        decodedCache.setObject(image, forKey: url as NSURL)
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        let cacheResponse = response ?? HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!

        let cachedResponse = CachedURLResponse(response: cacheResponse, data: data)
        URLCache.shared.storeCachedResponse(cachedResponse, for: request)
    }
}

// Custom AsyncImage with proper caching
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: PlatformImage?
    @State private var isLoading = false

    var body: some View {
        let cachedImage = url.flatMap { ImageCache.shared.getImage(for: $0) }

        Group {
            if let image = image ?? cachedImage {
                content(Image(platformImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }

    private func loadImage() {
        guard let url = url, !isLoading else { return }

        // Check cache first
        if let cachedImage = ImageCache.shared.getImage(for: url) {
            self.image = cachedImage
            return
        }

        // Load from network
        isLoading = true
        ImageCache.shared.loadImage(for: url) { loadedImage in
            if let loadedImage {
                self.image = loadedImage
            }
            isLoading = false
        }
    }
}

// Convenience initializer matching AsyncImage API
extension CachedAsyncImage where Placeholder == Color {
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
        self.placeholder = { Color.gray }
    }
}
