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
            HStack(spacing: 10) {
                WRhythmArtworkThumbnail(coverArtId: song.coverArt, size: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let artist = song.artist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    // Download/Delete button
                    if isDownloaded {
                        if !offlineMode {
                            // Online mode: tappable to delete
                            Button(action: onDelete) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Offline mode: just an indicator
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    } else if !offlineMode {
                        Button(action: onDownload) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    // Heart/favorite button (online mode only)
                    if !offlineMode {
                        Button(action: onToggleFavorite) {
                            Image(systemName: isStarred ? "heart.fill" : "heart")
                                .font(.caption2)
                                .foregroundColor(isStarred ? .red : .gray)
                        }
                        .buttonStyle(.plain)
                    }

                    // Radio button (online mode only) - navigate to radio options
                    if !offlineMode {
                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "music.note.list")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    // Now playing indicator
                    if isCurrentAndPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            TrackContextMenuItems(song: song)
        }
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
