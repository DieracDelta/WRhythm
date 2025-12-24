//
//  DownloadsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct DownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared

    private var player: AudioPlayer { AudioPlayer.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Show active downloads if any
                if !downloadManager.activeDownloads.isEmpty {
                    NavigationLink(destination: ActiveDownloadsView()) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text("\(downloadManager.activeDownloads.count) downloading")
                                    .font(.caption)
                                Text("Tap to view progress")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    Divider()
                }

                if downloadManager.downloadedSongs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Downloads")
                            .font(.headline)
                        Text("Download songs, albums, or playlists for offline playback")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(spacing: 8) {
                        Text("\(downloadManager.getTotalDownloaded()) songs")
                            .font(.headline)
                        Text(formatBytes(downloadManager.getTotalSize()))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: {
                            downloadManager.deleteAll()
                        }) {
                            Label("Delete All", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.vertical, 8)

                    Divider()

                    VStack(spacing: 8) {
                        ForEach(Array(downloadManager.downloadedSongs.values.sorted(by: { $0.downloadedAt > $1.downloadedAt })), id: \.songId) { downloadedSong in
                            Button(action: {
                                // Create a temporary Song object to play
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
                                player.playSong(song)
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(downloadedSong.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        if let artist = downloadedSong.artist {
                                            Text(artist)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text(formatBytes(downloadedSong.fileSize))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button(action: {
                                        downloadManager.deleteSong(downloadedSong.songId)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)

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
            }
            .padding()
        }
        .navigationTitle("Downloads")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
