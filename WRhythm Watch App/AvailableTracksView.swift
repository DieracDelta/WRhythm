//
//  AvailableTracksView.swift
//  WRhythm Watch App
//
//  Created by Codex on 5/24/26.
//

import SwiftUI

struct AvailableTracksPresentationPolicy: Sendable {
    static func summary(
        previousReadyCount: Int,
        nextReadyCount: Int,
        downloadingCount: Int,
        pausedCount: Int = 0
    ) -> String {
        var parts: [String] = []
        if previousReadyCount > 0 || nextReadyCount > 0 {
            parts.append("\(previousReadyCount) prev avail")
            parts.append("\(nextReadyCount) next avail")
        }
        if downloadingCount > 0 {
            parts.append("\(downloadingCount) downloading")
        }
        if pausedCount > 0 {
            parts.append("\(pausedCount) paused")
        }
        return parts.isEmpty ? "No tracks ready" : parts.joined(separator: " | ")
    }
}

struct AvailableTracksView: View {
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        BufferedTracksListContent(
            availableSongs: player.availablePrebufferedSongs,
            previousSongs: player.retainedPrebufferedSongs,
            nextSongs: player.prebufferedSongs,
            downloadStatuses: player.prebufferDownloadStatuses,
            qualityLabels: player.availablePrebufferedTrackQualityLabels
        )
        .navigationTitle("Available Tracks")
        .platformNavigationBarTitleDisplayModeInline()
    }
}

struct BufferedTracksListView: View {
    var availableSongs: [Song] = []
    var previousSongs: [Song] = []
    var nextSongs: [Song] = []
    var downloadStatuses: [PrebufferDownloadStatus] = []
    var qualityLabels: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    init(
        availableSongs: [Song] = [],
        previousSongs: [Song] = [],
        nextSongs: [Song] = [],
        downloadStatuses: [PrebufferDownloadStatus] = [],
        qualityLabels: [String: String] = [:]
    ) {
        self.availableSongs = availableSongs
        self.previousSongs = previousSongs
        self.nextSongs = nextSongs
        self.downloadStatuses = downloadStatuses
        self.qualityLabels = qualityLabels
    }

    init(songs: [Song], downloadStatuses: [PrebufferDownloadStatus] = [], qualityLabels: [String: String] = [:]) {
        self.previousSongs = []
        self.nextSongs = songs
        self.downloadStatuses = downloadStatuses
        self.qualityLabels = qualityLabels
    }

    var body: some View {
        NavigationStack {
            BufferedTracksListContent(
                availableSongs: availableSongs,
                previousSongs: previousSongs,
                nextSongs: nextSongs,
                downloadStatuses: downloadStatuses,
                qualityLabels: qualityLabels
            )
                .navigationTitle("Available Tracks")
                .platformNavigationBarTitleDisplayModeInline()
                .platformModalCloseToolbar {
                    dismiss()
                }
        }
        .platformExplicitCloseModal()
    }
}

private struct BufferedTracksListContent: View {
    @ObservedObject private var player = AudioPlayer.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    let availableSongs: [Song]
    let previousSongs: [Song]
    let nextSongs: [Song]
    var downloadStatuses: [PrebufferDownloadStatus]
    var qualityLabels: [String: String]

    private var readySongs: [Song] {
        availableSongs.isEmpty ? previousSongs + nextSongs : availableSongs
    }

    var body: some View {
        WRhythmScreen(contentMaxWidth: 920) {
            if readySongs.isEmpty && downloadStatuses.isEmpty {
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No Available Tracks",
                    message: "Queue tracks appear here while downloading and after they are ready to play."
                )
            } else {
                VStack(spacing: WRhythmSpacing.md) {
                    restoreSection
                    downloadingSection
                    availableSection(title: "Available", songs: readySongs)
                }
            }
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        if player.availableTracksQueueRestoreAvailable {
            Button {
                player.restoreQueueBeforeAvailableTracks()
            } label: {
                Label("Restore Previous Queue", systemImage: "arrow.uturn.backward")
                    .font(WRhythmTypography.rowTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WRhythmTheme.accent)
        }
    }

    @ViewBuilder
    private var downloadingSection: some View {
        if !downloadStatuses.isEmpty {
            WRhythmCard {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    WRhythmSectionHeader(title: "Downloading")
                    SlidingRenderWindowForEach(
                        downloadStatuses,
                        estimatedRowHeight: 58,
                        resetToken: SongRenderWindowPolicy.prebufferDownloadStatusesResetToken(
                            statusIds: downloadStatuses.map(\.id)
                        )
                    ) { _, status in
                        WRhythmMediaRow(
                            title: status.song.title,
                            subtitle: status.song.artist,
                            detail: status.song.album,
                            coverArtId: status.song.coverArt,
                            artworkSize: 42
                        ) {
                            Text(statusLabel(for: status))
                                .font(WRhythmTypography.metadata.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(status.isPaused ? .secondary : WRhythmTheme.warning)
                        }

                        if status.id != downloadStatuses.last?.id {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    private func statusLabel(for status: PrebufferDownloadStatus) -> String {
        if status.isPaused {
            if let progressPercent = status.progressPercent {
                return "Paused \(progressPercent)%"
            }
            return "Paused"
        }
        return status.progressPercent.map { "\($0)%" } ?? "Starting"
    }

    @ViewBuilder
    private func availableSection(title: String, songs: [Song]) -> some View {
        if !songs.isEmpty {
            WRhythmCard {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    HStack {
                        WRhythmSectionHeader(title: title)
                        Spacer()
                        Button {
                            player.keepAllAvailableTracks()
                        } label: {
                            if player.isKeepingAvailableTracks {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Keeping")
                                }
                                .font(WRhythmTypography.metadata.weight(.semibold))
                            } else {
                                Label("Keep All", systemImage: "tray.and.arrow.down.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(WRhythmTypography.metadata.weight(.semibold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(WRhythmTheme.accent)
                        .disabled(player.isKeepingAvailableTracks)
                    }

                    SlidingRenderWindowForEach(
                        songs,
                        estimatedRowHeight: 58,
                        resetToken: SongRenderWindowPolicy.availableTracksResetToken(songIds: songs.map(\.id))
                    ) { index, song in
                        HStack(spacing: WRhythmSpacing.xs) {
                            Button {
                                player.playAvailableTracksQueue(readySongs, startingAt: availableIndex(for: song, fallback: index))
                            } label: {
                                WRhythmMediaRow(
                                    title: song.title,
                                    subtitle: song.artist,
                                    detail: song.album,
                                    coverArtId: song.coverArt,
                                    artworkSize: 42
                                ) {
                                    if let qualityLabel = qualityLabels[song.id] {
                                        AvailableTrackQualityBadge(label: qualityLabel)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    await player.keepAvailableTrack(song)
                                }
                            } label: {
                                VStack(alignment: .trailing, spacing: 6) {
                                    Image(systemName: downloadManager.isDownloaded(song.id) ? "checkmark.circle.fill" : "tray.and.arrow.down")
                                        .font(WRhythmTypography.metadata.weight(.semibold))
                                        .foregroundStyle(WRhythmTheme.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(downloadManager.isDownloaded(song.id))
                            .accessibilityLabel(downloadManager.isDownloaded(song.id) ? "Kept \(song.title)" : "Keep \(song.title)")
                        }

                        if song.id != songs.last?.id {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    private func availableIndex(for song: Song, fallback: Int) -> Int {
        readySongs.firstIndex(where: { $0.id == song.id }) ?? fallback
    }
}

private struct AvailableTrackQualityBadge: View {
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .imageScale(.small)
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .font(WRhythmTypography.metadata.weight(.semibold))
        .foregroundStyle(WRhythmTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(WRhythmTheme.accent.opacity(0.14))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(WRhythmTheme.accent.opacity(0.34), lineWidth: 1)
                }
        }
        .accessibilityLabel("Cached quality \(label)")
    }
}
