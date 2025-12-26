//
//  CachedAsyncImage.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/25/25.
//

import SwiftUI

// Image cache manager using URLCache for persistent caching
class ImageCache {
    static let shared = ImageCache()

    private init() {
        // Configure URLCache with larger capacity for image caching
        // 50MB memory cache, 200MB disk cache
        let cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "image_cache"
        )
        URLCache.shared = cache
    }

    func getImage(for url: URL) -> UIImage? {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)

        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            return image
        }
        return nil
    }

    func cacheImage(_ image: UIImage, for url: URL) {
        guard let data = image.pngData() else { return }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!

        let cachedResponse = CachedURLResponse(response: response, data: data)
        URLCache.shared.storeCachedResponse(cachedResponse, for: request)
    }
}

// Custom AsyncImage with proper caching
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
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
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let loadedImage = UIImage(data: data) else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }

            // Cache the image
            ImageCache.shared.cacheImage(loadedImage, for: url)

            DispatchQueue.main.async {
                self.image = loadedImage
                isLoading = false
            }
        }.resume()
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
