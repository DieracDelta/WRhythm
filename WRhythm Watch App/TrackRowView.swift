//
//  TrackRowView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/25/25.
//

import SwiftUI

struct TrackRowView: View {
    let song: Song
    let isDownloaded: Bool
    let isStarred: Bool
    let isCurrentAndPlaying: Bool
    let offlineMode: Bool
    let onTap: () -> Void
    var onDownload: () -> Void
    var onDelete: () -> Void
    var onToggleFavorite: () -> Void

    init(
        song: Song,
        isDownloaded: Bool,
        isStarred: Bool,
        isCurrentAndPlaying: Bool,
        offlineMode: Bool,
        onTap: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.song = song
        self.isDownloaded = isDownloaded
        self.isStarred = isStarred
        self.isCurrentAndPlaying = isCurrentAndPlaying
        self.offlineMode = offlineMode
        self.onTap = onTap
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onToggleFavorite = onToggleFavorite
    }

    var body: some View {
        Button(action: onTap) {
            WRhythmMediaRow(
                title: song.title,
                subtitle: song.artist,
                detail: song.album,
                coverArtId: song.coverArt,
                artworkSize: 44,
                isCurrent: isCurrentAndPlaying,
                isPlaying: isCurrentAndPlaying
            ) {
                HStack(spacing: WRhythmSpacing.xs) {
                    if isDownloaded {
                        if !offlineMode {
                            WRhythmRowIconButton(
                                systemImage: "arrow.down.circle.fill",
                                tint: WRhythmTheme.success,
                                accessibilityLabel: "Delete download",
                                action: onDelete
                            )
                        } else {
                            // Offline mode: just an indicator
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(WRhythmTheme.success)
                        }
                    } else if !offlineMode {
                        WRhythmRowIconButton(
                            systemImage: "arrow.down.circle",
                            tint: WRhythmTheme.secondaryAccent,
                            accessibilityLabel: "Download song",
                            action: onDownload
                        )
                    }

                    if !offlineMode {
                        WRhythmRowIconButton(
                            systemImage: isStarred ? "heart.fill" : "heart",
                            tint: isStarred ? WRhythmTheme.favorite : .secondary,
                            accessibilityLabel: isStarred ? "Unfavorite song" : "Favorite song",
                            action: onToggleFavorite
                        )
                    }

                    if !offlineMode {
                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "music.note.list")
                                .font(.caption2)
                                .foregroundColor(WRhythmTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .wrhythmTrackActions(song: song)
    }
}

extension TrackRowView {
    init(
        song: Song,
        player: AudioPlayer,
        downloadManager: DownloadManager,
        offlineMode: Bool,
        onTap: @escaping () -> Void
    ) {
        self.init(
            song: song,
            isDownloaded: downloadManager.isDownloaded(song.id),
            isStarred: downloadManager.starredSongIds.contains(song.id),
            isCurrentAndPlaying: player.currentSong?.id == song.id && player.isPlaying,
            offlineMode: offlineMode,
            onTap: onTap,
            onDownload: { downloadManager.downloadSong(song) },
            onDelete: { downloadManager.deleteSong(song.id) },
            onToggleFavorite: { TrackActions.toggleFavorite(song) }
        )
    }
}
