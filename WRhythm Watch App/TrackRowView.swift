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
    let downloadStatus: DownloadRowStatus
    let isStarred: Bool
    let isCurrentAndPlaying: Bool
    let offlineMode: Bool
    let selectionScopeSongs: [Song]
    let onTap: () -> Void
    var onDownload: () -> Void
    var onDelete: () -> Void
    var onToggleFavorite: () async -> Void

    init(
        song: Song,
        isDownloaded: Bool,
        downloadStatus: DownloadRowStatus = .none,
        isStarred: Bool,
        isCurrentAndPlaying: Bool,
        offlineMode: Bool,
        selectionScopeSongs: [Song] = [],
        onTap: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onToggleFavorite: @escaping () async -> Void
    ) {
        self.song = song
        self.isDownloaded = isDownloaded
        self.downloadStatus = downloadStatus
        self.isStarred = isStarred
        self.isCurrentAndPlaying = isCurrentAndPlaying
        self.offlineMode = offlineMode
        self.selectionScopeSongs = selectionScopeSongs
        self.onTap = onTap
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onToggleFavorite = onToggleFavorite
    }

    var body: some View {
        Button(action: handleTap) {
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
                    switch downloadStatus {
                    case .downloading(let progress):
                        DownloadStatusPill(
                            systemImage: nil,
                            text: "\(Int(progress * 100))%",
                            tint: WRhythmTheme.downloads
                        )
                    case .queued:
                        DownloadStatusPill(
                            systemImage: "clock",
                            text: "Queued",
                            tint: WRhythmTheme.warning
                        )
                    case .downloaded:
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
                                .font(WRhythmTypography.metadata)
                                .foregroundColor(WRhythmTheme.success)
                        }
                    case .none:
                        if !offlineMode {
                            WRhythmRowIconButton(
                                systemImage: "arrow.down.circle",
                                tint: WRhythmTheme.secondaryAccent,
                                accessibilityLabel: "Download song",
                                action: onDownload
                            )
                        }
                    }

                    if !offlineMode {
                        WRhythmFavoriteButton(
                            isFavorite: isStarred,
                            size: .row,
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
                                .font(WRhythmTypography.metadata)
                                .foregroundColor(WRhythmTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .wrhythmSelectableTrack(song: song, selectionScopeSongs: selectionScopeSongs)
        .wrhythmTrackActions(song: song)
    }

    private func handleTap() {
#if os(macOS)
        let modifiers = TrackSelectionModifiers.currentEventModifiers
        if modifiers.shouldSelectInsteadOfActivate {
            TrackSelectionManager.shared.handleClick(
                song: song,
                scopeSongs: selectionScopeSongs,
                modifiers: modifiers
            )
            return
        }
        if TrackSelectionManager.shared.selectedCount > 0 {
            TrackSelectionManager.shared.clear()
        }
#endif
        onTap()
    }
}

extension TrackRowView {
    init(
        song: Song,
        player: AudioPlayer,
        downloadManager: DownloadManager,
        offlineMode: Bool,
        selectionScopeSongs: [Song] = [],
        onTap: @escaping () -> Void
    ) {
        self.init(
            song: song,
            isDownloaded: downloadManager.isDownloaded(song.id),
            downloadStatus: downloadManager.downloadStatus(for: song.id),
            isStarred: downloadManager.starredSongIds.contains(song.id),
            isCurrentAndPlaying: player.currentSong?.id == song.id && player.isPlaying,
            offlineMode: offlineMode,
            selectionScopeSongs: selectionScopeSongs,
            onTap: onTap,
            onDownload: { downloadManager.downloadSong(song) },
            onDelete: { downloadManager.deleteSong(song.id) },
            onToggleFavorite: { await TrackActions.toggleFavoriteAsync(song) }
        )
    }
}

private struct DownloadStatusPill: View {
    let systemImage: String?
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.62)
            }

            Text(text)
                .font(WRhythmTypography.metadata)
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule(style: .continuous))
        .accessibilityLabel(text)
    }
}
