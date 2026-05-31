//
//  AlbumsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var libraryDataManager: LibraryDataManager
    @State private var searchText = ""
    @State private var searchResults: [AlbumSummary] = []
    @State private var isSearching = false
    @State private var presentedSheet: AlbumsSheet?
    @State private var searchTask: Task<Void, Never>?
    @State private var sortOption: AlbumSortOption = .titleAscending
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var filteredAlbums: [AlbumSummary] {
        if offlineMode {
            let downloadedAlbums = libraryDataManager.albums.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
            guard !searchText.isEmpty else {
                return downloadedAlbums
            }
            return downloadedAlbums.filter { album in
                album.name.localizedCaseInsensitiveContains(searchText) ||
                    (album.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        if !searchText.isEmpty {
            return searchResults
        }
        return libraryDataManager.albums
    }

    private var sortedFilteredAlbums: [AlbumSummary] {
        if !offlineMode, searchText.isEmpty, sortOption.isServerOrderedAlbumList {
            return filteredAlbums
        }
        return sortOption.sorted(filteredAlbums)
    }

    var body: some View {
        content
            .navigationTitle("Albums")
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
                    PlatformSearchSheet("Search Albums", onCancel: {
                        presentedSheet = nil
                    }) {
                        VStack(spacing: 16) {
                            TextField("Search albums", text: $searchText)
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
                if !offlineMode && libraryDataManager.albums.isEmpty {
                    loadAlbums(forceRefresh: false)
                }
            }
            .onChange(of: sortOption) { _, _ in
                guard !offlineMode, searchText.isEmpty else { return }
                loadAlbums(forceRefresh: true)
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
        let downloadedAlbums = downloadManager.getDownloadedAlbums()
        let filteredAlbums = searchText.isEmpty ? downloadedAlbums : downloadedAlbums.filter { album in
            album.name.localizedCaseInsensitiveContains(searchText) ||
                (album.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        let sortedAlbums = sortedDownloadedAlbums(filteredAlbums)

        if downloadedAlbums.isEmpty {
            WRhythmEmptyState(
                systemImage: "arrow.down.circle",
                title: "No downloaded albums",
                message: "Download albums while online to access them here"
            )
        } else if filteredAlbums.isEmpty {
            WRhythmEmptyState(
                systemImage: "magnifyingglass",
                title: "No albums found",
                message: "Try a different search term"
            )
        } else {
            ScrollView {
                VStack(spacing: WRhythmSpacing.sm) {
#if os(iOS)
                    PhoneSearchSubmenuHeader(
                        title: "Offline Albums",
                        subtitle: "Albums available from downloaded music.",
                        systemImage: "square.stack",
                        countText: albumCountText(sortedAlbums.count),
                        queryText: searchText
                    )
#endif

                    WRhythmCard {
                        SlidingRenderWindowForEach(sortedAlbums, estimatedRowHeight: 64, resetToken: sortOption) { _, album in
                            NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                WRhythmCollectionRow(
                                    title: album.name,
                                    subtitle: album.artist,
                                    coverArtId: album.coverArt,
                                    fallbackSystemImage: "square.stack",
                                    tint: WRhythmTheme.album
                                ) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(WRhythmTypography.metadata)
                                        .foregroundColor(WRhythmTheme.success)
                                }
                            }
                            .buttonStyle(.plain)
                            .wrhythmAlbumActions(albumId: album.id, albumName: album.name)

                            if album.id != sortedAlbums.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search albums")
            .wrhythmListSurface()
        }
    }

    @ViewBuilder
    private var onlineContent: some View {
        if libraryDataManager.albums.isEmpty && libraryDataManager.isLoadingAlbums {
            WRhythmLoadingState(
                systemImage: "square.stack",
                title: "Loading albums",
                message: "Please wait..."
            )
        } else if !libraryDataManager.albumsErrorMessage.isEmpty && libraryDataManager.albums.isEmpty {
            WRhythmErrorState(
                title: "Album Error",
                message: libraryDataManager.albumsErrorMessage
            ) {
                loadAlbums(forceRefresh: true)
            }
        } else if libraryDataManager.albums.isEmpty {
            WRhythmEmptyState(
                systemImage: "square.stack",
                title: "No albums found",
                message: nil,
                actionTitle: "Retry"
            ) {
                loadAlbums(forceRefresh: true)
            }
        } else {
            ScrollView {
                VStack(spacing: WRhythmSpacing.sm) {
#if os(iOS)
                    PhoneSearchSubmenuHeader(
                        title: "Albums",
                        subtitle: searchText.isEmpty ? "Browse records across your library." : "Albums matching your search.",
                        systemImage: "square.stack",
                        countText: albumCountText(sortedFilteredAlbums.count),
                        queryText: searchText
                    )
#endif

                    if libraryDataManager.hasEarlierAlbums, libraryDataManager.isLoadingAlbums {
                        ProgressView("Loading earlier albums")
                            .frame(maxWidth: .infinity)
                    }

                    WRhythmCard {
                        SlidingRenderWindowForEach(sortedFilteredAlbums, estimatedRowHeight: 64, resetToken: sortOption) { _, album in
                            NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                WRhythmCollectionRow(
                                    title: album.name,
                                    subtitle: album.artist,
                                    detail: album.year.map(String.init),
                                    coverArtId: album.coverArt,
                                    fallbackSystemImage: "square.stack",
                                    tint: WRhythmTheme.album
                                )
                            }
                            .buttonStyle(.plain)
                            .wrhythmAlbumActions(albumId: album.id, albumName: album.name)
                            .onAppear {
                                if shouldFetchEarlierAlbumPage(for: album) {
                                    libraryDataManager.fetchPreviousAlbums()
                                }

                                if shouldFetchLaterAlbumPage(for: album) {
                                    libraryDataManager.fetchMoreAlbums()
                                }
                            }

                            if album.id != sortedFilteredAlbums.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }

                    if libraryDataManager.isLoadingAlbums {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .wrhythmListSurface()
        }
    }

    private func albumCountText(_ count: Int) -> String {
        count == 1 ? "1 album" : "\(count) albums"
    }

    private func loadAlbums(forceRefresh: Bool) {
        if sortOption.requiresCompleteAlbumList {
            libraryDataManager.fetchAllAlbums(forceRefresh: forceRefresh, type: sortOption.serverAlbumListType)
        } else {
            libraryDataManager.fetchInitialAlbums(forceRefresh: forceRefresh, type: sortOption.serverAlbumListType)
        }
    }

    private func shouldFetchEarlierAlbumPage(for album: AlbumSummary) -> Bool {
        guard searchText.isEmpty,
              sortOption.isServerOrderedAlbumList,
              libraryDataManager.hasEarlierAlbums,
              !libraryDataManager.isLoadingAlbums else {
            return false
        }
        return album.id == libraryDataManager.albums.first?.id
    }

    private func shouldFetchLaterAlbumPage(for album: AlbumSummary) -> Bool {
        guard searchText.isEmpty,
              sortOption.isServerOrderedAlbumList,
              libraryDataManager.hasMoreAlbums,
              !libraryDataManager.isLoadingAlbums else {
            return false
        }
        return album.id == libraryDataManager.albums.last?.id
    }

    private func sortedDownloadedAlbums(_ albums: [(id: String, name: String, artist: String?, coverArt: String?)]) -> [(id: String, name: String, artist: String?, coverArt: String?)] {
        albums.sorted { lhs, rhs in
            switch sortOption {
            case .titleAscending, .newest, .mostTracks:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .titleDescending:
                return rhs.name.localizedCaseInsensitiveCompare(lhs.name) == .orderedAscending
            case .artistAscending:
                return (lhs.artist ?? "").localizedCaseInsensitiveCompare(rhs.artist ?? "") == .orderedAscending
            case .artistDescending:
                return (rhs.artist ?? "").localizedCaseInsensitiveCompare(lhs.artist ?? "") == .orderedAscending
            }
        }
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
                searchResults = result.album ?? []
                isSearching = false
                print("🔍 Album search results: \(searchResults.count) albums")
            } catch {
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: query,
                    currentQuery: searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                searchResults = []
                isSearching = false
                print("❌ Album search error: \(error)")
            }
        }
    }
}

private enum AlbumsSheet: String, Identifiable {
    case search

    var id: String { rawValue }
}

#Preview {
    NavigationStack {
        AlbumsView()
    }
}
