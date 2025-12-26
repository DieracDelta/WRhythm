//
//  RadioPlaylistsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/24/25.
//

import SwiftUI

struct RadioPlaylistsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        List {
            if downloadManager.radioPlaylists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Radio Playlists")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Download a radio to play it offline")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ForEach(downloadManager.radioPlaylists) { radio in
                    RadioPlaylistRow(radio: radio)
                }
            }
        }
        .navigationTitle("Radio Playlists")
    }
}

struct RadioPlaylistRow: View {
    let radio: RadioPlaylist
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        NavigationLink(destination: RadioPlaylistDetailView(radio: radio)) {
            HStack {
                if let coverArtId = radio.coverArt,
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
                        Label("Delete Radio", systemImage: "trash")
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
                        ForEach(Array(downloadedSongs.enumerated()), id: \.offset) { index, songId in
                            if let downloadedSong = downloadManager.downloadedSongs[songId] {
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
                                TrackRowView(song: song) {
                                    playRadio(startingAt: index)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Radio")
    }

    private var downloadedSongs: [String] {
        radio.songIds.filter { downloadManager.isDownloaded($0) }
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
