//
//  PlaylistDetailView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: String
    let playlistName: String

    @State private var playlist: Playlist?
    @State private var isLoading = true
    @State private var isSyncing = false
    @State private var errorMessage = ""
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        content
        .navigationTitle("Playlist")
        .toolbar {
            if !offlineMode && playlist != nil {
                ToolbarItem(placement: .platformTopBarTrailing) {
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

    @ViewBuilder
    private var content: some View {
        if offlineMode {
            offlinePlaylistContent
        } else if isLoading {
            WRhythmLoadingState(
                systemImage: "music.note.list",
                title: "Loading playlist",
                message: nil
            )
            .wrhythmPageBackground()
        } else if !errorMessage.isEmpty {
            WRhythmErrorState(
                title: "Playlist Error",
                message: errorMessage
            ) {
                loadPlaylist()
            }
            .wrhythmPageBackground()
        } else if let playlist, let songs = playlist.entry {
            onlinePlaylistContent(playlist, songs: songs)
        }
    }

    @ViewBuilder
    private var offlinePlaylistContent: some View {
        let cachedPlaylist = downloadManager.cachedPlaylists.first { $0.id == playlistId }
        let songs = downloadedPlaylistSongs(cachedPlaylist)

        if songs.isEmpty {
            WRhythmScreen(coverArtId: cachedPlaylist?.coverArt) {
                WRhythmHeroHeader(
                    title: playlistName,
                    subtitle: "\(cachedPlaylist?.songCount ?? 0) songs total",
                    detail: "No downloaded songs",
                    systemImage: "music.note.list",
                    tint: .purple,
                    coverArtId: cachedPlaylist?.coverArt
                )

                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No downloaded songs",
                    message: "Download songs while online to play this playlist offline"
                )
            }
        } else {
            WRhythmScreen(coverArtId: cachedPlaylist?.coverArt ?? songs.first?.coverArt) {
                WRhythmHeroHeader(
                    title: playlistName,
                    subtitle: "\(songs.count) of \(cachedPlaylist?.songCount ?? songs.count) songs downloaded",
                    detail: "Offline playlist",
                    systemImage: "music.note.list",
                    tint: .purple,
                    coverArtId: cachedPlaylist?.coverArt ?? songs.first?.coverArt
                ) {
                    WRhythmActionStrip {
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
                    }
                }

                trackSection(songs: songs, queue: songs)
            }
        }
    }

    private func onlinePlaylistContent(_ playlist: Playlist, songs: [Song]) -> some View {
        WRhythmScreen(coverArtId: playlist.coverArt ?? songs.first?.coverArt) {
            WRhythmHeroHeader(
                title: playlist.name,
                subtitle: "\(playlist.songCount) song\(playlist.songCount == 1 ? "" : "s")",
                detail: "Playlist",
                systemImage: "music.note.list",
                tint: .purple,
                coverArtId: playlist.coverArt ?? songs.first?.coverArt
            ) {
                WRhythmActionStrip {
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

                    playlistDownloadButton(playlist)
                }
            }

            trackSection(songs: filteredSongs(songs), queue: songs)
        }
    }

    private func trackSection(songs: [Song], queue: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WRhythmSectionHeader(
                title: "Tracks",
                subtitle: "\(songs.count) song\(songs.count == 1 ? "" : "s")"
            )

            WRhythmCard(padding: 10) {
                VStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: offlineMode) {
                            player.playQueue(queue, startingAt: index)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playlistDownloadButton(_ playlist: Playlist) -> some View {
        if isPlaylistDownloaded(playlist) {
            Button(action: {
                downloadManager.deletePlaylist(playlist)
            }) {
                Image(systemName: "trash")
            }
            .tint(WRhythmTheme.danger)
        } else if isPlaylistDownloading(playlist) {
            Button(action: {}) {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading")
                        .font(.caption2)
                }
            }
            .disabled(true)
        } else {
            Button(action: {
                downloadManager.downloadPlaylist(playlist)
            }) {
                Image(systemName: "arrow.down.circle")
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

    private func isPlaylistDownloading(_ playlist: Playlist) -> Bool {
        guard let songs = playlist.entry else { return false }
        return songs.contains { downloadManager.isDownloading($0.id) }
    }

    private func filteredSongs(_ songs: [Song]) -> [Song] {
        if offlineMode {
            return songs.filter { downloadManager.isDownloaded($0.id) }
        }
        return songs
    }

    private func downloadedPlaylistSongs(_ playlist: CachedPlaylist?) -> [Song] {
        guard let playlist else { return [] }
        return playlist.songIds
            .filter { downloadManager.isDownloaded($0) }
            .compactMap { downloadManager.downloadedSongs[$0] }
            .map { downloaded in
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
    }
}
