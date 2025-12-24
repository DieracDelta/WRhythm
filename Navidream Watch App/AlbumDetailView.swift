//
//  AlbumDetailView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct AlbumDetailView: View {
    let albumId: String

    @State private var album: Album?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        ZStack {
            if offlineMode {
                // Offline mode: build album from downloaded songs
                let downloadedSongs = downloadManager.downloadedSongs.values.filter { $0.album == albumId }
                if downloadedSongs.isEmpty {
                    VStack {
                        Text("Error")
                            .font(.headline)
                        Text("No downloaded songs for this album")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let coverArtId = downloadedSongs.first?.coverArt,
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

                            VStack(spacing: 4) {
                                Text(downloadedSongs.first?.album ?? "Unknown Album")
                                    .font(.headline)
                                if let artist = downloadedSongs.first?.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Button(action: {
                                    // Build Song array from downloaded songs
                                    let songs = downloadedSongs.map { downloaded in
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
                                    }.sorted { ($0.track ?? 999) < ($1.track ?? 999) }
                                    player.playQueue(songs, startingAt: 0)
                                }) {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                Button(action: {
                                    let songs = downloadedSongs.map { downloaded in
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
                                    player.playQueueShuffled(songs)
                                }) {
                                    Image(systemName: "shuffle")
                                }
                                .buttonStyle(.bordered)
                            }

                            Divider()

                            VStack(spacing: 8) {
                                ForEach(Array(downloadedSongs.enumerated()), id: \.element.songId) { index, downloadedSong in
                                    Button(action: {
                                        let songs = downloadedSongs.map { downloaded in
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
                                        }.sorted { ($0.track ?? 999) < ($1.track ?? 999) }
                                        player.playQueue(songs, startingAt: index)
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(downloadedSong.title)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.green)

                                            if player.currentSong?.id == downloadedSong.songId && player.isPlaying {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                }
            } else if isLoading {
                ProgressView("Loading album...")
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadAlbum()
                    }
                }
            } else if let album = album {
                ScrollView {
                    VStack(spacing: 12) {
                        if let coverArtId = album.coverArt,
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

                        VStack(spacing: 4) {
                            Text(album.name)
                                .font(.headline)
                            if let artist = album.artist {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let year = album.year {
                                Text(String(year))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                player.playQueue(album.song, startingAt: 0)
                            }) {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: {
                                player.playQueueShuffled(album.song)
                            }) {
                                Image(systemName: "shuffle")
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            if isAlbumDownloaded(album) {
                                Button(action: {
                                    downloadManager.deleteAlbum(album)
                                }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else {
                                Button(action: {
                                    downloadManager.downloadAlbum(album)
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Divider()

                        VStack(spacing: 8) {
                            ForEach(Array(filteredSongs(album.song).enumerated()), id: \.element.id) { index, song in
                                Button(action: {
                                    player.playQueue(album.song, startingAt: index)
                                }) {
                                    HStack {
                                        if let track = song.track {
                                            Text("\(track)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 20, alignment: .leading)
                                        }

                                        VStack(alignment: .leading) {
                                            Text(song.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            if let duration = song.duration {
                                                Text(formatDuration(duration))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
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
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Album")
        .onAppear {
            if !offlineMode {
                loadAlbum()
            }
        }
    }

    private func loadAlbum() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedAlbum = try await NavidromeAPI.shared.getAlbum(id: albumId)
                await MainActor.run {
                    self.album = fetchedAlbum
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func isAlbumDownloaded(_ album: Album) -> Bool {
        return album.song.allSatisfy { downloadManager.isDownloaded($0.id) }
    }

    private func filteredSongs(_ songs: [Song]) -> [Song] {
        if offlineMode {
            return songs.filter { downloadManager.isDownloaded($0.id) }
        }
        return songs
    }
}
