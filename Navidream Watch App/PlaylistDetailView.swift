//
//  PlaylistDetailView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct PlaylistSongRowView: View {
    let song: Song
    let onTap: () -> Void
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading) {
                    Text(song.title)
                        .font(.caption)
                        .lineLimit(1)
                    if let artist = song.artist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if downloadManager.isDownloading(song.id) {
                    VStack(spacing: 2) {
                        ProgressView()
                            .scaleEffect(0.7)
                        let progress = downloadManager.downloadProgress(song.id)
                        if progress > 0 {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if downloadManager.isDownloaded(song.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                if player.currentSong?.id == song.id && player.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistDetailView: View {
    let playlistId: String
    let playlistName: String

    @State private var playlist: Playlist?
    @State private var isLoading = true
    @State private var isSyncing = false
    @State private var errorMessage = ""
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var player: AudioPlayer { AudioPlayer.shared }

    var body: some View {
        Group {
            if offlineMode {
                // Offline mode: show only downloaded songs from cached playlist
                let cachedPlaylist = downloadManager.cachedPlaylists.first { $0.id == playlistId }
                let downloadedSongIds = cachedPlaylist?.songIds.filter { downloadManager.isDownloaded($0) } ?? []

                ScrollView {
                    VStack(spacing: 12) {
                        Group {
                            if let coverArtId = cachedPlaylist?.coverArt,
                               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                                AsyncImage(url: coverURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(height: 120)
                                .cornerRadius(8)
                            }
                        }
                        .id(playlistId)

                        VStack(spacing: 4) {
                            Text(playlistName)
                                .font(.headline)
                            if !downloadedSongIds.isEmpty {
                                Text("\(downloadedSongIds.count) of \(cachedPlaylist?.songCount ?? 0) songs downloaded")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(cachedPlaylist?.songCount ?? 0) songs total")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if downloadedSongIds.isEmpty {
                            Divider()

                            VStack {
                                Image(systemName: "arrow.down.circle")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No downloaded songs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Download songs while online to play them here")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        } else {
                            Divider()

                            VStack(spacing: 8) {
                                let songs = downloadedSongIds.compactMap { id in
                                    downloadManager.downloadedSongs[id]
                                }.map { downloaded in
                                    Song(
                                        id: downloaded.songId,
                                        title: downloaded.title,
                                        album: downloaded.album,
                                        albumId: downloaded.album,
                                        artist: downloaded.artist,
                                        artistId: nil,
                                        track: nil,
                                        year: nil,
                                        genre: nil,
                                        coverArt: downloaded.coverArt,
                                        size: Int(downloaded.fileSize),
                                        contentType: nil,
                                        suffix: nil,
                                        duration: nil,
                                        bitRate: nil,
                                        path: nil
                                    )
                                }

                                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                    PlaylistSongRowView(song: song) {
                                        player.playQueue(songs, startingAt: index)
                                    }
                                    .id(song.id)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else if isLoading {
                ProgressView("Loading playlist...")
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadPlaylist()
                    }
                }
            } else if let playlist = playlist, let songs = playlist.entry {
                ScrollView {
                    VStack(spacing: 12) {
                        Group {
                            if let coverArtId = playlist.coverArt,
                               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                                AsyncImage(url: coverURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(height: 120)
                                .cornerRadius(8)
                            }
                        }
                        .id(playlist.id)

                        VStack(spacing: 4) {
                            Text(playlist.name)
                                .font(.headline)
                            Text("\(playlist.songCount) songs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                player.playQueue(songs, startingAt: 0)
                            }) {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: {
                                player.playQueueShuffled(songs)
                            }) {
                                Image(systemName: "shuffle")
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            if isPlaylistDownloaded(playlist) {
                                Button(action: {
                                    downloadManager.deletePlaylist(playlist)
                                }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else {
                                Button(action: {
                                    downloadManager.downloadPlaylist(playlist)
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Divider()

                        VStack(spacing: 8) {
                            ForEach(Array(filteredSongs(songs).enumerated()), id: \.element.id) { index, song in
                                PlaylistSongRowView(song: song) {
                                    player.playQueue(songs, startingAt: index)
                                }
                                .id(song.id)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Playlist")
        .toolbar {
            if !offlineMode && playlist != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        syncPlaylist()
                    }) {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isSyncing)
                }
            }
        }
        .onAppear {
            if !offlineMode {
                loadPlaylist()
            }
        }
    }

    private func loadPlaylist() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedPlaylist = try await NavidromeAPI.shared.getPlaylist(id: playlistId)
                await MainActor.run {
                    self.playlist = fetchedPlaylist
                    self.isLoading = false
                    // Cache playlist details for offline mode
                    self.downloadManager.cachePlaylistDetails(fetchedPlaylist)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func syncPlaylist() {
        isSyncing = true

        Task {
            do {
                let fetchedPlaylist = try await NavidromeAPI.shared.getPlaylist(id: playlistId)
                await MainActor.run {
                    self.playlist = fetchedPlaylist
                    self.isSyncing = false
                    // Update cached playlist details
                    self.downloadManager.cachePlaylistDetails(fetchedPlaylist)
                }
                print("✅ Synced playlist: \(playlistName)")
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSyncing = false
                }
                print("❌ Failed to sync playlist: \(error)")
            }
        }
    }

    private func isPlaylistDownloaded(_ playlist: Playlist) -> Bool {
        guard let songs = playlist.entry else { return false }
        return songs.allSatisfy { downloadManager.isDownloaded($0.id) }
    }

    private func filteredSongs(_ songs: [Song]) -> [Song] {
        if offlineMode {
            return songs.filter { downloadManager.isDownloaded($0.id) }
        }
        return songs
    }
}
