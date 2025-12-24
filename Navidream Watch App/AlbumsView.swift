//
//  AlbumsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct AlbumsView: View {
    @State private var albums: [AlbumSummary] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var offset = 0
    @State private var hasMore = true
    @State private var loadStartTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var downloadProgress: Double = 0
    @State private var downloadedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    private let pageSize = 20

    private var filteredAlbums: [AlbumSummary] {
        if offlineMode {
            return albums.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
        }
        return albums
    }

    var body: some View {
        Group {
            if offlineMode {
                // Offline mode: show downloaded albums only
                let downloadedAlbums = downloadManager.getDownloadedAlbums()
                if downloadedAlbums.isEmpty {
                    VStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No downloaded albums")
                            .font(.headline)
                        Text("Download albums while online to access them here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(downloadedAlbums, id: \.id) { album in
                            NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                HStack {
                                    if let coverArtId = album.coverArt,
                                       let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                        AsyncImage(url: coverURL) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Color.gray
                                        }
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(4)
                                    }

                                    VStack(alignment: .leading) {
                                        Text(album.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        if let artist = album.artist {
                                            Text(artist)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            } else if albums.isEmpty && isLoading {
                VStack(spacing: 8) {
                    ProgressView("Loading albums...", value: downloadProgress, total: 1.0)

                    Text("⏱️ \(formatElapsedTime(elapsedTime))")
                        .font(.headline)
                        .foregroundColor(.blue)

                    if totalBytes > 0 {
                        Text("📦 \(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes)) (\(Int(downloadProgress * 100))%)")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if downloadedBytes > 0 {
                        Text("📦 Downloaded \(formatBytes(downloadedBytes))")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if elapsedTime < 3 {
                        Text("Fetching from server...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if elapsedTime < 10 {
                        Text("Network seems slow...")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        Text("Still waiting for response...")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Button("Cancel") {
                        stopTimer()
                        isLoading = false
                        errorMessage = "Loading cancelled"
                    }
                    .padding(.top, 4)
                    .font(.caption)
                }
            } else if !errorMessage.isEmpty && albums.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadInitialAlbums()
                    }
                }
            } else if albums.isEmpty {
                VStack {
                    Text("No albums found")
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadInitialAlbums()
                    }
                }
            } else {
                List {
                    ForEach(filteredAlbums) { album in
                        NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                            HStack {
                                if let coverArtId = album.coverArt,
                                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                    AsyncImage(url: coverURL) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray
                                    }
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(4)
                                }

                                VStack(alignment: .leading) {
                                    Text(album.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let artist = album.artist {
                                        Text(artist)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            if album.id == albums.last?.id && hasMore && !isLoading {
                                loadMoreAlbums()
                            }
                        }
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("Albums")
        .onAppear {
            if !offlineMode && albums.isEmpty {
                loadInitialAlbums()
            }
        }
    }

    private func loadInitialAlbums() {
        albums = []
        offset = 0
        hasMore = true
        errorMessage = ""
        loadStartTime = Date()
        elapsedTime = 0
        loadMoreAlbums()
    }

    private func loadMoreAlbums() {
        guard !isLoading && hasMore else {
            print("⏭️ Skipping load: isLoading=\(isLoading), hasMore=\(hasMore)")
            return
        }

        isLoading = true

        // Start timer only for initial load
        if offset == 0 {
            loadStartTime = Date()
            elapsedTime = 0
            startTimer()
        }

        print("🎵 AlbumsView: Loading albums at offset \(offset)...")
        print("🔑 API authenticated: \(NavidromeAPI.shared.isAuthenticated)")

        Task {
            do {
                print("📞 Calling getAlbumList API...")
                let progressCallback: (Double, Int64, Int64) -> Void = { progress, received, total in
                    if offset == 0 {
                        self.downloadProgress = progress
                        self.downloadedBytes = received
                        self.totalBytes = total
                    }
                }
                let fetchedAlbums = try await NavidromeAPI.shared.getAlbumList(
                    type: "newest",
                    size: pageSize,
                    offset: offset,
                    progressHandler: offset == 0 ? progressCallback : nil
                )

                await MainActor.run {
                    if offset == 0 {
                        stopTimer()
                        let totalTime = Date().timeIntervalSince(loadStartTime ?? Date())
                        print("🎵 AlbumsView: Successfully loaded \(fetchedAlbums.count) albums in \(String(format: "%.1f", totalTime))s")
                    } else {
                        print("🎵 AlbumsView: Successfully loaded \(fetchedAlbums.count) more albums")
                    }

                    if fetchedAlbums.count < pageSize {
                        hasMore = false
                        print("📭 No more albums to load")
                    }

                    self.albums.append(contentsOf: fetchedAlbums)
                    self.offset += fetchedAlbums.count
                    self.isLoading = false

                    print("✅ Total albums now: \(self.albums.count)")
                }
            } catch {
                await MainActor.run {
                    stopTimer()
                    print("❌ AlbumsView: Failed to load albums")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                    print("❌ Error: \(error)")
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.hasMore = false
                }
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            Task { @MainActor in
                if let startTime = self.loadStartTime {
                    self.elapsedTime = Date().timeIntervalSince(startTime)
                }
            }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatElapsedTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        if mins > 0 {
            return String(format: "%d:%02d.%d", mins, secs, tenths)
        } else {
            return String(format: "%d.%d s", secs, tenths)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationView {
        AlbumsView()
    }
}
