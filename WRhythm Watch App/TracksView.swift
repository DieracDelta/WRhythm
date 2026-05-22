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
    @State private var presentedSheet: TracksSheet?
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
        Group {
            if offlineMode {
                // Offline mode: search through downloaded content
                if searchText.isEmpty {
                    WRhythmEmptyState(
                        systemImage: "magnifyingglass",
                        title: "Search offline music",
                        message: offlineSearchMessage,
                        actionTitle: "Search"
                    ) {
                        presentedSheet = .search
                    }
                } else if displayedSongs.isEmpty && offlineAlbumResults.isEmpty && offlineArtistResults.isEmpty && offlinePlaylistResults.isEmpty {
                    WRhythmEmptyState(
                        systemImage: "music.note",
                        title: "No offline results",
                        message: "Try a different search term"
                    )
                } else {
                    List {
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
                                            tint: .purple
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
                                            tint: .indigo
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
                                            tint: .teal
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
                WRhythmEmptyState(
                    systemImage: "magnifyingglass",
                    title: "Search music",
                    message: "Find songs, albums, artists, and playlists",
                    actionTitle: "Search"
                ) {
                    presentedSheet = .search
                }
            } else if searchResults.isEmpty && albumResults.isEmpty && artistResults.isEmpty {
                WRhythmEmptyState(
                    systemImage: "music.note",
                    title: "No results",
                    message: "Try a different search term"
                )
            } else {
                List {
                    if !artistResults.isEmpty {
                        Section(header: Text("Artists")) {
                            ForEach(artistResults) { artist in
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
                                        tint: .teal
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
        .navigationTitle(offlineMode ? "Offline Search" : "Search")
        .wrhythmPageBackground()
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchTask?.cancel()
                        if !offlineMode {
                            searchResults = []
                            albumResults = []
                            artistResults = []
                            isSearching = false
                        }
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .search:
            PlatformSearchSheet(offlineMode ? "Offline Search" : "Search", onCancel: {
                presentedSheet = nil
            }) {
                VStack(spacing: 16) {
                    TextField(offlineMode ? "Search offline music" : "Search music", text: $searchText)
                        .platformSearchTextFieldStyle()
                        .frame(maxWidth: .infinity)

                    Button("Search") {
                        presentedSheet = nil
                        if !offlineMode {
                            performSearch(query: searchText)
                        }
                        // In offline mode, the view automatically updates via computed properties
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.isEmpty)

                    Spacer()
                }
            }
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
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
                            .font(.caption2)
                            .foregroundColor(WRhythmTheme.success)
                    } else if !offlineMode {
                        Button(action: {
                            DownloadManager.shared.downloadSong(song)
                        }) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption2)
                                .foregroundColor(WRhythmTheme.secondaryAccent)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }

                    if !offlineMode {
                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "music.note.list")
                                .font(.caption2)
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

    private func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            albumResults = []
            artistResults = []
            isSearching = false
            return
        }

        // Debounce the search
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            guard SearchResultOwnershipPolicy.shouldApply(
                query: query,
                currentQuery: searchText,
                isCancelled: Task.isCancelled
            ) else { return } // Check if search text changed

            isSearching = true
            errorMessage = ""

            do {
                let result = try await NavidromeAPI.shared.search(query: query)
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: query,
                    currentQuery: searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.artistResults = result.artist ?? []
                self.albumResults = result.album ?? []
                self.searchResults = result.song ?? []
                self.isSearching = false

                print("🔍 Search results: \(self.artistResults.count) artists, \(self.albumResults.count) albums, \(self.searchResults.count) songs")
            } catch {
                guard SearchResultOwnershipPolicy.shouldApply(
                    query: query,
                    currentQuery: searchText,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.errorMessage = error.localizedDescription
                self.isSearching = false
                print("❌ Search error: \(error)")
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private enum TracksSheet: String, Identifiable {
    case search

    var id: String { rawValue }
}

#Preview {
    NavigationView {
        TracksView()
    }
}
