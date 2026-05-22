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
                HStack(spacing: 6) {
                    if isDownloaded {
                        if !offlineMode {
                            Button(action: onDelete) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(WRhythmTheme.success)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Offline mode: just an indicator
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(WRhythmTheme.success)
                        }
                    } else if !offlineMode {
                        Button(action: onDownload) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption2)
                                .foregroundColor(WRhythmTheme.secondaryAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    if !offlineMode {
                        Button(action: onToggleFavorite) {
                            Image(systemName: isStarred ? "heart.fill" : "heart")
                                .font(.caption2)
                                .foregroundColor(isStarred ? WRhythmTheme.favorite : .gray)
                        }
                        .buttonStyle(.plain)
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
