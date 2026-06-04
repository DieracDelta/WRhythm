//
//  PhoneQueueView.swift
//  WRhythm
//

import SwiftUI

#if os(iOS)
struct PhoneQueueView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        WRhythmScreen {
            queueHeader

            queueSection(
                title: localQueueSectionTitle,
                songs: displayedQueue,
                currentIndex: displayedCurrentIndex,
                isPlaying: displayedQueueIsPlaying,
                emptyText: "No queued songs",
                play: playDisplayedQueueItem,
                canRemove: canRemoveDisplayedQueueItem,
                remove: removeDisplayedQueueItem,
                clear: clearDisplayedQueue
            )

            if deviceSyncManager.syncModeEnabled,
               let remote = activeRemotePlayback,
               !remoteQueueMatchesDisplayed {
                queueSection(
                    title: "\(remote.deviceName) Queue",
                    songs: remoteQueue,
                    currentIndex: remote.currentIndex,
                    isPlaying: remote.isPlaying,
                    emptyText: "No queued songs",
                    play: { index in
                        deviceSyncManager.playRemoteQueueItem(remote, at: index)
                    },
                    canRemove: { _ in false },
                    remove: { _ in },
                    clear: {}
                )
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var queueHeader: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            Text("Queue")
                .font(WRhythmTypography.appTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(queueSummary)
                .font(WRhythmTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func queueSection(
        title: String,
        songs: [Song],
        currentIndex: Int,
        isPlaying: Bool,
        emptyText: String,
        play: @escaping (Int) -> Void,
        canRemove: @escaping (Int) -> Bool,
        remove: @escaping (Int) -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            WRhythmSectionHeader(title: title) {
                if !songs.isEmpty {
                    WRhythmStatusPill(
                        text: "\(songs.count) \(songs.count == 1 ? "track" : "tracks")",
                        systemImage: "music.note.list",
                        tint: WRhythmTheme.accent
                    )
                }
            }

            WRhythmCard {
                if songs.isEmpty {
                    Text(emptyText)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, WRhythmSpacing.xs)
                } else {
                    SlidingRenderWindowForEach(
                        queueItems(songs),
                        estimatedRowHeight: 62,
                        spacing: WRhythmSpacing.xs,
                        resetToken: SongRenderWindowPolicy.sidebarQueueResetToken(
                            songIds: songs.map(\.id),
                            currentIndex: currentIndex
                        ),
                        anchorIndexHint: currentIndex
                    ) { _, item in
                        Button(action: {
                            play(item.index)
                        }) {
                            PhoneQueueRow(
                                song: item.song,
                                index: item.index,
                                isCurrent: currentIndex == item.index,
                                isPlaying: isPlaying
                            )
                        }
                        .buttonStyle(.plain)
                        .wrhythmQueueTrackActions(
                            song: item.song,
                            canRemoveFromQueue: canRemove(item.index),
                            removeFromQueue: {
                                remove(item.index)
                            },
                            clearQueue: clear
                        )
                    }
                }
            }
        }
    }

    private var activeRemotePlayback: PlaybackSnapshot? {
        deviceSyncManager.activeSharedPlayback
    }

    private var displayedQueue: [Song] {
        if let sharedSession = deviceSyncManager.sharedSession {
            return sharedSession.queue
        }
        return player.queue
    }

    private var displayedCurrentIndex: Int {
        if deviceSyncManager.isLocalPlaybackOutput,
           displayedQueue.map(\.id) == player.queue.map(\.id),
           let currentSong = player.currentSong,
           let index = displayedQueue.firstIndex(where: { $0.id == currentSong.id }) {
            return index
        }

        if deviceSyncManager.sharedSession != nil {
            return deviceSyncManager.sharedQueueCurrentIndex
        }

        if let currentSong = player.currentSong,
           let index = displayedQueue.firstIndex(where: { $0.id == currentSong.id }) {
            return index
        }

        return min(max(player.currentIndex, 0), max(displayedQueue.count - 1, 0))
    }

    private var displayedQueueIsPlaying: Bool {
        if deviceSyncManager.isLocalPlaybackOutput {
            return deviceSyncManager.localPlaybackIsPlayingForDisplay
        }
        if let sharedPlayback = deviceSyncManager.activeSharedPlayback {
            return sharedPlayback.isPlaying
        }
        if let sharedSession = deviceSyncManager.sharedSession {
            return sharedSession.isPlaying
        }
        return player.isPlaying
    }

    private var remoteQueue: [Song] {
        guard let remote = activeRemotePlayback else { return [] }
        return remote.queue.isEmpty ? remote.song.map { [$0] } ?? [] : remote.queue
    }

    private var remoteQueueMatchesLocal: Bool {
        guard !player.queue.isEmpty, !remoteQueue.isEmpty else { return false }
        return player.queue.map(\.id) == remoteQueue.map(\.id)
    }

    private var remoteQueueMatchesDisplayed: Bool {
        guard !displayedQueue.isEmpty, !remoteQueue.isEmpty else { return false }
        return displayedQueue.map(\.id) == remoteQueue.map(\.id)
    }

    private var localQueueSectionTitle: String {
        QueuePresentationPolicy.sectionTitle(
            hasSharedSession: deviceSyncManager.sharedSession != nil,
            remoteQueueMatchesLocal: remoteQueueMatchesLocal,
            localTitle: "This Device Queue"
        )
    }

    private var queueSummary: String {
        QueuePresentationPolicy.summary(queueCount: displayedQueue.count, currentIndex: displayedCurrentIndex)
    }

    private func queueItems(_ songs: [Song]) -> [PhoneQueueDisplayItem] {
        songs.enumerated().map { index, song in
            PhoneQueueDisplayItem(index: index, song: song)
        }
    }

    private func playDisplayedQueueItem(at index: Int) {
        if deviceSyncManager.sharedSession != nil {
            deviceSyncManager.playSharedQueueItem(at: index)
        } else {
            player.playQueue(player.queue, startingAt: index)
        }
    }

    private func canRemoveDisplayedQueueItem(at index: Int) -> Bool {
        QueuePresentationPolicy.canRemove(
            index: index,
            currentIndex: displayedCurrentIndex,
            queueCount: displayedQueue.count
        )
    }

    private func removeDisplayedQueueItem(at index: Int) {
        if QueuePresentationPolicy.mutationTarget(hasSharedSession: deviceSyncManager.sharedSession != nil) == .shared {
            deviceSyncManager.removeSharedQueueItem(at: index)
        } else {
            player.removeQueueItem(at: index)
        }
    }

    private func clearDisplayedQueue() {
        if QueuePresentationPolicy.mutationTarget(hasSharedSession: deviceSyncManager.sharedSession != nil) == .shared {
            deviceSyncManager.clearSharedQueue()
        } else {
            player.clearQueue()
        }
    }
}

private struct PhoneQueueDisplayItem: Identifiable {
    let index: Int
    let song: Song

    var id: String {
        "\(song.id)-\(index)"
    }
}

private struct PhoneQueueRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            WRhythmArtworkThumbnail(coverArtId: song.coverArt, size: 52)

            VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                HStack(spacing: WRhythmSpacing.xs) {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker")
                            .font(WRhythmTypography.controlLabelEmphasis)
                            .foregroundStyle(WRhythmTheme.accent)
                    }

                    Text(song.title)
                        .font(WRhythmTypography.queueTitle(isCurrent: isCurrent))
                        .lineLimit(1)
                }

                Text([song.artist, song.album].compactMap { $0 }.joined(separator: " • "))
                    .font(WRhythmTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: WRhythmSpacing.xs)

            Text("\(index + 1)")
                .font(WRhythmTypography.controlLabelEmphasis)
                .foregroundStyle(isCurrent ? WRhythmTheme.accent : .secondary)
                .frame(minWidth: 24)
        }
        .padding(WRhythmSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                    .fill(WRhythmTheme.accent.opacity(0.18))
            }
        }
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                    .stroke(WRhythmTheme.accent.opacity(0.55), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}
#endif
