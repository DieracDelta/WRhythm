//
//  RadioPlaylistsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/24/25.
//

import SwiftUI

struct RadioPlaylistsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        List {
            if player.playlistGenQueue.isEmpty && downloadManager.radioPlaylists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Playlist Gen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Start Playlist Gen from a song, album, artist, or playlist")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }

            if !player.playlistGenQueue.isEmpty {
                Section("Current Playlist Gen") {
                    CurrentPlaylistGenSummary()

                    ForEach(Array(player.playlistGenQueue.enumerated()), id: \.element.id) { index, song in
                        TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: false) {
                            player.playQueue(player.playlistGenQueue, startingAt: index, clearGeneratedPlaylist: false)
                        }
                    }
                }
            }

            if !downloadManager.radioPlaylists.isEmpty {
                Section("Downloaded Playlist Gen") {
                    ForEach(downloadManager.radioPlaylists) { radio in
                        RadioPlaylistRow(radio: radio)
                    }
                }
            }
        }
        .navigationTitle("Playlist Gen")
        .wrhythmListSurface()
    }
}

struct CurrentPlaylistGenSummary: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.playlistGenSourceTitle ?? "Current Playlist Gen")
                    .font(.headline)
                    .lineLimit(1)

                if let artist = player.playlistGenSourceArtist {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text("\(player.playlistGenQueue.count) songs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: playCurrentPlaylist) {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: downloadCurrentPlaylist) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    player.clearPlaylistGen()
                }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Clear Playlist Gen")
            }
        }
        .padding(.vertical, 4)
    }

    private func playCurrentPlaylist() {
        player.playQueue(player.playlistGenQueue, startingAt: 0, clearGeneratedPlaylist: false)
    }

    private func downloadCurrentPlaylist() {
        guard let sourceSong = player.playlistGenQueue.first else { return }

        for song in player.playlistGenQueue {
            downloadManager.downloadSong(song)
        }

        downloadManager.saveRadioPlaylist(sourceSong: sourceSong, songs: player.playlistGenQueue)
    }
}

struct RadioPlaylistRow: View {
    let radio: RadioPlaylist
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        NavigationLink(destination: RadioPlaylistDetailView(radio: radio)) {
            HStack {
                WRhythmArtworkThumbnail(coverArtId: radio.coverArt, fallbackSystemImage: "radio", size: 42)

                VStack(alignment: .leading) {
                    Text(radio.sourceSongTitle)
                        .font(.caption)
                        .lineLimit(1)
                    if let artist = radio.sourceSongArtist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    let downloadedCount = radio.songIds.filter { downloadManager.isDownloaded($0) }.count
                    Text("\(downloadedCount)/\(radio.songIds.count) songs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct RadioPlaylistDetailView: View {
    let radio: RadioPlaylist
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let coverArtId = radio.coverArt,
                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                    CachedAsyncImage(url: coverURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .frame(height: 120)
                    .cornerRadius(8)
                }

                VStack(spacing: 4) {
                    Text(radio.sourceSongTitle)
                        .font(.headline)
                    if let artist = radio.sourceSongArtist {
                        Text(artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    let downloadedSongs = radio.songIds.filter { downloadManager.isDownloaded($0) }
                    Text("\(downloadedSongs.count) of \(radio.songIds.count) songs downloaded")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if !downloadedSongs.isEmpty {
                    HStack(spacing: 8) {
                        Button(action: {
                            playRadio()
                        }) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: {
                            shuffleRadio()
                        }) {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: {
                        deleteRadio()
                    }) {
                        Label("Delete Playlist Gen", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Divider()

                if downloadedSongs.isEmpty {
                    VStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No downloaded songs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    VStack(spacing: 8) {
                        ForEach(downloadedSongItems) { item in
                            if let downloadedSong = downloadManager.downloadedSongs[item.songId] {
                                let song = Song(
                                    id: downloadedSong.songId,
                                    title: downloadedSong.title,
                                    album: downloadedSong.album,
                                    albumId: nil,
                                    artist: downloadedSong.artist,
                                    artistId: nil,
                                    track: nil,
                                    year: nil,
                                    genre: nil,
                                    coverArt: downloadedSong.coverArt,
                                    size: Int(downloadedSong.fileSize),
                                    contentType: nil,
                                    suffix: nil,
                                    duration: nil,
                                    bitRate: nil,
                                    path: downloadedSong.filePath
                                )
                                TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: true) {
                                    playRadio(startingAt: item.index)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Playlist Gen")
        .wrhythmPageBackground(coverArtId: radio.coverArt)
    }

    private var downloadedSongs: [String] {
        radio.songIds.filter { downloadManager.isDownloaded($0) }
    }

    private var downloadedSongItems: [DownloadedRadioSongItem] {
        downloadedSongs.enumerated().map { index, songId in
            DownloadedRadioSongItem(index: index, songId: songId)
        }
    }

    private func playRadio(startingAt index: Int = 0) {
        let songs = downloadedSongs.compactMap { songId -> Song? in
            guard let downloaded = downloadManager.downloadedSongs[songId] else { return nil }
            return Song(
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
                size: Int(downloaded.fileSize),
                contentType: nil,
                suffix: nil,
                duration: nil,
                bitRate: nil,
                path: downloaded.filePath
            )
        }

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs in radio")
            return
        }

        player.playQueue(songs, startingAt: index)
    }

    private func shuffleRadio() {
        let songs = downloadedSongs.compactMap { songId -> Song? in
            guard let downloaded = downloadManager.downloadedSongs[songId] else { return nil }
            return Song(
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
                size: Int(downloaded.fileSize),
                contentType: nil,
                suffix: nil,
                duration: nil,
                bitRate: nil,
                path: downloaded.filePath
            )
        }

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs in radio")
            return
        }

        player.playQueueShuffled(songs)
    }

    private func deleteRadio() {
        downloadManager.deleteRadioPlaylist(radio.id)
    }
}

private struct DownloadedRadioSongItem: Identifiable {
    let index: Int
    let songId: String

    var id: String {
        "\(songId)-\(index)"
    }
}
