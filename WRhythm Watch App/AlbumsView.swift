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
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    private let pageSize = 20

    private var filteredAlbums: [AlbumSummary] {
        if offlineMode {
            let downloadedAlbums = libraryDataManager.albums.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
            if searchText.isEmpty {
                return downloadedAlbums
            }
            return downloadedAlbums.filter { album in
                album.name.localizedCaseInsensitiveContains(searchText) ||
                (album.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        } else {
            // Online mode: use search results if searching, otherwise show paginated list
            if !searchText.isEmpty {
                return searchResults
            }
            return libraryDataManager.albums
        }
    }

    var body: some View {
        content
            .navigationTitle("Albums")
            .wrhythmPageBackground()
            .toolbar {
                if !offlineMode {
                    ToolbarItem(placement: .platformTopBarTrailing) {
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

                        libraryDataManager.fetchInitialAlbums()

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

            // Offline mode: show downloaded albums only

            let downloadedAlbums = downloadManager.getDownloadedAlbums()

            let filteredAlbums = searchText.isEmpty ? downloadedAlbums : downloadedAlbums.filter { album in

                album.name.localizedCaseInsensitiveContains(searchText) ||

                (album.artist?.localizedCaseInsensitiveContains(searchText) ?? false)

            }

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

                List {

                    ForEach(filteredAlbums, id: \.id) { album in

                        NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                            WRhythmCollectionRow(
                                title: album.name,
                                subtitle: album.artist,
                                coverArtId: album.coverArt,
                                fallbackSystemImage: "square.stack",
                                tint: WRhythmTheme.album
                            ) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(WRhythmTheme.success)
                            }
                        }
                        .wrhythmAlbumActions(albumId: album.id, albumName: album.name)

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

                        libraryDataManager.fetchInitialAlbums(forceRefresh: true)

                }

            } else if libraryDataManager.albums.isEmpty {

                WRhythmEmptyState(
                    systemImage: "square.stack",
                    title: "No albums found",
                    message: nil,
                    actionTitle: "Retry"
                ) {

                        libraryDataManager.fetchInitialAlbums(forceRefresh: true)

                }

            } else {

                List {

                    ForEach(filteredAlbums) { album in

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
                        .wrhythmAlbumActions(albumId: album.id, albumName: album.name)

                        .onAppear {

                            if album.id == libraryDataManager.albums.last?.id && libraryDataManager.hasMoreAlbums && !libraryDataManager.isLoadingAlbums {

                                libraryDataManager.fetchMoreAlbums()

                            }

                        }

                    }

    

                    if libraryDataManager.isLoadingAlbums {

                        HStack {

                            Spacer()

                            ProgressView()

                            Spacer()

                        }

                    }

                }
                .wrhythmListSurface()

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
                self.searchResults = result.album ?? []
                self.isSearching = false
                print("🔍 Album search results: \(self.searchResults.count) albums")
            }
            catch {
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: query,
                    currentQuery: searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.searchResults = []
                self.isSearching = false
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
