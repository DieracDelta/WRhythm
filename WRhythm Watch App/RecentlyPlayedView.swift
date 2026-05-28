//
//  RecentlyPlayedView.swift
//  WRhythm Watch App
//

import SwiftUI

struct RecentlyPlayedView: View {
    @ObservedObject private var store = RecentlyPlayedStore.shared
    @ObservedObject private var player = AudioPlayer.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var songs: [Song] {
        store.items.map(\.song)
    }

    var body: some View {
        WRhythmScreen(coverArtId: store.items.first?.song.coverArt, contentMaxWidth: 920) {
            if store.items.isEmpty {
                WRhythmEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "No Recently Played",
                    message: "Tracks appear here after they count as played."
                )
            } else {
                VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                    header

                    WRhythmCard {
                        VStack(spacing: 0) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                                recentlyPlayedRow(item: item, index: index)

                                if item.id != store.items.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recently Played")
        .platformNavigationBarTitleDisplayModeInline()
        .toolbar {
            if !store.items.isEmpty {
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Clear Recently Played", systemImage: "trash")
                }
            }
        }
    }

    private var header: some View {
        WRhythmFeatureHeader(
            title: "Recently Played",
            subtitle: "\(store.items.count) tracks",
            systemImage: "clock.arrow.circlepath",
            tint: WRhythmTheme.accent
        )
    }

    private func recentlyPlayedRow(item: RecentlyPlayedItem, index: Int) -> some View {
        Button {
            player.playQueue(songs, startingAt: index)
        } label: {
            WRhythmMediaRow(
                title: item.song.title,
                subtitle: item.song.artist,
                detail: item.song.album,
                coverArtId: item.song.coverArt,
                fallbackTint: WRhythmTheme.accent,
                artworkSize: 44,
                isCurrent: player.currentSong?.id == item.song.id,
                isPlaying: player.currentSong?.id == item.song.id && player.isPlaying
            ) {
                VStack(alignment: .trailing, spacing: WRhythmSpacing.xxs) {
                    Text(item.playedAt.formatted(.relative(presentation: .numeric)))
                        .font(WRhythmTypography.metadata.weight(.semibold))
                        .foregroundStyle(WRhythmTheme.accent)

#if !os(watchOS)
                    HStack(spacing: WRhythmSpacing.xs) {
                        if !offlineMode {
                            WRhythmFavoriteButton(
                                isFavorite: downloadManager.starredSongIds.contains(item.song.id),
                                size: .row,
                                action: { TrackActions.toggleFavorite(item.song) }
                            )
                        }

                        if downloadManager.isDownloaded(item.song.id) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(WRhythmTypography.metadata)
                                .foregroundStyle(WRhythmTheme.success)
                        }
                    }
#endif
                }
            }
        }
        .buttonStyle(.plain)
        .wrhythmTrackActions(song: item.song)
    }
}

#Preview {
    RecentlyPlayedView()
}
