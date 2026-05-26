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
        WRhythmScreen {
            let sortedSongs = Array(downloadManager.downloadedSongs.values.sorted(by: { $0.downloadedAt > $1.downloadedAt }))
            let songsToDisplay = Array(sortedSongs.prefix(displayedSongCount))

            if downloadManager.getTotalPendingDownloads() > 0 || downloadManager.isPaused {
                downloadStatusCard
            }

            if sortedSongs.isEmpty {
#if os(iOS)
                PhoneDownloadsEmptyView(message: emptyDownloadsMessage)
#else
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No Downloads",
                    message: emptyDownloadsMessage
                )
#endif
            } else {
                downloadedSummaryCard

                LazyVStack(spacing: WRhythmSpacing.xs) {
                    ForEach(songsToDisplay, id: \.songId) { downloadedSong in
                        downloadedSongRow(downloadedSong)
                            .onAppear {
                                if downloadedSong.songId == songsToDisplay.last?.songId && displayedSongCount < sortedSongs.count {
                                    displayedSongCount = min(displayedSongCount + 20, sortedSongs.count)
                                }
                            }
                    }

                    if displayedSongCount < sortedSongs.count {
                        Button(action: {
                            displayedSongCount = min(displayedSongCount + 20, sortedSongs.count)
                        }) {
                            Label("Load \(sortedSongs.count - displayedSongCount) more", systemImage: "chevron.down")
                                .font(WRhythmTypography.controlLabel)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(WRhythmTheme.secondaryAccent)
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .deleteAll:
                deleteAllSheet
            }
        }
    }

    private var downloadStatusCard: some View {
        WRhythmCard {
            VStack(spacing: WRhythmSpacing.sm) {
                WRhythmSectionHeader(title: "Download Status") {
                    WRhythmIconBadge(systemImage: "arrow.down.circle.fill", tint: WRhythmTheme.downloads, size: 30)
                }

                VStack(spacing: WRhythmSpacing.xxs) {
                    WRhythmMetricRow(title: "Completed", value: "\(downloadManager.sessionCompletedCount)", valueColor: WRhythmTheme.success)
                    WRhythmMetricRow(title: "Active", value: "\(downloadManager.getActiveDownloadCount())", valueColor: WRhythmTheme.secondaryAccent)
                    WRhythmMetricRow(title: "Queued", value: "\(downloadManager.getQueuedDownloadCount())", valueColor: WRhythmTheme.warning)
                    WRhythmMetricRow(title: "Total", value: "\(downloadManager.sessionTotalCount)")
                }

                if downloadManager.getActiveDownloadCount() > 0 {
                    activeProgressSection
                }

                WRhythmActionStrip {
                    Button(action: {
                        if downloadManager.isPaused {
                            downloadManager.resumeDownloads()
                        } else {
                            downloadManager.pauseDownloads()
                        }
                    }) {
                        Image(systemName: downloadManager.isPaused ? "play.fill" : "pause.fill")
                    }
                    .tint(downloadManager.isPaused ? WRhythmTheme.success : WRhythmTheme.accent)

                    Button(action: downloadManager.restartDownloads) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(WRhythmTheme.secondaryAccent)

                    Button(action: downloadManager.cancelAllDownloads) {
                        Image(systemName: "xmark")
                    }
                    .tint(WRhythmTheme.danger)
                }

                NavigationLink(destination: ActiveDownloadsView()) {
                    Label("View Details", systemImage: "chevron.right")
                        .font(WRhythmTypography.controlLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundColor(WRhythmTheme.secondaryAccent)
            }
        }
    }

    private var activeProgressSection: some View {
        VStack(spacing: WRhythmSpacing.xs) {
            let avgProgress = downloadManager.getAverageDownloadProgress()
            WRhythmMetricRow(title: "Avg Progress", value: "\(Int(avgProgress * 100))%")
            ProgressView(value: avgProgress)
                .progressViewStyle(.linear)
                .tint(WRhythmTheme.secondaryAccent)

            Divider()

            let totalBytes = downloadManager.getTotalBytesToDownload()
            let downloadedBytes = downloadManager.getTotalBytesDownloaded()
            let remainingBytes = downloadManager.getBytesRemaining()
            WRhythmMetricRow(title: "Downloaded", value: formatBytes(downloadedBytes), valueColor: WRhythmTheme.success)
            WRhythmMetricRow(title: "Total Size", value: formatBytes(totalBytes))
            WRhythmMetricRow(title: "Remaining", value: formatBytes(remainingBytes), valueColor: WRhythmTheme.warning)

            if totalBytes > 0 {
                ProgressView(value: Double(downloadedBytes) / Double(totalBytes))
                    .progressViewStyle(.linear)
                    .tint(WRhythmTheme.success)
            }
        }
    }

    private var downloadedSummaryCard: some View {
        WRhythmCard {
            HStack(spacing: WRhythmSpacing.sm) {
                WRhythmIconBadge(systemImage: "internaldrive", tint: WRhythmTheme.downloads)

                VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                    Text("\(downloadManager.getTotalDownloaded()) songs")
                        .font(WRhythmTypography.featureTitle)
                    Text(formatBytes(downloadManager.getTotalSize()))
                        .font(WRhythmTypography.rowSubtitle)
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
                .tint(WRhythmTheme.danger)
            }
        }
    }

    private func downloadedSongRow(_ downloadedSong: DownloadedSong) -> some View {
        Button(action: {
            player.playSong(song(from: downloadedSong))
        }) {
            HStack(spacing: WRhythmSpacing.sm) {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                    Text(downloadedSong.title)
                        .font(WRhythmTypography.rowTitle)
                        .lineLimit(1)
                    if let artist = downloadedSong.artist {
                        Text(artist)
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(formatBytes(downloadedSong.fileSize))
                        .font(WRhythmTypography.metadata)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if player.currentSong?.id == downloadedSong.songId && player.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(WRhythmTypography.metadata)
                        .foregroundColor(WRhythmTheme.accent)
                }

                WRhythmRowIconButton(
                    systemImage: "trash",
                    tint: WRhythmTheme.danger,
                    accessibilityLabel: "Delete download"
                ) {
                    downloadManager.deleteSong(downloadedSong.songId)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(WRhythmSpacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
    }

    private var deleteAllSheet: some View {
        NavigationStack {
            WRhythmScreen {
                WRhythmCard {
                    VStack(spacing: WRhythmSpacing.md) {
                        Text("Delete All Downloads?")
                            .font(WRhythmTypography.featureTitle)

                        Text("This will delete \(downloadManager.getTotalDownloaded()) songs (\(formatBytes(downloadManager.getTotalSize())))")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Type DELETE to confirm")
                            .font(WRhythmTypography.controlLabel)
                            .foregroundColor(WRhythmTheme.danger)

                        TextField("Type DELETE", text: $deleteConfirmationText)
                            .platformAutocapitalizationCharacters()
                            .platformSearchTextFieldStyle()

                        Button(action: {
                            downloadManager.deleteAll()
                            presentedSheet = nil
                            deleteConfirmationText = ""
                        }) {
                            Text("Delete All")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WRhythmTheme.danger)
                        .disabled(deleteConfirmationText != "DELETE")
                    }
                }
            }
            .navigationTitle("Confirm Delete")
            .platformNavigationBarTitleDisplayModeInline()
            .platformModalCloseToolbar {
                presentedSheet = nil
                deleteConfirmationText = ""
            }
        }
        .platformExplicitCloseModal()
    }

    private var emptyDownloadsMessage: String? {
#if os(iOS) || os(watchOS)
        nil
#else
        "Download songs, albums, or playlists for offline playback"
#endif
    }

    private var navigationTitleText: String {
#if os(iOS)
        downloadManager.downloadedSongs.isEmpty ? "" : "Downloads"
#else
        "Downloads"
#endif
    }

    private func song(from downloadedSong: DownloadedSong) -> Song {
        Song(
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
    }

    private func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

private enum DownloadsSheet: String, Identifiable {
    case deleteAll

    var id: String { rawValue }
}
