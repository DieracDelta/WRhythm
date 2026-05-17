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
    @State private var showingSearchSheet = false
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
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Search offline music")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        let downloadedCount = downloadManager.songMetadata.values.filter { downloadManager.isDownloaded($0.id) }.count
                        if downloadedCount == 0 {
                            Text("No downloaded songs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Download songs while online to search offline")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Text("\(downloadedCount) songs available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button(action: {
                            showingSearchSheet = true
                        }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Start Search")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                } else if displayedSongs.isEmpty && offlineAlbumResults.isEmpty && offlineArtistResults.isEmpty && offlinePlaylistResults.isEmpty {
                    VStack {
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No offline results")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        if !offlinePlaylistResults.isEmpty {
                            Section(header: Text("Playlists")) {
                                ForEach(offlinePlaylistResults, id: \.id) { playlist in
                                    NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                                        HStack {
                                            if let coverArtId = playlist.coverArt,
                                               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                                CachedAsyncImage(url: coverURL) { image in
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                }
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(4)
                                            }

                                            VStack(alignment: .leading) {
                                                Text(playlist.name)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                                Text("\(playlist.songCount) songs")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
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
                                        HStack {
                                            if let coverArtId = artist.coverArt,
                                               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                                CachedAsyncImage(url: coverURL) { image in
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                }
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(4)
                                            }

                                            Text(artist.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                        }
                                    }
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
                                        HStack {
                                            if let coverArtId = album.coverArt,
                                               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                                CachedAsyncImage(url: coverURL) { image in
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
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
                }
            } else if isSearching {
                ProgressView("Searching...")
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else if searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Search music")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        showingSearchSheet = true
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Start Search")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            } else if searchResults.isEmpty && albumResults.isEmpty && artistResults.isEmpty {
                VStack {
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    if !artistResults.isEmpty {
                        Section(header: Text("Artists")) {
                            ForEach(artistResults) { artist in
                                NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                                    HStack {
                                        if let coverArtId = artist.coverArt,
                                           let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                            CachedAsyncImage(url: coverURL) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            }
                                            .frame(width: 40, height: 40)
                                            .cornerRadius(4)
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
                            }
                        }
                    }

                    if !albumResults.isEmpty {
                        Section(header: Text("Albums")) {
                            ForEach(albumResults) { album in
                                NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                    HStack {
                                        if let coverArtId = album.coverArt,
                                           let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                            CachedAsyncImage(url: coverURL) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
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
            }
        }
        .navigationTitle(offlineMode ? "Offline Search" : "Search")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        if !offlineMode {
                            searchResults = []
                            albumResults = []
                            artistResults = []
                        }
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
        .sheet(isPresented: $showingSearchSheet) {
            NavigationView {
                VStack(spacing: 16) {
                    TextField(offlineMode ? "Search offline music" : "Search music", text: $searchText)
                        .padding()

                    Button("Search") {
                        showingSearchSheet = false
                        if !offlineMode {
                            performSearch(query: searchText)
                        }
                        // In offline mode, the view automatically updates via computed properties
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.isEmpty)

                    Spacer()
                }
                .navigationTitle(offlineMode ? "Offline Search" : "Search")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingSearchSheet = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func songRow(song: Song) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Title and metadata - tappable to play
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        if let artist = song.artist {
                            Text(artist)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if song.album != nil && song.artist != nil {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let album = song.album {
                            Text(album)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                AudioPlayer.shared.playSong(song)
            }

            // Controls row
            HStack(spacing: 8) {
                if player.currentSong?.id == song.id && player.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                if downloadManager.isDownloading(song.id) {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if downloadManager.isDownloaded(song.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if !offlineMode {
                    Button(action: {
                        DownloadManager.shared.downloadSong(song)
                    }) {
                        Image(systemName: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink(destination: RadioOptionsView(
                    sourceSong: song,
                    sourceTitle: song.title,
                    sourceType: .song
                )) {
                    Image(systemName: "music.note.list")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            if let artistId = song.artistId, let artist = song.artist {
                NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: artist)) {
                    Label("Go to Artist", systemImage: "person.fill")
                }
            }

            if let albumId = song.albumId {
                NavigationLink(destination: AlbumDetailView(albumId: albumId)) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            albumResults = []
            artistResults = []
            return
        }

        // Debounce the search
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            guard query == searchText else { return } // Check if search text changed

            isSearching = true
            errorMessage = ""

            do {
                let result = try await NavidromeAPI.shared.search(query: query)
                await MainActor.run {
                    self.artistResults = result.artist ?? []
                    self.albumResults = result.album ?? []
                    self.searchResults = result.song ?? []
                    self.isSearching = false

                    print("🔍 Search results: \(self.artistResults.count) artists, \(self.albumResults.count) albums, \(self.searchResults.count) songs")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSearching = false
                    print("❌ Search error: \(error)")
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    NavigationView {
        TracksView()
    }
}
