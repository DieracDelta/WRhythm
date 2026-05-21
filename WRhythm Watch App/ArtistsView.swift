//
//  ArtistsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var libraryDataManager: LibraryDataManager
    @State private var displayedArtists: [Artist] = []
    @State private var loadedCount = 0
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
        content
            .navigationTitle(offlineMode ? "Artists (\(downloadManager.getDownloadedArtists().count))" : "Artists (\(filteredDisplayedArtists.count))")
            .wrhythmPageBackground()
            .toolbar {
                if !offlineMode {
                    ToolbarItem(placement: .platformTopBarTrailing) {
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
                PlatformSearchSheet("Search Artists", onCancel: {
                    showingSearchSheet = false
                }) {
                    VStack(spacing: 16) {
                        TextField("Search artists", text: $searchText)
                            .platformSearchTextFieldStyle()
                            .frame(maxWidth: .infinity)

                        Button("Search") {
                            showingSearchSheet = false
                            performSearch(query: searchText)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(searchText.isEmpty)

                        Spacer()
                    }
                }
            }
            .onAppear {
                if !offlineMode {
                    libraryDataManager.fetchArtists()
                    if !libraryDataManager.artists.isEmpty && displayedArtists.isEmpty {
                        loadMoreArtists()
                    }
                }
            }
            .onChange(of: libraryDataManager.artists) { newArtists in
                if !newArtists.isEmpty && displayedArtists.isEmpty {
                    loadMoreArtists()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if offlineMode {
            offlineContent
        } else {
            onlineContent
        }
    }

    @ViewBuilder
    private var offlineContent: some View {
        // Offline mode: show downloaded artists only
        let downloadedArtists = downloadManager.getDownloadedArtists()
        let filteredArtists = searchText.isEmpty ? downloadedArtists : downloadedArtists.filter { artist in
            artist.name.localizedCaseInsensitiveContains(searchText)
        }
        if downloadedArtists.isEmpty {
            WRhythmEmptyState(
                systemImage: "arrow.down.circle",
                title: "No downloaded artists",
                message: "Download music while online to access it here"
            )
        } else if filteredArtists.isEmpty {
            WRhythmEmptyState(
                systemImage: "magnifyingglass",
                title: "No artists found",
                message: "Try a different search term"
            )
        } else {
            List {
                ForEach(Array(filteredArtists.enumerated()), id: \.element.name) { index, artist in
                    NavigationLink(destination: ArtistDetailView(artistId: "offline-\(artist.name)", artistName: artist.name)) {
                        HStack {
                            WRhythmArtworkThumbnail(coverArtId: artist.coverArt, fallbackSystemImage: "person.fill", size: 42)

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
                    .contextMenu {
                        ArtistContextMenuItems(artistId: "offline-\(artist.name)", artistName: artist.name)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search artists")
            .wrhythmListSurface()
        }
    }

    @ViewBuilder
    private var onlineContent: some View {
        if libraryDataManager.isLoadingArtists {
            WRhythmEmptyState(
                systemImage: "person.2",
                title: "Loading artists",
                message: "Please wait..."
            )
            .overlay {
                ProgressView()
                    .padding(.top, 96)
            }
        } else if !libraryDataManager.artistsErrorMessage.isEmpty {
            WRhythmEmptyState(
                systemImage: "exclamationmark.triangle.fill",
                title: "Artist Error",
                message: libraryDataManager.artistsErrorMessage,
                actionTitle: "Retry"
            ) {
                    libraryDataManager.fetchArtists(forceRefresh: true)
            }
        } else if displayedArtists.isEmpty && !libraryDataManager.artists.isEmpty {
           // Initializing display
           ProgressView()
        } else if displayedArtists.isEmpty {
            WRhythmEmptyState(
                systemImage: "person.2",
                title: "No artists found",
                message: nil,
                actionTitle: "Retry"
            ) {
                    libraryDataManager.fetchArtists(forceRefresh: true)
            }
        } else {
            List {
                ForEach(filteredDisplayedArtists) { artist in
                    NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                        HStack {
                            WRhythmArtworkThumbnail(coverArtId: artist.coverArt, fallbackSystemImage: "person.fill", size: 42)

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
                    .contextMenu {
                        ArtistContextMenuItems(artistId: artist.id, artistName: artist.name)
                    }
                    .onAppear {
                        if artist.id == displayedArtists.last?.id {
                            loadMoreArtists()
                        }
                    }
                }

                if loadedCount < libraryDataManager.artists.count {
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
            .wrhythmListSurface()
        }
    }

    private func loadMoreArtists() {
        let artists = libraryDataManager.artists
        guard loadedCount < artists.count else {
            return
        }

        let nextBatch = artists[loadedCount..<min(loadedCount + batchSize, artists.count)]
        displayedArtists.append(contentsOf: nextBatch)
        loadedCount += nextBatch.count
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
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
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
