//
//  AvailableTracksView.swift
//  WRhythm Watch App
//
//  Created by Codex on 5/24/26.
//

import SwiftUI

struct AvailableTracksPresentationPolicy: Sendable {
    static func summary(previousReadyCount: Int, nextReadyCount: Int, downloadingCount: Int) -> String {
        var parts: [String] = []
        if previousReadyCount > 0 || nextReadyCount > 0 {
            parts.append("\(previousReadyCount) prev avail")
            parts.append("\(nextReadyCount) next avail")
        }
        if downloadingCount > 0 {
            parts.append("\(downloadingCount) downloading")
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
            downloadStatuses: player.prebufferDownloadStatuses
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
    @Environment(\.dismiss) private var dismiss

    init(
        availableSongs: [Song] = [],
        previousSongs: [Song] = [],
        nextSongs: [Song] = [],
        downloadStatuses: [PrebufferDownloadStatus] = []
    ) {
        self.availableSongs = availableSongs
        self.previousSongs = previousSongs
        self.nextSongs = nextSongs
        self.downloadStatuses = downloadStatuses
    }

    init(songs: [Song], downloadStatuses: [PrebufferDownloadStatus] = []) {
        self.previousSongs = []
        self.nextSongs = songs
        self.downloadStatuses = downloadStatuses
    }

    var body: some View {
        NavigationStack {
            BufferedTracksListContent(
                availableSongs: availableSongs,
                previousSongs: previousSongs,
                nextSongs: nextSongs,
                downloadStatuses: downloadStatuses
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
    let availableSongs: [Song]
    let previousSongs: [Song]
    let nextSongs: [Song]
    var downloadStatuses: [PrebufferDownloadStatus]

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
                    ForEach(downloadStatuses) { status in
                        WRhythmMediaRow(
                            title: status.song.title,
                            subtitle: status.song.artist,
                            detail: status.song.album,
                            coverArtId: status.song.coverArt,
                            artworkSize: 42
                        ) {
                            Text(status.progressPercent.map { "\($0)%" } ?? "Starting")
                                .font(WRhythmTypography.metadata.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(WRhythmTheme.warning)
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

    @ViewBuilder
    private func availableSection(title: String, songs: [Song]) -> some View {
        if !songs.isEmpty {
            WRhythmCard {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    WRhythmSectionHeader(title: title)
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
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
                                Image(systemName: "play.fill")
                                    .font(WRhythmTypography.metadata.weight(.semibold))
                                    .foregroundStyle(WRhythmTheme.accent)
                            }
                        }
                        .buttonStyle(.plain)

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
