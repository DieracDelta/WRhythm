//
//  TrackRowView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/25/25.
//

import SwiftUI

struct TrackRowView: View {
    let song: Song
    let onTap: () -> Void
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let artist = song.artist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    // Download/Delete button
                    if downloadManager.isDownloaded(song.id) {
                        if !offlineMode {
                            // Online mode: tappable to delete
                            Button(action: {
                                downloadManager.deleteSong(song.id)
                            }) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Offline mode: just an indicator
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    } else if !offlineMode {
                        Button(action: {
                            downloadManager.downloadSong(song)
                        }) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    // Heart/favorite button (online mode only)
                    if !offlineMode {
                        Button(action: {
                            toggleFavorite()
                        }) {
                            Image(systemName: downloadManager.starredSongIds.contains(song.id) ? "heart.fill" : "heart")
                                .font(.caption2)
                                .foregroundColor(downloadManager.starredSongIds.contains(song.id) ? .red : .gray)
                        }
                        .buttonStyle(.plain)
                    }

                    // Radio button (online mode only) - navigate to radio options
                    if !offlineMode {
                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "music.note.list")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    // Now playing indicator
                    if player.currentSong?.id == song.id && player.isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleFavorite() {
        let isStarred = downloadManager.starredSongIds.contains(song.id)

        Task {
            do {
                if isStarred {
                    try await NavidromeAPI.shared.unstar(songId: song.id)
                    await MainActor.run {
                        downloadManager.unstarSong(song.id, isOffline: false)
                    }
                } else {
                    try await NavidromeAPI.shared.star(songId: song.id)
                    await MainActor.run {
                        downloadManager.starSong(song.id, isOffline: false)
                    }
                }
            } catch {
                print("❌ Failed to toggle favorite: \(error)")
            }
        }
    }
}
