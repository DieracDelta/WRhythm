//
//  TracksView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/24/25.
//

import SwiftUI

struct TracksView: View {
    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var albumResults: [AlbumSummary] = []
    @State private var artistResults: [Artist] = []
    @State private var isSearching = false
    @State private var errorMessage = ""
    @State private var isRestoringCachedSearch = false
    @State private var restoredCachedSearchQueryToSkip: String?
#if os(watchOS)
    @State private var presentedSheet: TracksSheet?
#endif
    @State private var searchTask: Task<Void, Never>?
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var displayedSongs: [Song] {
        if offlineMode {
            // Get songs from songMetadata that are actually downloaded
            let allSongs = downloadManager.songMetadata.values.filter { song in
                downloadManager.isDownloaded(song.id)
            }

            // Filter by search text if present
            if searchText.isEmpty {
                return allSongs.sorted { $0.title < $1.title }
            } else {
                return allSongs.filter { song in
                    song.title.localizedCaseInsensitiveContains(searchText) ||
                    (song.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (song.album?.localizedCaseInsensitiveContains(searchText) ?? false)
                }.sorted { $0.title < $1.title }
            }
        } else {
            return searchResults
        }
    }

    private var offlineAlbumResults: [AlbumSummary] {
        guard offlineMode && !searchText.isEmpty else { return [] }

        // Extract unique albums from downloaded songs
        var albumsDict: [String: AlbumSummary] = [:]
        for song in downloadManager.songMetadata.values where downloadManager.isDownloaded(song.id) {
            if let album = song.album,
               album.localizedCaseInsensitiveContains(searchText) {
                let key = album.lowercased()
                if albumsDict[key] == nil {
                    albumsDict[key] = AlbumSummary(
                        id: key,
                        name: album,
                        artist: song.artist,
                        artistId: nil,
                        coverArt: song.coverArt,
                        songCount: 0,
                        duration: 0,
                        created: "",
                        year: nil
                    )
                }
            }
        }
        return Array(albumsDict.values).sorted { $0.name < $1.name }
    }

    private var offlineArtistResults: [Artist] {
        guard offlineMode && !searchText.isEmpty else { return [] }

        // Extract unique artists from downloaded songs
        var artistsDict: [String: Artist] = [:]
        for song in downloadManager.songMetadata.values where downloadManager.isDownloaded(song.id) {
            if let artist = song.artist,
               artist.localizedCaseInsensitiveContains(searchText) {
                let key = artist.lowercased()
                if artistsDict[key] == nil {
                    artistsDict[key] = Artist(
                        id: key,
                        name: artist,
                        albumCount: nil,
                        coverArt: song.coverArt
                    )
                }
            }
        }
        return Array(artistsDict.values).sorted { $0.name < $1.name }
    }

    private var offlinePlaylistResults: [CachedPlaylist] {
        guard offlineMode && !searchText.isEmpty else { return [] }

        return downloadManager.cachedPlaylists.filter { playlist in
            playlist.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        searchScaffold {
            searchContent
        }
        .navigationTitle(navigationTitleText)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .wrhythmPageBackground()
#if os(watchOS)
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                WRhythmSearchToolbarButton(
                    hasQuery: !searchText.isEmpty,
                    clear: clearSearch,
                    search: {
                        presentedSheet = .search
                    }
                )
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .search:
                PlatformSearchSheet(offlineMode ? "Offline Search" : "Search", onCancel: {
                    presentedSheet = nil
                }) {
                    VStack(spacing: WRhythmSpacing.md) {
                        TextField(offlineMode ? "Search offline music" : "Search music", text: $searchText)
                            .platformSearchTextFieldStyle()
                            .frame(maxWidth: .infinity)

                        Button("Search") {
                            presentedSheet = nil
                            if !offlineMode {
                                performSearch(query: searchText, debounce: false)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(searchText.isEmpty)

                        Spacer()
                    }
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, WRhythmSpacing.md)
                    .padding(.top, WRhythmSpacing.lg)
                }
            }
        }
#endif
        .onAppear {
            loadCachedSearchIfNeeded()
        }
        .onChange(of: searchText) { _, newValue in
            guard !offlineMode else { return }
            let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if restoredCachedSearchQueryToSkip == trimmedValue {
                restoredCachedSearchQueryToSkip = nil
                return
            }
            guard !isRestoringCachedSearch else { return }
            if newValue.isEmpty {
                clearOnlineSearchResults()
            } else {
                performSearch(query: newValue)
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        Group {
            if offlineMode {
                // Offline mode: search through downloaded content
                if searchText.isEmpty {
                    searchPrompt(title: "Search Offline", message: offlineSearchMessage)
                } else if displayedSongs.isEmpty && offlineAlbumResults.isEmpty && offlineArtistResults.isEmpty && offlinePlaylistResults.isEmpty {
                    WRhythmEmptyState(
                        systemImage: "music.note",
                        title: "No offline results",
                        message: "Try a different search term"
                    )
                } else {
                    List {
#if os(iOS)
                        PhoneSearchSubmenuHeader(
                            title: "Offline Results",
                            subtitle: "Downloaded songs, albums, artists, and playlists that match your query.",
                            systemImage: "magnifyingglass",
                            countText: resultCountText(displayedSongs.count + offlineAlbumResults.count + offlineArtistResults.count + offlinePlaylistResults.count),
                            queryText: searchText
                        )
#endif

                        if !offlinePlaylistResults.isEmpty {
                            Section(header: Text("Playlists")) {
                                ForEach(offlinePlaylistResults, id: \.id) { playlist in
                                NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                                        WRhythmCollectionRow(
                                            title: playlist.name,
                                            subtitle: "\(playlist.songCount) songs",
                                            detail: "Cached playlist",
                                            coverArtId: playlist.coverArt,
                                            fallbackSystemImage: "music.note.list",
                                            tint: WRhythmTheme.playlistGen
                                        )
                                    }
                                    .wrhythmPlaylistActions(playlistId: playlist.id, playlistName: playlist.name)
                                }
                            }
                        }

                        if !offlineArtistResults.isEmpty {
                            Section(header: Text("Artists")) {
                                ForEach(offlineArtistResults) { artist in
                                    Button(action: {
                                        // Filter songs by this artist
                                        searchText = artist.name
                                    }) {
                                        WRhythmCollectionRow(
                                            title: artist.name,
                                            subtitle: "Artist",
                                            coverArtId: artist.coverArt,
                                            fallbackSystemImage: "person.fill",
                                            tint: WRhythmTheme.artist
                                        )
                                    }
                                    .wrhythmArtistActions(artistId: "offline-\(artist.name)", artistName: artist.name)
                                }
                            }
                        }

                        if !offlineAlbumResults.isEmpty {
                            Section(header: Text("Albums")) {
                                ForEach(offlineAlbumResults) { album in
                                    Button(action: {
                                        // Filter songs by this album
                                        searchText = album.name
                                    }) {
                                        WRhythmCollectionRow(
                                            title: album.name,
                                            subtitle: album.artist,
                                            coverArtId: album.coverArt,
                                            fallbackSystemImage: "square.stack",
                                            tint: WRhythmTheme.album
                                        )
                                    }
                                    .wrhythmAlbumActions(albumId: album.id, albumName: album.name)
                                }
                            }
                        }

                        if !displayedSongs.isEmpty {
                            Section(header: Text("Songs")) {
                                ForEach(displayedSongs) { song in
                                    songRow(song: song)
                                }
                            }
                        }
                    }
                    .wrhythmListSurface()
                }
            } else if isSearching {
                WRhythmLoadingState(
                    systemImage: "magnifyingglass",
                    title: "Searching",
                    message: searchText
                )
            } else if !errorMessage.isEmpty {
                WRhythmErrorState(
                    title: "Search Error",
                    message: errorMessage
                ) {
                    performSearch(query: searchText)
                }
            } else if searchText.isEmpty {
                searchPrompt(title: "Search Music", message: nil)
            } else if searchResults.isEmpty && albumResults.isEmpty && artistResults.isEmpty {
                WRhythmEmptyState(
                    systemImage: "music.note",
                    title: "No results",
                    message: "Try a different search term"
                )
            } else {
                List {
#if os(iOS)
                    PhoneSearchSubmenuHeader(
                        title: "Search Results",
                        subtitle: "Matching songs, albums, and artists from your library.",
                        systemImage: "magnifyingglass",
                        countText: resultCountText(searchResults.count + albumResults.count + artistResults.count),
                        queryText: searchText
                    )
#endif

                    if !artistResults.isEmpty {
                        Section(header: Text("Artists")) {
                            ForEach(artistResults) { artist in
                                NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                                    WRhythmCollectionRow(
                                        title: artist.name,
                                        subtitle: artist.albumCount.map { "\($0) albums" },
                                        coverArtId: artist.coverArt,
                                        fallbackSystemImage: "person.fill",
                                        tint: WRhythmTheme.artist
                                    )
                                }
                                .wrhythmArtistActions(artistId: artist.id, artistName: artist.name)
                            }
                        }
                    }

                    if !albumResults.isEmpty {
                        Section(header: Text("Albums")) {
                            ForEach(albumResults) { album in
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
                            }
                        }
                    }

                    if !searchResults.isEmpty {
                        Section(header: Text("Songs")) {
                            ForEach(searchResults) { song in
                                songRow(song: song)
                            }
                        }
                    }
                }
                .wrhythmListSurface()
            }
        }
    }

    @ViewBuilder
    private func searchPrompt(title: String, message: String?) -> some View {
#if os(watchOS)
        WRhythmScreen {
            Button(action: {
                presentedSheet = .search
            }) {
                HStack(spacing: WRhythmSpacing.sm) {
                    WRhythmIconBadge(systemImage: "magnifyingglass", tint: WRhythmTheme.accent, size: 34)
                    Text("Search")
                        .font(WRhythmTypography.rowTitle)
                    Spacer(minLength: WRhythmSpacing.xs)
                    Image(systemName: "chevron.right")
                        .font(WRhythmTypography.metadata)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, WRhythmSpacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
#elseif os(iOS) || os(macOS)
        WRhythmEmptyState(
            systemImage: "magnifyingglass",
            title: title,
            message: message
        )
#endif
    }

    @ViewBuilder
    private func songRow(song: Song) -> some View {
        Button(action: {
            AudioPlayer.shared.playSong(song)
        }) {
            WRhythmMediaRow(
                title: song.title,
                subtitle: song.artist,
                detail: song.album,
                coverArtId: song.coverArt,
                artworkSize: 44,
                isCurrent: player.currentSong?.id == song.id,
                isPlaying: player.currentSong?.id == song.id && player.isPlaying
            ) {
                HStack(spacing: 8) {
                    if downloadManager.isDownloading(song.id) {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if downloadManager.isDownloaded(song.id) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(WRhythmTheme.success)
                    } else if !offlineMode {
                        WRhythmRowIconButton(
                            systemImage: "arrow.down.circle",
                            tint: WRhythmTheme.secondaryAccent,
                            accessibilityLabel: "Download song"
                        ) {
                            DownloadManager.shared.downloadSong(song)
                        }
                    }

                    if !offlineMode {
                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "music.note.list")
                                .font(WRhythmTypography.metadata)
                                .foregroundColor(WRhythmTheme.accent)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .wrhythmTrackActions(song: song)
    }

    private var offlineSearchMessage: String {
        let downloadedCount = downloadManager.songMetadata.values.filter { downloadManager.isDownloaded($0.id) }.count
        if downloadedCount == 0 {
            return "Download songs while online to search offline"
        }
        return "\(downloadedCount) songs available offline"
    }

    private func resultCountText(_ count: Int) -> String {
        count == 1 ? "1 result" : "\(count) results"
    }

    private var navigationTitleText: String {
#if os(iOS)
        offlineMode ? "Offline Search" : "Search"
#else
        offlineMode ? "Offline Search" : "Search"
#endif
    }

    private var showsPhoneSearchPrompt: Bool {
#if os(iOS)
        searchText.isEmpty && !isSearching && errorMessage.isEmpty
#else
        false
#endif
    }

    @ViewBuilder
    private func searchScaffold<Content: View>(@ViewBuilder content: () -> Content) -> some View {
#if os(iOS) || os(macOS)
        VStack(spacing: 0) {
            inlineSearchField
                .padding(.horizontal, WRhythmSpacing.md)
                .padding(.top, WRhythmSpacing.md)
                .padding(.bottom, WRhythmSpacing.sm)

            content()
        }
#else
        content()
#endif
    }

#if os(iOS) || os(macOS)
    private var inlineSearchField: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(WRhythmTypography.bodyEmphasis)
                .foregroundStyle(WRhythmTheme.accent)

            TextField(offlineMode ? "Search offline music" : "Search music", text: $searchText)
                .textFieldStyle(.plain)
                .platformAutocapitalizationNever()
                .submitLabel(.search)
                .onSubmit {
                    if !offlineMode {
                        performSearch(query: searchText, debounce: false)
                    }
                }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(WRhythmTheme.accent)
                    .accessibilityLabel("Searching")
            } else if !offlineMode && !searchText.isEmpty {
                Button {
                    performSearch(query: searchText, debounce: false)
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundStyle(WRhythmTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search now")
            }

            if !searchText.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, WRhythmSpacing.md)
        .frame(minHeight: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.accent.opacity(0.24), lineWidth: 1)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }
#endif

    private func clearSearch() {
        searchText = ""
        searchTask?.cancel()
        if !offlineMode {
            clearOnlineSearchResults()
        }
    }

    private func clearOnlineSearchResults() {
        searchResults = []
        albumResults = []
        artistResults = []
        isSearching = false
        errorMessage = ""
    }

    private func loadCachedSearchIfNeeded() {
        guard !offlineMode, searchText.isEmpty else { return }
        guard let cached = SearchResultDiskCache.loadLastSearch() else { return }

        isRestoringCachedSearch = true
        applySearchResult(cached.result)
        restoredCachedSearchQueryToSkip = cached.query
        searchText = cached.query
        isSearching = false
        errorMessage = ""

        Task { @MainActor in
            await Task.yield()
            isRestoringCachedSearch = false
        }
    }

    private func applySearchResult(_ result: SearchResult) {
        artistResults = result.artist ?? []
        albumResults = result.album ?? []
        searchResults = result.song ?? []
    }

    private func performSearch(query: String, debounce: Bool = true) {
        searchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            albumResults = []
            artistResults = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = ""

        searchTask = Task { @MainActor in
            if debounce {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            }

            guard SearchResultOwnershipPolicy.shouldApply(
                query: trimmedQuery,
                currentQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                isCancelled: Task.isCancelled
            ) else { return } // Check if search text changed

            do {
                let result = try await searchWithRetry(query: trimmedQuery)
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: trimmedQuery,
                    currentQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    isCancelled: Task.isCancelled
                ) else { return }
                self.applySearchResult(result)
                SearchResultDiskCache.save(query: trimmedQuery, result: result)
                self.isSearching = false

                print("🔍 Search results: \(self.artistResults.count) artists, \(self.albumResults.count) albums, \(self.searchResults.count) songs")
            } catch {
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: trimmedQuery,
                    currentQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    isCancelled: Task.isCancelled
                ) else { return }
                self.errorMessage = searchErrorMessage(error)
                self.isSearching = false
                print("❌ Search error: \(error)")
            }
        }
    }

    private func searchWithRetry(query: String) async throws -> SearchResult {
        do {
            return try await NavidromeAPI.shared.search(query: query)
        } catch {
            guard SearchRetryPolicy.isRetryable(error), !Task.isCancelled else {
                throw error
            }
            try await Task.sleep(nanoseconds: 700_000_000)
            return try await NavidromeAPI.shared.search(query: query)
        }
    }

    private func searchErrorMessage(_ error: Error) -> String {
        SearchRetryPolicy.userMessage(for: error)
    }

    private func formatDuration(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds))
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }
}

#if os(watchOS)
private enum TracksSheet: String, Identifiable {
    case search

    var id: String { rawValue }
}
#endif

#Preview {
    NavigationStack {
        TracksView()
    }
}
