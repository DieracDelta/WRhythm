//
//  CachedAsyncImage.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/25/25.
//

import SwiftUI

// Image cache manager using URLCache for persistent caching
class ImageCache {
    static let shared = ImageCache()

    private init() {
        // Configure URLCache with capacity based on battery saver mode
        updateCacheSize()

        // Listen for battery saver changes
        NotificationCenter.default.addObserver(
            forName: .batterySaverModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCacheSize()
        }
    }

    private func updateCacheSize() {
        // Reduce cache size in battery saver mode
        let memoryCapacity = BatterySaverManager.shared.isActive ? 10 * 1024 * 1024 : 50 * 1024 * 1024
        let diskCapacity = BatterySaverManager.shared.isActive ? 50 * 1024 * 1024 : 200 * 1024 * 1024

        let cache = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "image_cache"
        )
        URLCache.shared = cache

        print("🔋 Updated image cache: \(memoryCapacity / 1024 / 1024)MB memory, \(diskCapacity / 1024 / 1024)MB disk")
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
    @ObservedObject private var batterySaver = BatterySaverManager.shared

    var body: some View {
        Group {
            if batterySaver.isActive {
                // Battery saver mode: show placeholder with battery icon
                batterySaverPlaceholder
            } else if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onChange(of: batterySaver.isActive) { active in
            if !active && image == nil {
                loadImage() // Load image when battery saver disabled
            } else if active {
                image = nil // Clear image when battery saver enabled
            }
        }
    }

    private var batterySaverPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "bolt.slash.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            )
    }

    private func loadImage() {
        guard let url = url, !isLoading, !batterySaver.isActive else { return }

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
