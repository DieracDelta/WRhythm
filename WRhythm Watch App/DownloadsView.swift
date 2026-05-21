//
//  DownloadsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct DownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var presentedSheet: DownloadsSheet?
    @State private var deleteConfirmationText = ""
    @State private var displayedSongCount = 20  // Start with 20 songs

    private var player: AudioPlayer { AudioPlayer.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: WRhythmVisual.sectionSpacing) {
                let totalPending = downloadManager.getTotalPendingDownloads()
                if totalPending > 0 || downloadManager.isPaused {
                    WRhythmCard(padding: 12) {
                        VStack(spacing: 10) {
                        HStack {
                            WRhythmIconBadge(systemImage: "arrow.down.circle.fill", tint: .blue, size: 30)
                            Text("Download Status")
                                .font(.headline)
                            Spacer()
                        }

                        VStack(spacing: 4) {
                            WRhythmMetricRow(
                                title: "Completed",
                                value: "\(downloadManager.sessionCompletedCount)",
                                valueColor: .green
                            )

                            WRhythmMetricRow(
                                title: "Active",
                                value: "\(downloadManager.getActiveDownloadCount())",
                                valueColor: .blue
                            )

                            WRhythmMetricRow(
                                title: "Queued",
                                value: "\(downloadManager.getQueuedDownloadCount())",
                                valueColor: .orange
                            )

                            WRhythmMetricRow(title: "Total", value: "\(downloadManager.sessionTotalCount)")

                            if downloadManager.getActiveDownloadCount() > 0 {
                                let avgProgress = downloadManager.getAverageDownloadProgress()
                                WRhythmMetricRow(title: "Avg Progress", value: "\(Int(avgProgress * 100))%")

                                ProgressView(value: avgProgress)
                                    .progressViewStyle(.linear)
                                    .tint(.blue)

                                Divider()
                                    .padding(.vertical, 2)

                                let totalBytes = downloadManager.getTotalBytesToDownload()
                                let downloadedBytes = downloadManager.getTotalBytesDownloaded()
                                let remainingBytes = downloadManager.getBytesRemaining()

                                VStack(spacing: 4) {
                                    WRhythmMetricRow(title: "Downloaded", value: formatBytes(downloadedBytes), valueColor: .green)
                                    WRhythmMetricRow(title: "Total Size", value: formatBytes(totalBytes))
                                    WRhythmMetricRow(title: "Remaining", value: formatBytes(remainingBytes), valueColor: .orange)

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
                                    Image(systemName: "play.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            } else {
                                Button(action: {
                                    downloadManager.pauseDownloads()
                                }) {
                                    Image(systemName: "pause.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                            }

                            Button(action: {
                                downloadManager.restartDownloads()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)

                            Button(action: {
                                downloadManager.cancelAllDownloads()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        NavigationLink(destination: ActiveDownloadsView()) {
                            HStack {
                                Text("View Details")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    }
                }

                if downloadManager.downloadedSongs.isEmpty {
                    WRhythmEmptyState(
                        systemImage: "arrow.down.circle",
                        title: "No Downloads",
                        message: "Download songs, albums, or playlists for offline playback"
                    )
                } else {
                    WRhythmCard {
                        HStack(spacing: 12) {
                            WRhythmIconBadge(systemImage: "internaldrive", tint: .green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(downloadManager.getTotalDownloaded()) songs")
                                    .font(.headline)
                                Text(formatBytes(downloadManager.getTotalSize()))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: {
                                presentedSheet = .deleteAll
                                deleteConfirmationText = ""
                            }) {
                                Label("Delete All", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .sheet(item: $presentedSheet) { sheet in
                            switch sheet {
                            case .deleteAll:
                            NavigationView {
                                VStack(spacing: 16) {
                                    Text("Delete All Downloads?")
                                        .font(.headline)

                                    Text("This will delete \(downloadManager.getTotalDownloaded()) songs (\(formatBytes(downloadManager.getTotalSize())))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)

                                    Text("Type DELETE to confirm")
                                        .font(.caption)
                                        .foregroundColor(.red)

                                    TextField("Type DELETE", text: $deleteConfirmationText)
                                        .platformAutocapitalizationCharacters()
                                        .padding()

                                    Button(action: {
                                        downloadManager.deleteAll()
                                        presentedSheet = nil
                                        deleteConfirmationText = ""
                                    }) {
                                        Text("Delete All")
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .disabled(deleteConfirmationText != "DELETE")

                                    Spacer()
                                }
                                .padding()
                                .navigationTitle("Confirm Delete")
                                .platformNavigationBarTitleDisplayModeInline()
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Cancel") {
                                            presentedSheet = nil
                                            deleteConfirmationText = ""
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }

                    let sortedSongs = Array(downloadManager.downloadedSongs.values.sorted(by: { $0.downloadedAt > $1.downloadedAt }))
                    let songsToDisplay = Array(sortedSongs.prefix(displayedSongCount))

                    LazyVStack(spacing: 8) {
                        ForEach(songsToDisplay, id: \.songId) { downloadedSong in
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
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
                            .onAppear {
                                // Load more songs when we reach the last visible song
                                if downloadedSong.songId == songsToDisplay.last?.songId && displayedSongCount < sortedSongs.count {
                                    displayedSongCount = min(displayedSongCount + 20, sortedSongs.count)
                                }
                            }
                        }

                        // Show "Load More" button if there are more songs
                        if displayedSongCount < sortedSongs.count {
                            Button(action: {
                                displayedSongCount = min(displayedSongCount + 20, sortedSongs.count)
                            }) {
                                HStack {
                                    Text("Load More (\(sortedSongs.count - displayedSongCount) remaining)")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Downloads")
        .wrhythmPageBackground()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private enum DownloadsSheet: String, Identifiable {
    case deleteAll

    var id: String { rawValue }
}
