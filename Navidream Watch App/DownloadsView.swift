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
                // Download Statistics Panel
                let totalPending = downloadManager.getTotalPendingDownloads()
                if totalPending > 0 || downloadManager.isPaused {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                            Text("Download Status")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                        }

                        VStack(spacing: 4) {
                            HStack {
                                Text("Completed:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(downloadManager.sessionCompletedCount)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }

                            HStack {
                                Text("Active:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(downloadManager.getActiveDownloadCount())")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }

                            HStack {
                                Text("Queued:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(downloadManager.getQueuedDownloadCount())")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                            }

                            HStack {
                                Text("Total:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(downloadManager.sessionTotalCount)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                            }

                            if downloadManager.getActiveDownloadCount() > 0 {
                                let avgProgress = downloadManager.getAverageDownloadProgress()
                                HStack {
                                    Text("Avg Progress:")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(avgProgress * 100))%")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }

                                ProgressView(value: avgProgress)
                                    .progressViewStyle(.linear)
                                    .tint(.blue)

                                Divider()
                                    .padding(.vertical, 2)

                                let totalBytes = downloadManager.getTotalBytesToDownload()
                                let downloadedBytes = downloadManager.getTotalBytesDownloaded()
                                let remainingBytes = downloadManager.getBytesRemaining()

                                VStack(spacing: 4) {
                                    HStack {
                                        Text("Downloaded:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatBytes(downloadedBytes))
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.green)
                                    }

                                    HStack {
                                        Text("Total Size:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatBytes(totalBytes))
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }

                                    HStack {
                                        Text("Remaining:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatBytes(remainingBytes))
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                    }

                                    if totalBytes > 0 {
                                        let bytesProgress = Double(downloadedBytes) / Double(totalBytes)
                                        ProgressView(value: bytesProgress)
                                            .progressViewStyle(.linear)
                                            .tint(.green)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        HStack(spacing: 8) {
                            if downloadManager.isPaused {
                                Button(action: {
                                    downloadManager.resumeDownloads()
                                }) {
                                    Label("Resume", systemImage: "play.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            } else {
                                Button(action: {
                                    downloadManager.pauseDownloads()
                                }) {
                                    Label("Pause", systemImage: "pause.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                            }

                            Button(action: {
                                downloadManager.restartDownloads()
                            }) {
                                Label("Restart", systemImage: "arrow.clockwise")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)

                            Button(action: {
                                downloadManager.cancelAllDownloads()
                            }) {
                                Label("Cancel All", systemImage: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        NavigationLink(destination: ActiveDownloadsView()) {
                            HStack {
                                Text("View Details")
                                    .font(.caption2)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

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
