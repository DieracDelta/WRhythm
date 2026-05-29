//
//  ActiveDownloadsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ActiveDownloadsPresentationPolicy: Sendable {
    static let queuedPreviewLimit = 20

    static func showsEmptyState(activeCount: Int, queuedCount: Int, failedCount: Int = 0) -> Bool {
        activeCount == 0 && queuedCount == 0 && failedCount == 0
    }

    static func headerTitle(activeCount: Int, queuedCount: Int, failedCount: Int = 0) -> String {
        if activeCount > 0 {
            return "\(activeCount) downloading"
        }
        if queuedCount > 0 {
            return "\(queuedCount) queued"
        }
        return "\(failedCount) failed"
    }

    static func headerSubtitle(activeCount: Int, queuedCount: Int, failedCount: Int = 0) -> String? {
        guard activeCount > 0 else {
            return nil
        }
        if activeCount > 0, queuedCount > 0, failedCount > 0 {
            return "\(queuedCount) queued, \(failedCount) failed"
        }
        if activeCount > 0, queuedCount > 0 {
            return "\(queuedCount) queued"
        }
        if activeCount > 0, failedCount > 0 {
            return "\(failedCount) failed"
        }
        return nil
    }
}

struct ActiveDownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: WRhythmVisual.sectionSpacing) {
                if ActiveDownloadsPresentationPolicy.showsEmptyState(
                    activeCount: downloadManager.activeDownloads.count,
                    queuedCount: downloadManager.downloadQueue.count,
                    failedCount: downloadManager.failedDownloads.count
                ) {
                    WRhythmEmptyState(
                        systemImage: "arrow.down.circle",
                        title: "No Active Downloads",
                        message: "Downloads will appear here while in progress"
                    )
                } else {
                    WRhythmFeatureHeader(
                        title: ActiveDownloadsPresentationPolicy.headerTitle(
                            activeCount: downloadManager.activeDownloads.count,
                            queuedCount: downloadManager.downloadQueue.count,
                            failedCount: downloadManager.failedDownloads.count
                        ),
                        subtitle: ActiveDownloadsPresentationPolicy.headerSubtitle(
                            activeCount: downloadManager.activeDownloads.count,
                            queuedCount: downloadManager.downloadQueue.count,
                            failedCount: downloadManager.failedDownloads.count
                        ),
                        systemImage: "arrow.down.circle.fill",
                        tint: WRhythmTheme.downloads
                    )

                    if !downloadManager.activeDownloads.isEmpty {
                        WRhythmSectionHeader(title: "Active", subtitle: "Current transfers")

                        VStack(spacing: WRhythmSpacing.xs) {
                            ForEach(Array(downloadManager.activeDownloads.keys), id: \.self) { songId in
                                ActiveDownloadRow(songId: songId, song: findSongInfo(songId))
                            }
                        }
                    }

                    if !downloadManager.downloadQueue.isEmpty {
                        WRhythmSectionHeader(title: "Queued", subtitle: "\(downloadManager.downloadQueue.count) waiting")

                        VStack(spacing: WRhythmSpacing.xs) {
                            ForEach(Array(downloadManager.downloadQueue.prefix(ActiveDownloadsPresentationPolicy.queuedPreviewLimit)), id: \.id) { song in
                                QueuedDownloadRow(song: song)
                            }

                            if downloadManager.downloadQueue.count > ActiveDownloadsPresentationPolicy.queuedPreviewLimit {
                                Text("+ \(downloadManager.downloadQueue.count - ActiveDownloadsPresentationPolicy.queuedPreviewLimit) more")
                                    .font(WRhythmTypography.rowSubtitle)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if !downloadManager.failedDownloads.isEmpty {
                        WRhythmSectionHeader(title: "Failed", subtitle: "\(downloadManager.failedDownloads.count) needs attention")

                        VStack(spacing: WRhythmSpacing.xs) {
                            ForEach(Array(downloadManager.failedDownloads.values.sorted(by: { $0.failedAt > $1.failedAt }))) { failed in
                                FailedDownloadRow(failedDownload: failed)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Active Downloads")
        .wrhythmPageBackground()
    }

    private func findSongInfo(_ songId: String) -> Song? {
        // Get song metadata for active downloads
        return downloadManager.songMetadata[songId]
    }
}

private struct FailedDownloadRow: View {
    let failedDownload: FailedDownload
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        WRhythmCard(padding: 10) {
            WRhythmMediaRow(
                title: failedDownload.title,
                subtitle: failedDownload.artist,
                detail: failedDownload.errorDescription,
                coverArtId: failedDownload.coverArt,
                fallbackSystemImage: "exclamationmark.triangle",
                artworkSize: 42
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(WRhythmTypography.metadata)
                        .foregroundColor(WRhythmTheme.danger)

                    Button(action: {
                        downloadManager.retryDownload(failedDownload.songId)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(WRhythmTypography.metadata)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry download")

                    Button(action: {
                        downloadManager.cancelDownload(failedDownload.songId)
                    }) {
                        Image(systemName: "xmark")
                            .font(WRhythmTypography.metadata)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(WRhythmTheme.danger)
                    .accessibilityLabel("Dismiss failed download")
                }
            }
        }
    }
}

private struct ActiveDownloadRow: View {
    let songId: String
    let song: Song?
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        let progress = downloadManager.downloadProgress(songId)

        WRhythmCard(padding: 10) {
            VStack(spacing: 8) {
                WRhythmMediaRow(
                    title: song?.title ?? "Downloading",
                    subtitle: song?.artist,
                    detail: "Active download",
                    coverArtId: song?.coverArt,
                    fallbackSystemImage: "arrow.down.circle",
                    artworkSize: 42
                ) {
                    HStack(spacing: 8) {
                        Text("\(Int(progress * 100))%")
                            .font(WRhythmTypography.controlLabelEmphasis)
                            .foregroundColor(.secondary)
                            .monospacedDigit()

                        Button(action: {
                            downloadManager.retryDownload(songId)
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(WRhythmTypography.metadata)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retry download")

                        Button(action: {
                            downloadManager.cancelDownload(songId)
                        }) {
                            Image(systemName: "xmark")
                                .font(WRhythmTypography.metadata)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(WRhythmTheme.danger)
                        .accessibilityLabel("Cancel download")
                    }
                }

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(WRhythmTheme.secondaryAccent)
            }
        }
    }
}

private struct QueuedDownloadRow: View {
    let song: Song
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        WRhythmCard(padding: 10) {
            WRhythmMediaRow(
                title: song.title,
                subtitle: song.artist,
                detail: "Queued",
                coverArtId: song.coverArt,
                fallbackSystemImage: "clock",
                artworkSize: 42
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(WRhythmTypography.metadata)
                        .foregroundColor(.secondary)

                    Button(action: {
                        downloadManager.cancelDownload(song.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(WRhythmTypography.metadata)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(WRhythmTheme.danger)
                    .accessibilityLabel("Cancel queued download")
                }
            }
        }
        .opacity(0.72)
    }
}
