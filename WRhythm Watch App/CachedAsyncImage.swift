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

struct StoredAlbumArtworkPolicy: Sendable {
    static let enabledUserDefaultsKey = "storeAlbumArtwork"

    static func fileName(for coverArtId: String) -> String {
        let encoded = Data(coverArtId.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(encoded).img"
    }
}

enum StoredAlbumArtworkCache {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: StoredAlbumArtworkPolicy.enabledUserDefaultsKey)
    }

    @MainActor
    static func displayURL(for coverArtId: String, size: Int = 300) -> URL? {
        if let localURL = localURLIfExists(for: coverArtId) {
            return localURL
        }
        return NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: size)
    }

    static func localURLIfExists(for coverArtId: String) -> URL? {
        let url = localURL(for: coverArtId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func persistIfEnabled(coverArtId: String?, size: Int = 300) async {
        guard isEnabled, let coverArtId, localURLIfExists(for: coverArtId) == nil else { return }
        guard let remoteURL = await MainActor.run(body: {
            NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: size)
        }) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            try await persistIfEnabled(
                coverArtId: coverArtId,
                data: data,
                responseStatusCode: (response as? HTTPURLResponse)?.statusCode,
                remoteURL: remoteURL
            )
        } catch {
            print("⚠️ Failed to store album art: \(WRhythmLogRedactor.errorSummary(error))")
        }
    }

    static func persistIfEnabled(
        coverArtId: String?,
        data: Data,
        responseStatusCode: Int? = nil,
        remoteURL: URL?
    ) async throws {
        guard isEnabled, let coverArtId, localURLIfExists(for: coverArtId) == nil else { return }
        guard !data.isEmpty else { return }
        guard let image = PlatformImage(data: data) else {
            if let responseStatusCode {
                print("⚠️ Stored album art response was not decodable: \(responseStatusCode)")
            }
            return
        }

        let localURL = localURL(for: coverArtId)
        try ensureDirectory()
        try data.write(to: localURL, options: .atomic)

        await MainActor.run {
            if let remoteURL {
                ImageCache.shared.cacheImage(image, for: remoteURL)
            }
            ImageCache.shared.cacheImage(image, for: localURL)
            ImageCache.shared.cacheImage(image, forCoverArtId: coverArtId)
        }
    }

    static func removeAllStoredArtwork() {
        let directory = artworkDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func storedArtworkByteCount() -> Int64 {
        let directory = artworkDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return enumerator.compactMap { item -> Int64? in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return Int64(values.fileSize ?? 0)
        }.reduce(0, +)
    }

    private static func localURL(for coverArtId: String) -> URL {
        artworkDirectory.appendingPathComponent(StoredAlbumArtworkPolicy.fileName(for: coverArtId))
    }

    private static var artworkDirectory: URL {
#if os(macOS)
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WRhythm", isDirectory: true)
            .appendingPathComponent("AlbumArtwork", isDirectory: true)
#else
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlbumArtwork", isDirectory: true)
#endif
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }
}

// Image cache manager using decoded memory cache plus URLCache for persistence.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let decodedCache = NSCache<NSURL, PlatformImage>()
    private let decodedCoverArtCache = NSCache<NSString, PlatformImage>()
    private var inFlightRequests: [NSURL: [@MainActor (PlatformImage?) -> Void]] = [:]

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
        decodedCoverArtCache.countLimit = 1_000
    }

    func cacheKey(for url: URL) -> NSURL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url as NSURL
        }

        let volatileQueryItems: Set<String> = ["u", "t", "s", "c", "v", "f"]
        components.queryItems = components.queryItems?
            .filter { !volatileQueryItems.contains($0.name) }
            .sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name }

        return (components.url ?? url) as NSURL
    }

    func getImage(for url: URL) -> PlatformImage? {
        let cacheKey = cacheKey(for: url)
        if let image = decodedCache.object(forKey: cacheKey) {
            return image
        }

        if url.isFileURL,
           let data = try? Data(contentsOf: url),
           let image = PlatformImage(data: data) {
            decodedCache.setObject(image, forKey: cacheKey)
            return image
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)

        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = PlatformImage(data: cachedResponse.data) {
            decodedCache.setObject(image, forKey: cacheKey)
            return image
        }
        return nil
    }

    func getImage(forCoverArtId coverArtId: String?) -> PlatformImage? {
        guard let coverArtId else { return nil }
        return decodedCoverArtCache.object(forKey: coverArtId as NSString)
    }

    func loadImage(
        for url: URL,
        storedCoverArtId: String? = nil,
        completion: @escaping @MainActor (PlatformImage?) -> Void
    ) {
        if let image = getImage(for: url) {
            persistCachedArtworkIfNeeded(for: url, storedCoverArtId: storedCoverArtId)
            completion(image)
            return
        }

        let cacheKey = cacheKey(for: url)
        if inFlightRequests[cacheKey] != nil {
            inFlightRequests[cacheKey]?.append(completion)
            return
        }

        inFlightRequests[cacheKey] = [completion]

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let loadedImage = data.flatMap(PlatformImage.init(data:))

            Task { @MainActor in
                if let data, let loadedImage {
                    self.cacheImage(loadedImage, data: data, response: response, for: url, coverArtId: storedCoverArtId)
                    let responseStatusCode = (response as? HTTPURLResponse)?.statusCode
                    Task {
                        do {
                            try await StoredAlbumArtworkCache.persistIfEnabled(
                                coverArtId: storedCoverArtId,
                                data: data,
                                responseStatusCode: responseStatusCode,
                                remoteURL: url
                            )
                        } catch {
                            print("⚠️ Failed to store album art: \(WRhythmLogRedactor.errorSummary(error))")
                        }
                    }
                }

                let completions = self.inFlightRequests.removeValue(forKey: cacheKey) ?? []
                completions.forEach { $0(loadedImage) }
            }
        }.resume()
    }

    func persistCachedArtworkIfNeeded(for url: URL, storedCoverArtId: String?) {
        guard let storedCoverArtId, StoredAlbumArtworkCache.isEnabled else { return }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        guard let cachedResponse = URLCache.shared.cachedResponse(for: request) else { return }

        Task {
            do {
                try await StoredAlbumArtworkCache.persistIfEnabled(
                    coverArtId: storedCoverArtId,
                    data: cachedResponse.data,
                    responseStatusCode: (cachedResponse.response as? HTTPURLResponse)?.statusCode,
                    remoteURL: url
                )
            } catch {
                print("⚠️ Failed to store cached album art: \(WRhythmLogRedactor.errorSummary(error))")
            }
        }
    }

    func cacheImage(_ image: PlatformImage, for url: URL) {
        guard let data = image.pngData() else { return }
        cacheImage(image, data: data, response: nil, for: url)
    }

    func cacheImage(_ image: PlatformImage, forCoverArtId coverArtId: String?) {
        guard let coverArtId else { return }
        decodedCoverArtCache.setObject(image, forKey: coverArtId as NSString)
    }

    func clearAll() {
        decodedCache.removeAllObjects()
        decodedCoverArtCache.removeAllObjects()
        inFlightRequests.removeAll()
        URLCache.shared.removeAllCachedResponses()
    }

    private func cacheImage(_ image: PlatformImage, data: Data, response: URLResponse?, for url: URL, coverArtId: String? = nil) {
        cacheImage(image, forCoverArtId: coverArtId)
        decodedCache.setObject(image, forKey: cacheKey(for: url))
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
    let storedCoverArtId: String?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: PlatformImage?
    @State private var loadedCacheKey: NSURL?
    @State private var loadingCacheKey: NSURL?

    var body: some View {
        let cacheKey = url.map { ImageCache.shared.cacheKey(for: $0) }
        let cachedImage = ImageCache.shared.getImage(forCoverArtId: storedCoverArtId)
            ?? url.flatMap { ImageCache.shared.getImage(for: $0) }
        let stateImage = loadedCacheKey == cacheKey ? image : nil

        Group {
            if let image = stateImage ?? cachedImage {
                content(Image(platformImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            guard loadedCacheKey != url.map({ ImageCache.shared.cacheKey(for: $0) }) else {
                return
            }
            image = nil
            loadedCacheKey = nil
            loadingCacheKey = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard let url else {
            image = nil
            loadedCacheKey = nil
            loadingCacheKey = nil
            return
        }

        let cacheKey = ImageCache.shared.cacheKey(for: url)

        // Check cache first
        if let cachedImage = ImageCache.shared.getImage(forCoverArtId: storedCoverArtId)
            ?? ImageCache.shared.getImage(for: url) {
            ImageCache.shared.persistCachedArtworkIfNeeded(for: url, storedCoverArtId: storedCoverArtId)
            self.image = cachedImage
            self.loadedCacheKey = cacheKey
            self.loadingCacheKey = nil
            return
        }

        guard loadingCacheKey != cacheKey else { return }

        // Load from network
        loadingCacheKey = cacheKey
        ImageCache.shared.loadImage(for: url, storedCoverArtId: storedCoverArtId) { loadedImage in
            guard self.url.map({ ImageCache.shared.cacheKey(for: $0) }) == cacheKey else {
                if self.loadingCacheKey == cacheKey {
                    self.loadingCacheKey = nil
                }
                return
            }

            if let loadedImage {
                self.image = loadedImage
                self.loadedCacheKey = cacheKey
            }
            self.loadingCacheKey = nil
        }
    }
}

// Convenience initializer matching AsyncImage API
extension CachedAsyncImage where Placeholder == Color {
    init(url: URL?, storedCoverArtId: String? = nil, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.storedCoverArtId = storedCoverArtId
        self.content = content
        self.placeholder = { Color.gray }
    }
}
