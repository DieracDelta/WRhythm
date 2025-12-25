//
//  ArtistsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ArtistsView: View {
    @State private var artists: [Artist] = []
    @State private var isLoading = false  // FIX: Was true, preventing initial load!
    @State private var errorMessage = ""
    @State private var displayedArtists: [Artist] = []
    @State private var loadedCount = 0
    @State private var loadStartTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var downloadProgress: Double = 0
    @State private var downloadedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var searchText = ""
    @State private var searchResults: [Artist] = []
    @State private var isSearching = false
    @State private var showingSearchSheet = false
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    private let batchSize = 20

    private var filteredDisplayedArtists: [Artist] {
        if offlineMode {
            let downloadedArtists = displayedArtists.filter { artist in
                downloadManager.downloadedSongs.values.contains { song in
                    song.artist == artist.name
                }
            }
            if searchText.isEmpty {
                return downloadedArtists
            }
            return downloadedArtists.filter { artist in
                artist.name.localizedCaseInsensitiveContains(searchText)
            }
        } else {
            // Online mode: use search results if searching, otherwise show batch-loaded list
            if !searchText.isEmpty {
                return searchResults
            }
            return displayedArtists
        }
    }

    var body: some View {
        Group {
            if offlineMode {
                // Offline mode: show downloaded artists only
                let downloadedArtists = downloadManager.getDownloadedArtists()
                if downloadedArtists.isEmpty {
                    VStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No downloaded artists")
                            .font(.headline)
                        Text("Download music while online to access it here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(Array(downloadedArtists.enumerated()), id: \.element.name) { index, artist in
                            NavigationLink(destination: ArtistDetailView(artistId: "offline-\(artist.name)", artistName: artist.name)) {
                                HStack {
                                    if let coverArtId = artist.coverArt,
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
                                        .id(coverURL)
                                    }

                                    VStack(alignment: .leading) {
                                        Text(artist.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        let albumCount = downloadManager.getDownloadedAlbums().filter { $0.artist == artist.name }.count
                                        if albumCount > 0 {
                                            Text("\(albumCount) album\(albumCount == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
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
            } else if isLoading {
                VStack(spacing: 8) {
                    ProgressView("Loading all artists...", value: downloadProgress, total: 1.0)

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
                    } else if elapsedTime < 5 {
                        Text("Fetching from server...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if elapsedTime < 15 {
                        Text("Large library detected...")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else if elapsedTime < 30 {
                        Text("Still loading, almost there...")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        Text("This is taking longer than expected")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Text("(One-time load)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button("Cancel") {
                        stopTimer()
                        isLoading = false
                        errorMessage = "Loading cancelled"
                    }
                    .padding(.top, 4)
                    .font(.caption)
                }
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadArtists()
                    }
                }
            } else if displayedArtists.isEmpty {
                VStack {
                    Text("No artists found")
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadArtists()
                    }
                }
            } else {
                List {
                    ForEach(filteredDisplayedArtists) { artist in
                        NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                            HStack {
                                if let coverArtId = artist.coverArt,
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
                                    .id(coverURL)
                                }

                                VStack(alignment: .leading) {
                                    Text(artist.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let albumCount = artist.albumCount {
                                        Text("\(albumCount) albums")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            if artist.id == displayedArtists.last?.id {
                                loadMoreArtists()
                            }
                        }
                    }

                    if loadedCount < artists.count {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .onAppear {
                            loadMoreArtists()
                        }
                    }
                }
            }
        }
        .navigationTitle(offlineMode ? "Artists (\(downloadManager.getDownloadedArtists().count))" : "Artists (\(filteredDisplayedArtists.count))")
        .toolbar {
            if !offlineMode {
                ToolbarItem(placement: .topBarTrailing) {
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: {
                            showingSearchSheet = true
                        }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingSearchSheet) {
            NavigationView {
                VStack(spacing: 16) {
                    TextField("Search artists", text: $searchText)
                        .padding()

                    Button("Search") {
                        showingSearchSheet = false
                        performSearch(query: searchText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.isEmpty)

                    Spacer()
                }
                .navigationTitle("Search Artists")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingSearchSheet = false
                        }
                    }
                }
            }
        }
        .onAppear {
            print("👀 ArtistsView appeared")
            print("👀 Current state - isLoading: \(isLoading), artists count: \(artists.count), displayed: \(displayedArtists.count)")
            if !offlineMode && artists.isEmpty && !isLoading {
                print("👀 Triggering load because artists is empty")
                loadArtists()
            } else {
                print("👀 Not loading - offlineMode: \(offlineMode), artists: \(artists.count), isLoading: \(isLoading)")
            }
        }
    }

    private func loadArtists() {
        print("🔵 loadArtists() called")
        print("🔵 Current isLoading state: \(isLoading)")

        guard !isLoading else {
            print("⚠️ Already loading, skipping")
            return
        }

        print("🔵 Setting isLoading = true")
        isLoading = true
        errorMessage = ""
        displayedArtists = []
        loadedCount = 0
        loadStartTime = Date()
        elapsedTime = 0
        downloadProgress = 0
        downloadedBytes = 0
        totalBytes = 0

        print("🔵 Starting timer")
        startTimer()

        print("🎵 ArtistsView: Starting to load artists...")
        print("🔑 API authenticated: \(NavidromeAPI.shared.isAuthenticated)")

        Task {
            do {
                print("📞 Calling getArtists API...")
                let fetchedArtists = try await NavidromeAPI.shared.getArtists { progress, received, total in
                    print("📊 Progress callback - progress: \(progress), received: \(received), total: \(total)")
                    Task { @MainActor in
                        print("📊 Updating UI state on main actor")
                        self.downloadProgress = progress
                        self.downloadedBytes = received
                        self.totalBytes = total
                        print("📊 UI state updated - progress: \(self.downloadProgress)")
                    }
                }
                print("🎵 API call returned with \(fetchedArtists.count) artists")
                await MainActor.run {
                    print("🔵 Back on MainActor after API call")
                    stopTimer()
                    let totalTime = Date().timeIntervalSince(loadStartTime ?? Date())
                    print("🎵 ArtistsView: Successfully loaded \(fetchedArtists.count) artists in \(String(format: "%.1f", totalTime))s")
                    print("🔵 Setting artists array")
                    self.artists = fetchedArtists
                    print("🔵 Setting isLoading = false")
                    self.isLoading = false

                    // Load first batch immediately
                    if !fetchedArtists.isEmpty {
                        print("🔵 Loading first batch of artists for display")
                        loadMoreArtists()
                    } else {
                        print("⚠️ No artists returned from API")
                    }
                    print("🔵 Done with MainActor block")
                }
            } catch {
                print("❌ Exception caught in loadArtists")
                await MainActor.run {
                    stopTimer()
                    print("❌ ArtistsView: Failed to load artists")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                    print("❌ Error: \(error)")
                    self.errorMessage = "Failed to load artists: \(error.localizedDescription)"
                    self.isLoading = false
                    print("❌ Error state set")
                }
            }
        }
        print("🔵 loadArtists() Task created")
    }

    private func startTimer() {
        print("⏱️ Starting timer")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            Task { @MainActor in
                if let startTime = self.loadStartTime {
                    self.elapsedTime = Date().timeIntervalSince(startTime)
                    if Int(self.elapsedTime) % 5 == 0 && self.elapsedTime.truncatingRemainder(dividingBy: 1) < 0.15 {
                        print("⏱️ Timer tick - elapsed: \(String(format: "%.1f", self.elapsedTime))s")
                    }
                }
            }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
            print("⏱️ Timer added to RunLoop")
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

    private func loadMoreArtists() {
        print("🟢 loadMoreArtists() called - loadedCount: \(loadedCount), artists.count: \(artists.count)")
        guard loadedCount < artists.count else {
            print("🟢 No more artists to load")
            return
        }

        let nextBatch = artists[loadedCount..<min(loadedCount + batchSize, artists.count)]
        print("📦 Loading batch: \(loadedCount) to \(loadedCount + nextBatch.count)")

        displayedArtists.append(contentsOf: nextBatch)
        loadedCount += nextBatch.count

        print("✅ Now displaying \(displayedArtists.count) of \(artists.count) artists")
        print("✅ UI should now show \(displayedArtists.count) artists")
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard query == searchText else { return }

            isSearching = true

            do {
                let result = try await NavidromeAPI.shared.search(query: query)
                await MainActor.run {
                    self.searchResults = result.artist ?? []
                    self.isSearching = false
                    print("🔍 Artist search results: \(self.searchResults.count) artists")
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                    print("❌ Artist search error: \(error)")
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        ArtistsView()
    }
}
