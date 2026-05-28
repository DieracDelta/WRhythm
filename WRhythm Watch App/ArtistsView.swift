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
    @State private var sortOption: ArtistSortOption = .nameAscending
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
            guard !searchText.isEmpty else {
                return downloadedArtists
            }
            return downloadedArtists.filter { artist in
                artist.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        if !searchText.isEmpty {
            return searchResults
        }
        return displayedArtists
    }

    var body: some View {
        content
            .navigationTitle(offlineMode ? "Artists (\(downloadManager.getDownloadedArtists().count))" : "Artists (\(filteredDisplayedArtists.count))")
            .wrhythmPageBackground()
            .toolbar {
                ToolbarItemGroup(placement: .platformTopBarTrailing) {
                    WRhythmSortMenu(selection: $sortOption)

                    if !offlineMode {
                        WRhythmSearchToolbarButton(
                            hasQuery: !searchText.isEmpty,
                            clear: {
                                searchText = ""
                                searchTask?.cancel()
                                searchResults = []
                                isSearching = false
                            },
                            search: {
                                presentedSheet = .search
                            }
                        )
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
        let downloadedArtists = downloadManager.getDownloadedArtists()
        let filteredArtists = searchText.isEmpty ? downloadedArtists : downloadedArtists.filter { artist in
            artist.name.localizedCaseInsensitiveContains(searchText)
        }
        let sortedArtists = sortedDownloadedArtists(filteredArtists)

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
            ScrollView {
                VStack(spacing: WRhythmSpacing.sm) {
#if os(iOS)
                    PhoneSearchSubmenuHeader(
                        title: "Offline Artists",
                        subtitle: "Artists available from downloaded music.",
                        systemImage: "person.2",
                        countText: artistCountText(sortedArtists.count),
                        queryText: searchText
                    )
#endif

                    WRhythmCard {
                        SlidingRenderWindowForEach(sortedArtists, estimatedRowHeight: 64, resetToken: sortOption) { _, artist in
                            let albumCount = downloadedAlbumCount(for: artist.name)
                            NavigationLink(destination: ArtistDetailView(artistId: "offline-\(artist.name)", artistName: artist.name)) {
                                WRhythmCollectionRow(
                                    title: artist.name,
                                    subtitle: albumCount > 0 ? "\(albumCount) album\(albumCount == 1 ? "" : "s")" : nil,
                                    coverArtId: artist.coverArt,
                                    fallbackSystemImage: "person.fill",
                                    tint: WRhythmTheme.artist
                                ) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(WRhythmTypography.metadata)
                                        .foregroundColor(WRhythmTheme.success)
                                }
                            }
                            .buttonStyle(.plain)
                            .wrhythmArtistActions(artistId: "offline-\(artist.name)", artistName: artist.name)

                            if artist.name != sortedArtists.last?.name {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
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
            let sortedArtists = sortOption.sorted(filteredDisplayedArtists)
            ScrollView {
                VStack(spacing: WRhythmSpacing.sm) {
#if os(iOS)
                    PhoneSearchSubmenuHeader(
                        title: "Artists",
                        subtitle: searchText.isEmpty ? "Browse performers across your library." : "Artists matching your search.",
                        systemImage: "person.2",
                        countText: artistCountText(sortedArtists.count),
                        queryText: searchText
                    )
#endif

                    WRhythmCard {
                        SlidingRenderWindowForEach(sortedArtists, estimatedRowHeight: 64, resetToken: sortOption) { _, artist in
                            NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                                WRhythmCollectionRow(
                                    title: artist.name,
                                    subtitle: artist.albumCount.map { "\($0) albums" },
                                    coverArtId: artist.coverArt,
                                    fallbackSystemImage: "person.fill",
                                    tint: WRhythmTheme.artist
                                )
                            }
                            .buttonStyle(.plain)
                            .wrhythmArtistActions(artistId: artist.id, artistName: artist.name)
                            .onAppear {
                                if artist.id == displayedArtists.last?.id {
                                    loadMoreArtists()
                                }
                            }

                            if artist.id != sortedArtists.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }

                    if loadedCount < libraryDataManager.artists.count {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                loadMoreArtists()
                            }
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

    private func artistCountText(_ count: Int) -> String {
        count == 1 ? "1 artist" : "\(count) artists"
    }

    private func sortedDownloadedArtists(_ artists: [(name: String, coverArt: String?)]) -> [(name: String, coverArt: String?)] {
        artists.sorted { lhs, rhs in
            let lhsAlbumCount = downloadedAlbumCount(for: lhs.name)
            let rhsAlbumCount = downloadedAlbumCount(for: rhs.name)

            switch sortOption {
            case .nameAscending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return rhs.name.localizedCaseInsensitiveCompare(lhs.name) == .orderedAscending
            case .mostAlbums:
                return lhsAlbumCount == rhsAlbumCount
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhsAlbumCount > rhsAlbumCount
            case .fewestAlbums:
                return lhsAlbumCount == rhsAlbumCount
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhsAlbumCount < rhsAlbumCount
            }
        }
    }

    private func downloadedAlbumCount(for artistName: String) -> Int {
        downloadManager.getDownloadedAlbums().filter { $0.artist == artistName }.count
    }

    private func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
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
                searchResults = result.artist ?? []
                isSearching = false
            } catch {
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: query,
                    currentQuery: searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                searchResults = []
                isSearching = false
            }
        }
    }
}

private enum ArtistsSheet: String, Identifiable {
    case search

    var id: String { rawValue }
}

#Preview {
    NavigationStack {
        ArtistsView()
    }
}
