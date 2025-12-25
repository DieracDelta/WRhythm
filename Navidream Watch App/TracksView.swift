//
//  TracksView.swift
//  Navidream Watch App
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
            // Convert DownloadedSong to Song
            return downloadManager.downloadedSongs.values.map { downloaded -> Song in
                Song(
                    id: downloaded.songId,
                    title: downloaded.title,
                    album: downloaded.album,
                    albumId: nil,
                    artist: downloaded.artist,
                    artistId: nil,
                    track: nil,
                    year: nil,
                    genre: nil,
                    coverArt: downloaded.coverArt,
                    size: nil,
                    contentType: nil,
                    suffix: nil,
                    duration: nil,
                    bitRate: nil,
                    path: nil
                )
            }.sorted { $0.title < $1.title }
        } else {
            return searchResults
        }
    }

    var body: some View {
        Group {
            if offlineMode {
                // Offline mode: show downloaded songs
                if displayedSongs.isEmpty {
                    VStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No downloaded songs")
                            .font(.headline)
                        Text("Download songs while online to access them here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(displayedSongs) { song in
                            songRow(song: song)
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
                                            AsyncImage(url: coverURL) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Color.gray
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
                                            AsyncImage(url: coverURL) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Color.gray
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
        .navigationTitle(offlineMode ? "Tracks (\(displayedSongs.count))" : "Search")
        .toolbar {
            if !offlineMode {
                ToolbarItem(placement: .topBarTrailing) {
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                            albumResults = []
                            artistResults = []
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
                    TextField("Search music", text: $searchText)
                        .padding()

                    Button("Search") {
                        showingSearchSheet = false
                        performSearch(query: searchText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.isEmpty)

                    Spacer()
                }
                .navigationTitle("Search")
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
                    Image(systemName: "antenna.radiowaves.left.and.right")
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
