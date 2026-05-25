//
//  AvailableTracksView.swift
//  WRhythm Watch App
//
//  Created by Codex on 5/24/26.
//

import SwiftUI

struct AvailableTracksPresentationPolicy: Sendable {
    static func summary(readyCount: Int, downloadingCount: Int) -> String {
        if readyCount > 0, downloadingCount > 0 {
            return "\(readyCount) ready, \(downloadingCount) downloading"
        }
        if readyCount > 0 {
            return "\(readyCount) ready"
        }
        if downloadingCount > 0 {
            return "\(downloadingCount) downloading"
        }
        return "No tracks ready"
    }
}

struct AvailableTracksView: View {
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        BufferedTracksListContent(
            songs: player.availablePrebufferedSongs,
            downloadStatuses: player.prebufferDownloadStatuses
        )
        .navigationTitle("Available Tracks")
        .platformNavigationBarTitleDisplayModeInline()
    }
}

struct BufferedTracksListView: View {
    let songs: [Song]
    var downloadStatuses: [PrebufferDownloadStatus] = []

    var body: some View {
        NavigationStack {
            BufferedTracksListContent(songs: songs, downloadStatuses: downloadStatuses)
                .navigationTitle("Available Tracks")
                .platformNavigationBarTitleDisplayModeInline()
        }
    }
}

private struct BufferedTracksListContent: View {
    let songs: [Song]
    var downloadStatuses: [PrebufferDownloadStatus]

    var body: some View {
        WRhythmScreen(contentMaxWidth: 920) {
            if songs.isEmpty && downloadStatuses.isEmpty {
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No Available Tracks",
                    message: "Queue tracks appear here while downloading and after they are ready to play."
                )
            } else {
                VStack(spacing: WRhythmSpacing.md) {
                    downloadingSection
                    availableSection
                }
            }
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
    private var availableSection: some View {
        if !songs.isEmpty {
            WRhythmCard {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    WRhythmSectionHeader(title: "Available")
                    ForEach(songs) { song in
                        WRhythmMediaRow(
                            title: song.title,
                            subtitle: song.artist,
                            detail: song.album,
                            coverArtId: song.coverArt,
                            artworkSize: 42
                        ) {
                            Text("Ready")
                                .font(WRhythmTypography.metadata.weight(.semibold))
                                .foregroundStyle(WRhythmTheme.success)
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
}
