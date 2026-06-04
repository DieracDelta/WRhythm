//
//  TracksView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/24/25.
//

import SwiftUI

struct TracksView: View {
    private let searchPageSize = SearchPaginationPolicy.defaultPageSize

    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var albumResults: [AlbumSummary] = []
    @State private var artistResults: [Artist] = []
    @State private var isSearching = false
    @State private var errorMessage = ""
    @State private var isRestoringCachedSearch = false
    @State private var restoredCachedSearchQueryToSkip: String?
    @State private var artistPage = 0
    @State private var albumPage = 0
    @State private var songPage = 0
    @State private var artistCanGoNext = false
    @State private var albumCanGoNext = false
    @State private var songCanGoNext = false
    @State private var pagingKind: SearchResultPageKind?
    @State private var searchMode: TracksSearchMode = .library
    @State private var clapTopQueries: [String] = []
#if os(watchOS)
    @State private var presentedSheet: TracksSheet?
#endif
    @State private var searchTask: Task<Void, Never>?
    @ObservedObject var api = NavidromeAPI.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("experimentalAudioMuseFeaturesEnabled") private var experimentalAudioMuseFeaturesEnabled = false
    @AppStorage("audioMuseSearchResultLimit") private var audioMuseSearchResultLimit = AudioMuseSearchResultLimitPolicy.defaultLimit

    private var availableSearchModes: [TracksSearchMode] {
        TracksSearchModePolicy.availableModes(
            experimentalAudioMuseEnabled: experimentalAudioMuseFeaturesEnabled && !offlineMode,
            clapSupported: api.audioMuseClapSearchSupported,
            semanticSupported: api.audioMuseSemanticSearchSupported
        )
    }

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
        .task(id: experimentalAudioMuseFeaturesEnabled) {
            guard experimentalAudioMuseFeaturesEnabled, !offlineMode else { return }
            await api.checkAudioMuseSearchSupport()
            await loadClapTopQueriesIfAvailable()
        }
        .onChange(of: availableSearchModes.map(\.id)) { _, modes in
            let available = TracksSearchModePolicy.availableModes(
                experimentalAudioMuseEnabled: experimentalAudioMuseFeaturesEnabled && !offlineMode,
                clapSupported: api.audioMuseClapSearchSupported,
                semanticSupported: api.audioMuseSemanticSearchSupported
            )
            let sanitized = TracksSearchModePolicy.sanitizedSelection(searchMode, availableModes: available)
            if sanitized != searchMode {
                searchMode = sanitized
                clearOnlineSearchResults()
            }
        }
        .onChange(of: searchMode) { _, _ in
            guard !offlineMode else { return }
            clearOnlineSearchResults()
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                performSearch(query: searchText, debounce: false)
            }
        }
        .onChange(of: audioMuseSearchResultLimit) { _, newValue in
            let sanitized = AudioMuseSearchResultLimitPolicy.sanitizedLimit(newValue)
            if sanitized != newValue {
                audioMuseSearchResultLimit = sanitized
                return
            }
            guard !offlineMode, searchMode.audioMuseMode != nil else { return }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                performSearch(query: searchText, debounce: false)
            }
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
                                SlidingRenderWindowForEach(
                                    offlinePlaylistResults,
                                    estimatedRowHeight: 64,
                                    resetToken: SongRenderWindowPolicy.searchResultGroupResetToken(
                                        mode: "offline",
                                        kind: "playlists",
                                        query: searchText
                                    )
                                ) { _, playlist in
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
                                SlidingRenderWindowForEach(
                                    offlineArtistResults,
                                    estimatedRowHeight: 64,
                                    resetToken: SongRenderWindowPolicy.searchResultGroupResetToken(
                                        mode: "offline",
                                        kind: "artists",
                                        query: searchText
                                    )
                                ) { _, artist in
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
                                SlidingRenderWindowForEach(
                                    offlineAlbumResults,
                                    estimatedRowHeight: 64,
                                    resetToken: SongRenderWindowPolicy.searchResultGroupResetToken(
                                        mode: "offline",
                                        kind: "albums",
                                        query: searchText
                                    )
                                ) { _, album in
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
                                SlidingRenderWindowForEach(
                                    displayedSongs,
                                    estimatedRowHeight: 64,
                                    resetToken: SongRenderWindowPolicy.trackSearchResetToken(mode: "offline", query: searchText)
                                ) { _, song in
                                    songRow(song: song)
                                }
                            }
                        }
                    }
                    .wrhythmListSurface()
                }
            } else if isSearching && !hasOnlineSearchResults {
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
                searchPrompt(title: searchPromptTitle, message: searchPromptMessage)
            } else if searchResults.isEmpty && albumResults.isEmpty && artistResults.isEmpty {
                WRhythmEmptyState(
                    systemImage: "music.note",
                    title: "No results",
                    message: "Try a different search term"
                )
            } else {
                onlineSearchResultsContent
            }
        }
    }

    @ViewBuilder
    private var onlineSearchResultsContent: some View {
#if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                if shouldShowSearchSection(kind: .artists, resultCount: artistResults.count) {
                    searchResultSection(title: "Artists", kind: .artists, count: artistResults.count) {
                        if artistResults.isEmpty {
                            emptySearchPageMessage(for: .artists)
                        } else {
                            SlidingRenderWindowForEach(
                                artistResults,
                                estimatedRowHeight: 64,
                                resetToken: SongRenderWindowPolicy.searchResultGroupResetToken(
                                    mode: "online",
                                    kind: "artists",
                                    query: searchText
                                )
                            ) { _, artist in
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

                                if artist.id != artistResults.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }

                if shouldShowSearchSection(kind: .albums, resultCount: albumResults.count) {
                    searchResultSection(title: "Albums", kind: .albums, count: albumResults.count) {
                        if albumResults.isEmpty {
                            emptySearchPageMessage(for: .albums)
                        } else {
                            SlidingRenderWindowForEach(
                                albumResults,
                                estimatedRowHeight: 64,
                                resetToken: SongRenderWindowPolicy.searchResultGroupResetToken(
                                    mode: "online",
                                    kind: "albums",
                                    query: searchText
                                )
                            ) { _, album in
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

                                if album.id != albumResults.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }

                if shouldShowSearchSection(kind: .songs, resultCount: searchResults.count) {
                    searchResultSection(title: "Songs", kind: .songs, count: searchResults.count) {
                        if searchResults.isEmpty {
                            emptySearchPageMessage(for: .songs)
                        } else {
                            SlidingRenderWindowForEach(
                                searchResults,
                                estimatedRowHeight: 64,
                                resetToken: SongRenderWindowPolicy.trackSearchResetToken(mode: "online", query: searchText)
                            ) { _, song in
                                songRow(song: song)

                                if song.id != searchResults.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, WRhythmSpacing.lg)
            .padding(.vertical, WRhythmSpacing.md)
        }
        .wrhythmListSurface()
#else
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

            if shouldShowSearchSection(kind: .artists, resultCount: artistResults.count) {
                Section(
                    header: Text("Artists"),
                    footer: searchPaginationControls(kind: .artists, resultCount: artistResults.count)
                ) {
                    if artistResults.isEmpty {
                        emptySearchPageMessage(for: .artists)
                    } else {
                        SlidingRenderWindowForEach(
                            artistResults,
                            estimatedRowHeight: 64,
                            resetToken: SongRenderWindowPolicy.searchResultGroupResetToken(
                                mode: "online",
                                kind: "artists",
                                query: searchText
                            )
                        ) { _, artist in
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
            }

            if shouldShowSearchSection(kind: .albums, resultCount: albumResults.count) {
                Section(
                    header: Text("Albums"),
                    footer: searchPaginationControls(kind: .albums, resultCount: albumResults.count)
                ) {
                    if albumResults.isEmpty {
                        emptySearchPageMessage(for: .albums)
                    } else {
                        SlidingRenderWindowForEach(
                            albumResults,
                            estimatedRowHeight: 64,
                            resetToken: SongRenderWindowPolicy.searchResultGroupResetToken(
                                mode: "online",
                                kind: "albums",
                                query: searchText
                            )
                        ) { _, album in
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
            }

            if shouldShowSearchSection(kind: .songs, resultCount: searchResults.count) {
                Section(
                    header: Text("Songs"),
                    footer: searchPaginationControls(kind: .songs, resultCount: searchResults.count)
                ) {
                    if searchResults.isEmpty {
                        emptySearchPageMessage(for: .songs)
                    } else {
                        SlidingRenderWindowForEach(
                            searchResults,
                            estimatedRowHeight: 64,
                            resetToken: SongRenderWindowPolicy.trackSearchResetToken(mode: "online", query: searchText)
                        ) { _, song in
                            songRow(song: song)
                        }
                    }
                }
            }
        }
        .wrhythmListSurface()
#endif
    }

    @ViewBuilder
    private var audioMuseSearchControls: some View {
        if let mode = searchMode.audioMuseMode {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WRhythmSpacing.sm) {
                    audioMuseSearchLimitStepper(mode: mode)
                    audioMuseQueueAllButton
                }

                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    audioMuseSearchLimitStepper(mode: mode)
                    audioMuseQueueAllButton
                }
            }
            .padding(.horizontal, WRhythmSpacing.md)
            .padding(.vertical, WRhythmSpacing.sm)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                    .strokeBorder(WRhythmTheme.playlistGen.opacity(0.22), lineWidth: 1)
            }
            .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private func audioMuseSearchLimitStepper(mode: AudioMuseSearchMode) -> some View {
        Stepper(
            value: audioMuseSearchLimitBinding,
            in: AudioMuseSearchResultLimitPolicy.minimumLimit...AudioMuseSearchResultLimitPolicy.maximumLimit,
            step: AudioMuseSearchResultLimitPolicy.step
        ) {
            Label {
                Text("\(mode.label): \(sanitizedAudioMuseSearchResultLimit) songs")
                    .font(WRhythmTypography.metadataEmphasis)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "number")
            }
            .foregroundStyle(.primary)
        }
    }

    private var audioMuseQueueAllButton: some View {
        Button(action: queueAllAudioMuseSearchResults) {
            Label("Queue All", systemImage: "text.badge.plus")
        }
        .buttonStyle(.bordered)
        .tint(WRhythmTheme.playlistGen)
        .disabled(searchResults.isEmpty || isSearching)
    }

    private var sanitizedAudioMuseSearchResultLimit: Int {
        AudioMuseSearchResultLimitPolicy.sanitizedLimit(audioMuseSearchResultLimit)
    }

    private var audioMuseSearchLimitBinding: Binding<Int> {
        Binding(
            get: {
                sanitizedAudioMuseSearchResultLimit
            },
            set: { newValue in
                audioMuseSearchResultLimit = AudioMuseSearchResultLimitPolicy.sanitizedLimit(newValue)
            }
        )
    }

    @ViewBuilder
    private func searchResultSection<Content: View>(
        title: String,
        kind: SearchResultPageKind,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            WRhythmSectionHeader(
                title: title,
                subtitle: "\(resultCountText(count)) - page \(searchPage(for: kind) + 1)"
            )

            WRhythmCard(padding: WRhythmSpacing.sm) {
                content()
            }

            searchPaginationControls(kind: kind, resultCount: count)
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
        VStack(spacing: WRhythmSpacing.md) {
            WRhythmEmptyState(
                systemImage: searchMode == .library ? "magnifyingglass" : "sparkles",
                title: title,
                message: message
            )

            if searchMode == .audioMuseClap && !clapTopQueries.isEmpty {
                WRhythmCard(padding: WRhythmSpacing.sm) {
                    VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                        Text("Try a vibe")
                            .font(WRhythmTypography.sectionLabel)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: WRhythmSpacing.xs)], alignment: .leading, spacing: WRhythmSpacing.xs) {
                            ForEach(clapTopQueries.prefix(8), id: \.self) { query in
                                Button(query) {
                                    searchText = query
                                    performSearch(query: query, debounce: false)
                                }
                                .buttonStyle(.bordered)
                                .tint(WRhythmTheme.playlistGen)
                            }
                        }
                    }
                }
                .frame(maxWidth: 620)
            }
        }
#endif
    }

    @ViewBuilder
    private func songRow(song: Song) -> some View {
        Button(action: {
            handleSongRowTap(song)
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
                    switch downloadManager.downloadStatus(for: song.id) {
                    case .downloading(let progress):
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("\(Int(progress * 100))%")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(WRhythmTheme.downloads)
                            .monospacedDigit()
                    case .queued:
                        Label("Queued", systemImage: "clock")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(WRhythmTheme.warning)
                            .labelStyle(.iconOnly)
                    case .downloaded:
                        Image(systemName: "arrow.down.circle.fill")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(WRhythmTheme.success)
                    case .none:
                        if !offlineMode {
                            WRhythmRowIconButton(
                                systemImage: "arrow.down.circle",
                                tint: WRhythmTheme.secondaryAccent,
                                accessibilityLabel: "Download song"
                            ) {
                                DownloadManager.shared.downloadSong(song)
                            }
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
        .wrhythmSelectableTrack(song: song, selectionScopeSongs: displayedSongs)
        .wrhythmTrackActions(song: song)
    }

    private func handleSongRowTap(_ song: Song) {
#if os(macOS)
        let modifiers = TrackSelectionModifiers.currentEventModifiers
        if modifiers.shouldSelectInsteadOfActivate {
            TrackSelectionManager.shared.handleClick(
                song: song,
                scopeSongs: displayedSongs,
                modifiers: modifiers
            )
            return
        }
        if TrackSelectionManager.shared.selectedCount > 0 {
            TrackSelectionManager.shared.clear()
        }
#endif
        AudioPlayer.shared.playSong(song)
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

    private var hasOnlineSearchResults: Bool {
        !artistResults.isEmpty || !albumResults.isEmpty || !searchResults.isEmpty
    }

    private func shouldShowSearchSection(kind: SearchResultPageKind, resultCount: Int) -> Bool {
        resultCount > 0 || searchPage(for: kind) > 0
    }

    private func emptySearchPageMessage(for kind: SearchResultPageKind) -> some View {
        Text("No \(kind.label) on this page")
            .font(WRhythmTypography.metadata)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, WRhythmSpacing.sm)
    }

    @ViewBuilder
    private func searchPaginationControls(kind: SearchResultPageKind, resultCount: Int) -> some View {
        if searchMode != .library {
            EmptyView()
        } else {
        let currentPage = searchPage(for: kind)
        let canPrevious = SearchPaginationPolicy.canGoPrevious(page: currentPage)
        let canNext = searchCanGoNext(for: kind)
        let pages = SearchPaginationPolicy.visiblePages(currentPage: currentPage, canGoNext: canNext)

        HStack(spacing: WRhythmSpacing.xs) {
            Button {
                goToSearchPage(currentPage - 1, kind: kind)
            } label: {
                Label("Previous \(kind.label) page", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(!canPrevious || isSearching)

            ForEach(pages, id: \.self) { page in
                Button {
                    goToSearchPage(page, kind: kind)
                } label: {
                    Text("\(page + 1)")
                        .font(page == currentPage ? WRhythmTypography.metadataEmphasis : WRhythmTypography.metadata)
                        .monospacedDigit()
                        .frame(minWidth: 24)
                }
                .buttonStyle(.bordered)
                .tint(page == currentPage ? WRhythmTheme.accent : nil)
                .disabled(page == currentPage || isSearching)
            }

            Button {
                goToSearchPage(currentPage + 1, kind: kind)
            } label: {
                Label("Next \(kind.label) page", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(!canNext || isSearching)

            if pagingKind == kind {
                ProgressView()
                    .controlSize(.small)
                    .tint(WRhythmTheme.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, WRhythmSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.label) search result pages")
        }
    }

    private func searchPage(for kind: SearchResultPageKind) -> Int {
        switch kind {
        case .artists:
            return artistPage
        case .albums:
            return albumPage
        case .songs:
            return songPage
        }
    }

    private func searchCanGoNext(for kind: SearchResultPageKind) -> Bool {
        switch kind {
        case .artists:
            return artistCanGoNext
        case .albums:
            return albumCanGoNext
        case .songs:
            return songCanGoNext
        }
    }

    private func goToSearchPage(_ page: Int, kind: SearchResultPageKind) {
        let page = max(0, page)
        switch kind {
        case .artists:
            artistPage = page
        case .albums:
            albumPage = page
        case .songs:
            songPage = page
        }
        performSearch(query: searchText, debounce: false, resetPages: false, pagingKind: kind)
    }

    private func resetSearchPages() {
        artistPage = 0
        albumPage = 0
        songPage = 0
        artistCanGoNext = false
        albumCanGoNext = false
        songCanGoNext = false
    }

    private func updateSearchPageAvailability() {
        guard searchMode == .library else {
            artistCanGoNext = false
            albumCanGoNext = false
            songCanGoNext = false
            return
        }
        artistCanGoNext = SearchPaginationPolicy.canGoNext(resultCount: artistResults.count, pageSize: searchPageSize)
        albumCanGoNext = SearchPaginationPolicy.canGoNext(resultCount: albumResults.count, pageSize: searchPageSize)
        songCanGoNext = SearchPaginationPolicy.canGoNext(resultCount: searchResults.count, pageSize: searchPageSize)
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

            audioMuseSearchControls
                .padding(.horizontal, WRhythmSpacing.md)
                .padding(.bottom, searchMode.audioMuseMode == nil ? 0 : WRhythmSpacing.sm)

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

            if availableSearchModes.count > 1 {
                Picker("Search Mode", selection: $searchMode) {
                    ForEach(availableSearchModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 112)
                .accessibilityLabel("Search mode")
            }

            TextField(searchFieldPrompt, text: $searchText)
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
        pagingKind = nil
        errorMessage = ""
        resetSearchPages()
    }

    private func loadCachedSearchIfNeeded() {
        guard !offlineMode, searchText.isEmpty else { return }
        guard let cached = SearchResultDiskCache.loadLastSearch() else { return }

        isRestoringCachedSearch = true
        resetSearchPages()
        applySearchResult(cached.result)
        updateSearchPageAvailability()
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

    private func performSearch(
        query: String,
        debounce: Bool = true,
        resetPages: Bool = true,
        pagingKind: SearchResultPageKind? = nil
    ) {
        searchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            albumResults = []
            artistResults = []
            isSearching = false
            self.pagingKind = nil
            resetSearchPages()
            return
        }

        if resetPages {
            resetSearchPages()
            searchResults = []
            albumResults = []
            artistResults = []
        }
        isSearching = true
        self.pagingKind = pagingKind
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
                let artistPage = self.artistPage
                let albumPage = self.albumPage
                let songPage = self.songPage
                let audioMuseLimit = self.sanitizedAudioMuseSearchResultLimit
                let result = try await searchWithRetry(
                    query: trimmedQuery,
                    artistPage: artistPage,
                    albumPage: albumPage,
                    songPage: songPage,
                    audioMuseLimit: audioMuseLimit
                )
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: trimmedQuery,
                    currentQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    isCancelled: Task.isCancelled
                ) else { return }
                self.applySearchResult(result)
                self.updateSearchPageAvailability()
                if artistPage == 0, albumPage == 0, songPage == 0 {
                    SearchResultDiskCache.save(query: trimmedQuery, result: result)
                }
                self.isSearching = false
                self.pagingKind = nil

                print("🔍 Search results: \(self.artistResults.count) artists, \(self.albumResults.count) albums, \(self.searchResults.count) songs")
            } catch {
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: trimmedQuery,
                    currentQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    isCancelled: Task.isCancelled
                ) else { return }
                self.errorMessage = searchErrorMessage(error)
                self.isSearching = false
                self.pagingKind = nil
                print("❌ Search error: \(error)")
            }
        }
    }

    private func queueAllAudioMuseSearchResults() {
        guard searchMode.audioMuseMode != nil, !searchResults.isEmpty else { return }
        TrackActions.addToQueue(searchResults)
    }

    private func searchWithRetry(query: String, artistPage: Int, albumPage: Int, songPage: Int, audioMuseLimit: Int) async throws -> SearchResult {
        do {
            return try await pagedSearch(query: query, artistPage: artistPage, albumPage: albumPage, songPage: songPage, audioMuseLimit: audioMuseLimit)
        } catch {
            guard SearchRetryPolicy.isRetryable(error), !Task.isCancelled else {
                throw error
            }
            try await Task.sleep(nanoseconds: 700_000_000)
            return try await pagedSearch(query: query, artistPage: artistPage, albumPage: albumPage, songPage: songPage, audioMuseLimit: audioMuseLimit)
        }
    }

    private func pagedSearch(query: String, artistPage: Int, albumPage: Int, songPage: Int, audioMuseLimit: Int) async throws -> SearchResult {
        if let audioMuseMode = searchMode.audioMuseMode {
            let songs = try await NavidromeAPI.shared.getAudioMuseSearchSongs(
                mode: audioMuseMode,
                query: query,
                limit: audioMuseLimit
            )
            return SearchResult(artist: [], album: [], song: songs)
        }

        return try await NavidromeAPI.shared.search(
            query: query,
            artistCount: searchPageSize,
            artistOffset: SearchPaginationPolicy.offset(forPage: artistPage, pageSize: searchPageSize),
            albumCount: searchPageSize,
            albumOffset: SearchPaginationPolicy.offset(forPage: albumPage, pageSize: searchPageSize),
            songCount: searchPageSize,
            songOffset: SearchPaginationPolicy.offset(forPage: songPage, pageSize: searchPageSize)
        )
    }

    private func searchErrorMessage(_ error: Error) -> String {
        SearchRetryPolicy.userMessage(for: error)
    }

    private var searchFieldPrompt: String {
        if offlineMode {
            return "Search offline music"
        }
        switch searchMode {
        case .library:
            return "Search music"
        case .audioMuseClap:
            return "Search by vibe"
        case .audioMuseSemantic:
            return "Search semantically"
        }
    }

    private var searchPromptTitle: String {
        switch searchMode {
        case .library:
            return "Search Music"
        case .audioMuseClap:
            return "Vibe Search"
        case .audioMuseSemantic:
            return "Semantic Search"
        }
    }

    private var searchPromptMessage: String? {
        switch searchMode {
        case .library:
            return nil
        case .audioMuseClap:
            return "Describe how the music should feel or sound."
        case .audioMuseSemantic:
            return "Search by lyric, text, or meaning."
        }
    }

    private func loadClapTopQueriesIfAvailable() async {
        guard api.audioMuseClapSearchSupported == true else { return }
        do {
            clapTopQueries = try await api.getAudioMuseClapTopQueries()
        } catch {
            clapTopQueries = []
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds))
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }
}

private enum SearchResultPageKind: String, Sendable {
    case artists
    case albums
    case songs

    var label: String {
        switch self {
        case .artists:
            return "artists"
        case .albums:
            return "albums"
        case .songs:
            return "tracks"
        }
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
