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
        Group {
            if player.playlistGenIsGenerating {
                playlistGenerationLoadingView
            } else if player.playlistGenQueue.isEmpty && downloadManager.radioPlaylists.isEmpty {
#if os(iOS)
                WRhythmScreen {
                    PhoneDetailHeader(title: "Playlist Gen")

                    PhonePlaylistGenEmptyView()
                        .padding(.top, WRhythmSpacing.lg)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
#else
                List {
                    WRhythmEmptyState(
                        systemImage: "music.note.list",
                        title: "No Playlist Gen",
                        message: "Start Playlist Gen from a song, album, artist, or playlist"
                    )
                    .listRowBackground(Color.clear)
                }
                .navigationTitle("Playlist Gen")
                .wrhythmListSurface()
#endif
            } else {
                List {
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
        .safeAreaInset(edge: .bottom) {
            if let message = player.playlistGenErrorMessage {
                playlistGenerationErrorView(message: message, details: player.playlistGenErrorDetails)
                    .padding(.horizontal, WRhythmSpacing.md)
                    .padding(.bottom, WRhythmSpacing.sm)
            }
        }
    }

    private var playlistGenerationLoadingView: some View {
        List {
            WRhythmCard(padding: WRhythmSpacing.md) {
                VStack(spacing: WRhythmSpacing.sm) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Generating Playlist")
                        .font(.headline)
                    if let title = player.playlistGenGeneratingTitle {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button("Cancel", role: .cancel) {
                        player.cancelPlaylistGeneration()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Playlist Gen")
        .wrhythmListSurface()
    }

    private func playlistGenerationErrorView(message: String, details: String?) -> some View {
        VStack(spacing: 3) {
            Text(message)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WRhythmTheme.danger)
            if let details {
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button(action: player.dismissPlaylistGenError) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Playlist Gen error")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
    }
}

struct CurrentPlaylistGenSummary: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        WRhythmCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                WRhythmCollectionRow(
                    title: player.playlistGenSourceTitle ?? "Current Playlist Gen",
                    subtitle: player.playlistGenSourceArtist,
                    detail: "\(player.playlistGenQueue.count) songs",
                    coverArtId: player.playlistGenQueue.first?.coverArt,
                    fallbackSystemImage: "music.note.list",
                    tint: WRhythmTheme.playlistGen
                )

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
        }
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
            let downloadedCount = radio.songIds.filter { downloadManager.isDownloaded($0) }.count
            WRhythmCollectionRow(
                title: radio.sourceSongTitle,
                subtitle: radio.sourceSongArtist,
                detail: "\(downloadedCount)/\(radio.songIds.count) songs",
                coverArtId: radio.coverArt,
                fallbackSystemImage: "radio",
                tint: WRhythmTheme.playlistGen
            )
        }
        .buttonStyle(.plain)
    }
}

struct RadioPlaylistDetailView: View {
    let radio: RadioPlaylist
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        WRhythmScreen(coverArtId: radio.coverArt) {
            let downloadedSongs = radio.songIds.filter { downloadManager.isDownloaded($0) }

            WRhythmHeroHeader(
                title: radio.sourceSongTitle,
                subtitle: radio.sourceSongArtist,
                detail: "\(downloadedSongs.count) of \(radio.songIds.count) songs downloaded",
                systemImage: "radio",
                tint: WRhythmTheme.playlistGen,
                coverArtId: radio.coverArt
            )

            WRhythmActionStrip {
                if !downloadedSongs.isEmpty {
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
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(WRhythmTheme.danger)
                .accessibilityLabel("Delete Playlist Gen")
            }

            if downloadedSongs.isEmpty {
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No downloaded songs",
                    message: "Download this Playlist Gen before playing it offline"
                )
            } else {
                WRhythmSectionHeader(title: "Songs", subtitle: "\(downloadedSongs.count) ready")

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
        .navigationTitle("Playlist Gen")
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
