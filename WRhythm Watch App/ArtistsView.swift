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
    @State private var presentedSheet: ArtistsSheet?
    @State private var searchTask: Task<Void, Never>?
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
                                searchTask?.cancel()
                                searchResults = []
                                isSearching = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Button(action: {
                                presentedSheet = .search
                            }) {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .search:
                PlatformSearchSheet("Search Artists", onCancel: {
                    presentedSheet = nil
                }) {
                    VStack(spacing: 16) {
                        TextField("Search artists", text: $searchText)
                            .platformSearchTextFieldStyle()
                            .frame(maxWidth: .infinity)

                        Button("Search") {
                            presentedSheet = nil
                            performSearch(query: searchText)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(searchText.isEmpty)

                        Spacer()
                    }
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
            .onChange(of: libraryDataManager.artists) { _, newArtists in
                if !newArtists.isEmpty && displayedArtists.isEmpty {
                    loadMoreArtists()
                }
            }
            .onDisappear {
                searchTask?.cancel()
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
                    let albumCount = downloadManager.getDownloadedAlbums().filter { $0.artist == artist.name }.count
                    NavigationLink(destination: ArtistDetailView(artistId: "offline-\(artist.name)", artistName: artist.name)) {
                        WRhythmCollectionRow(
                            title: artist.name,
                            subtitle: albumCount > 0 ? "\(albumCount) album\(albumCount == 1 ? "" : "s")" : nil,
                            coverArtId: artist.coverArt,
                            fallbackSystemImage: "person.fill",
                            tint: .indigo
                        ) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .wrhythmArtistActions(artistId: "offline-\(artist.name)", artistName: artist.name)
                }
            }
            .searchable(text: $searchText, prompt: "Search artists")
            .wrhythmListSurface()
        }
    }

    @ViewBuilder
    private var onlineContent: some View {
        if libraryDataManager.isLoadingArtists {
            WRhythmLoadingState(
                systemImage: "person.2",
                title: "Loading artists",
                message: "Please wait..."
            )
        } else if !libraryDataManager.artistsErrorMessage.isEmpty {
            WRhythmErrorState(
                title: "Artist Error",
                message: libraryDataManager.artistsErrorMessage
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
                        WRhythmCollectionRow(
                            title: artist.name,
                            subtitle: artist.albumCount.map { "\($0) albums" },
                            coverArtId: artist.coverArt,
                            fallbackSystemImage: "person.fill",
                            tint: .indigo
                        )
                    }
                    .wrhythmArtistActions(artistId: artist.id, artistName: artist.name)
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
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard SearchResultOwnershipPolicy.shouldApply(
                query: query,
                currentQuery: searchText,
                isCancelled: Task.isCancelled
            ) else { return }

            isSearching = true

            do {
                let result = try await NavidromeAPI.shared.search(query: query)
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: query,
                    currentQuery: searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.searchResults = result.artist ?? []
                self.isSearching = false
            } catch {
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: query,
                    currentQuery: searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.searchResults = []
                self.isSearching = false
            }
        }
    }
}

private enum ArtistsSheet: String, Identifiable {
    case search

    var id: String { rawValue }
}

#Preview {
    NavigationView {
        ArtistsView()
    }
}
