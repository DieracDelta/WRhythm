//
//  PlaylistDetailView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: String
    let playlistName: String

    @State private var playlist: Playlist?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        Group {
            if isLoading {
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
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                Button(action: {
                                    player.playQueue(songs, startingAt: index)
                                }) {
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
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Playlist")
        .onAppear {
            loadPlaylist()
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
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func isPlaylistDownloaded(_ playlist: Playlist) -> Bool {
        guard let songs = playlist.entry else { return false }
        return songs.allSatisfy { downloadManager.isDownloaded($0.id) }
    }
}
