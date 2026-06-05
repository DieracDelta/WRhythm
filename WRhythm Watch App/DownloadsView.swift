//
//  DownloadsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct DownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var presentedSheet: DownloadsSheet?
    @State private var deleteConfirmationText = ""
    @State private var isSearchVisible = false
    @State private var searchText = ""

    private var player: AudioPlayer { AudioPlayer.shared }

    private var visibleDownloads: [DownloadedSong] {
        DownloadsPresentationPolicy.sortedVisibleDownloads(
            Array(downloadManager.downloadedSongs.values),
            fileExists: downloadManager.hasDownloadedFile
        )
    }

    private var albumSections: [DownloadedAlbumSection] {
        DownloadsPresentationPolicy.albumSections(for: visibleDownloads, searchText: searchText)
    }

    var body: some View {
        WRhythmScreen {
            if downloadManager.getTotalPendingDownloads() > 0 || !downloadManager.failedDownloads.isEmpty || downloadManager.isPaused {
                downloadStatusCard
            }

            if DownloadsPresentationPolicy.showsEmptyState(visibleDownloadCount: visibleDownloads.count) {
#if os(iOS)
                PhoneDownloadsEmptyView(message: emptyDownloadsMessage)
#else
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No Downloads",
                    message: emptyDownloadsMessage
                )
#endif
            } else {
                downloadedSummaryCard

                if isSearchVisible {
                    TextField("Search downloads", text: $searchText)
                        .platformSearchTextFieldStyle()
                        .wrhythmDismissFocusOnEscape()
                }

                if albumSections.isEmpty {
                    WRhythmEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No Matches",
                        message: nil
                    )
                } else {
                    SlidingRenderWindowForEach(
                        albumSections,
                        estimatedRowHeight: 82,
                        spacing: WRhythmSpacing.xs,
                        resetToken: SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
                            albumSectionIds: albumSections.map(\.id),
                            query: searchText
                        )
                    ) { _, section in
                        downloadedAlbumRow(section)
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .deleteAll:
                deleteAllSheet
            case .albumQuality(let albumID):
                if let section = albumSections.first(where: { $0.id == albumID }) {
                    DownloadQualityPickerSheet(
                        title: section.title,
                        currentQualityLabel: section.qualitySummary
                    ) { quality in
                        downloadManager.changeQuality(for: section.songs, to: quality)
                        presentedSheet = nil
                    }
                }
            case .trackQuality(let songID):
                if let downloadedSong = visibleDownloads.first(where: { $0.songId == songID }) {
                    DownloadQualityPickerSheet(
                        title: downloadedSong.title,
                        currentQualityLabel: DownloadsPresentationPolicy.qualityLabel(for: downloadedSong)
                    ) { quality in
                        downloadManager.changeQuality(for: downloadedSong, to: quality)
                        presentedSheet = nil
                    }
                }
            }
        }
    }

    private var downloadStatusCard: some View {
        WRhythmCard {
            VStack(spacing: WRhythmSpacing.sm) {
                WRhythmSectionHeader(title: "Download Status") {
                    WRhythmIconBadge(systemImage: "arrow.down.circle.fill", tint: WRhythmTheme.downloads, size: 30)
                }

                VStack(spacing: WRhythmSpacing.xxs) {
                    WRhythmMetricRow(title: "Completed", value: "\(downloadManager.sessionCompletedCount)", valueColor: WRhythmTheme.success)
                    WRhythmMetricRow(title: "Active", value: "\(downloadManager.getActiveDownloadCount())", valueColor: WRhythmTheme.secondaryAccent)
                    WRhythmMetricRow(title: "Queued", value: "\(downloadManager.getQueuedDownloadCount())", valueColor: WRhythmTheme.warning)
                    if !downloadManager.failedDownloads.isEmpty {
                        WRhythmMetricRow(title: "Failed", value: "\(downloadManager.failedDownloads.count)", valueColor: WRhythmTheme.danger)
                    }
                    WRhythmMetricRow(title: "Total", value: "\(downloadManager.sessionTotalCount)")
                }

                if downloadManager.getActiveDownloadCount() > 0 {
                    activeProgressSection
                }

                WRhythmActionStrip {
                    Button(action: {
                        if downloadManager.isPaused {
                            downloadManager.resumeDownloads()
                        } else {
                            downloadManager.pauseDownloads()
                        }
                    }) {
                        Image(systemName: downloadManager.isPaused ? "play.fill" : "pause.fill")
                    }
                    .tint(downloadManager.isPaused ? WRhythmTheme.success : WRhythmTheme.accent)

                    Button(action: downloadManager.restartDownloads) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(WRhythmTheme.secondaryAccent)

                    Button(action: downloadManager.cancelAllDownloads) {
                        Image(systemName: "xmark")
                    }
                    .tint(WRhythmTheme.danger)
                }

                NavigationLink(destination: ActiveDownloadsView()) {
                    Label("View Details", systemImage: "chevron.right")
                        .font(WRhythmTypography.controlLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundColor(WRhythmTheme.secondaryAccent)
            }
        }
    }

    private var activeProgressSection: some View {
        VStack(spacing: WRhythmSpacing.xs) {
            let avgProgress = downloadManager.getAverageDownloadProgress()
            WRhythmMetricRow(title: "Avg Progress", value: "\(Int(avgProgress * 100))%")
            ProgressView(value: avgProgress)
                .progressViewStyle(.linear)
                .tint(WRhythmTheme.secondaryAccent)

            Divider()

            let totalBytes = downloadManager.getTotalBytesToDownload()
            let downloadedBytes = downloadManager.getTotalBytesDownloaded()
            let remainingBytes = downloadManager.getBytesRemaining()
            WRhythmMetricRow(title: "Downloaded", value: formatBytes(downloadedBytes), valueColor: WRhythmTheme.success)
            WRhythmMetricRow(title: "Total Size", value: formatBytes(totalBytes))
            WRhythmMetricRow(title: "Remaining", value: formatBytes(remainingBytes), valueColor: WRhythmTheme.warning)

            if totalBytes > 0 {
                ProgressView(value: Double(downloadedBytes) / Double(totalBytes))
                    .progressViewStyle(.linear)
                    .tint(WRhythmTheme.success)
            }
        }
    }

    private var downloadedSummaryCard: some View {
        WRhythmCard {
            HStack(spacing: WRhythmSpacing.sm) {
                WRhythmIconBadge(systemImage: "internaldrive", tint: WRhythmTheme.downloads)

                VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                    Text("\(albumSections.count) albums")
                        .font(WRhythmTypography.featureTitle)
                    Text("\(downloadManager.getTotalDownloaded()) songs • \(formatBytes(downloadManager.getTotalSize()))")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isSearchVisible.toggle()
                        if !isSearchVisible {
                            searchText = ""
                        }
                    }
                } label: {
                    Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .tint(WRhythmTheme.accent)

                Button(action: {
                    presentedSheet = .deleteAll
                    deleteConfirmationText = ""
                }) {
                    Label("Delete All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(WRhythmTheme.danger)
            }
        }
    }

    private func downloadedAlbumRow(_ section: DownloadedAlbumSection) -> some View {
        HStack(spacing: WRhythmSpacing.xs) {
            NavigationLink {
                DownloadedAlbumTracksView(section: section)
            } label: {
                WRhythmMediaRow(
                    title: section.title,
                    subtitle: section.artist,
                    detail: "\(section.songs.count) songs • \(formatBytes(section.totalSize))",
                    coverArtId: section.coverArt,
                    artworkSize: 48
                ) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: WRhythmSpacing.xs)

            Button {
                presentedSheet = .albumQuality(albumID: section.id)
            } label: {
                DownloadQualityBadge(label: section.qualitySummary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change quality for \(section.title)")
        }
        .padding(WRhythmSpacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
    }

    private var deleteAllSheet: some View {
        NavigationStack {
            WRhythmScreen {
                WRhythmCard {
                    VStack(spacing: WRhythmSpacing.md) {
                        Text("Delete All Downloads?")
                            .font(WRhythmTypography.featureTitle)

                        Text("This will delete \(downloadManager.getTotalDownloaded()) songs (\(formatBytes(downloadManager.getTotalSize())))")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Type DELETE to confirm")
                            .font(WRhythmTypography.controlLabel)
                            .foregroundColor(WRhythmTheme.danger)

                        TextField("Type DELETE", text: $deleteConfirmationText)
                            .platformAutocapitalizationCharacters()
                            .platformSearchTextFieldStyle()

                        Button(action: {
                            downloadManager.deleteAll()
                            presentedSheet = nil
                            deleteConfirmationText = ""
                        }) {
                            Text("Delete All")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WRhythmTheme.danger)
                        .disabled(deleteConfirmationText != "DELETE")
                    }
                }
            }
            .navigationTitle("Confirm Delete")
            .platformNavigationBarTitleDisplayModeInline()
            .platformModalCloseToolbar {
                presentedSheet = nil
                deleteConfirmationText = ""
            }
        }
        .platformExplicitCloseModal()
    }

    private var emptyDownloadsMessage: String? {
#if os(iOS) || os(watchOS)
        nil
#else
        "Download songs, albums, or playlists for offline playback"
#endif
    }

    private var navigationTitleText: String {
#if os(iOS)
        let visibleCount = DownloadsPresentationPolicy.sortedVisibleDownloads(
            Array(downloadManager.downloadedSongs.values),
            fileExists: downloadManager.hasDownloadedFile
        ).count
        return DownloadsPresentationPolicy.showsEmptyState(visibleDownloadCount: visibleCount) ? "" : "Downloads"
#else
        "Downloads"
#endif
    }

    private func song(from downloadedSong: DownloadedSong) -> Song {
        Song(
            id: downloadedSong.songId,
            title: downloadedSong.title,
            album: downloadedSong.album,
            albumId: nil,
            artist: downloadedSong.artist,
            artistId: nil,
            track: nil,
            year: nil,
            genre: nil,
            coverArt: downloadedSong.coverArt,
            size: Int(downloadedSong.fileSize),
            contentType: nil,
            suffix: nil,
            duration: nil,
            bitRate: nil,
            path: downloadedSong.filePath
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

private enum DownloadsSheet: Identifiable {
    case deleteAll
    case albumQuality(albumID: String)
    case trackQuality(songID: String)

    var id: String {
        switch self {
        case .deleteAll:
            return "deleteAll"
        case .albumQuality(let albumID):
            return "albumQuality:\(albumID)"
        case .trackQuality(let songID):
            return "trackQuality:\(songID)"
        }
    }
}

private struct DownloadedAlbumTracksView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var player = AudioPlayer.shared
    @State private var presentedSheet: DownloadsSheet?

    let section: DownloadedAlbumSection

    private var displayedSection: DownloadedAlbumSection {
        let visibleDownloads = DownloadsPresentationPolicy.sortedVisibleDownloads(
            Array(downloadManager.downloadedSongs.values),
            fileExists: downloadManager.hasDownloadedFile
        )
        return DownloadsPresentationPolicy.albumSections(for: visibleDownloads, searchText: "")
            .first(where: { $0.id == section.id }) ?? section
    }

    var body: some View {
        let section = displayedSection
        WRhythmScreen {
            WRhythmCard {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    WRhythmMediaRow(
                        title: section.title,
                        subtitle: section.artist,
                        detail: "\(section.songs.count) songs • \(section.qualitySummary)",
                        coverArtId: section.coverArt,
                        artworkSize: 52
                    ) {
                        Button {
                            presentedSheet = .albumQuality(albumID: section.id)
                        } label: {
                            DownloadQualityBadge(label: section.qualitySummary)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    SlidingRenderWindowForEach(
                        section.songs,
                        estimatedRowHeight: 64,
                        resetToken: SongRenderWindowPolicy.downloadedAlbumSongsResetToken(
                            albumSectionId: section.id,
                            songIds: section.songs.map(\.songId)
                        )
                    ) { _, downloadedSong in
                        HStack(spacing: WRhythmSpacing.xs) {
                            Button {
                                player.playSong(song(from: downloadedSong))
                            } label: {
                                WRhythmMediaRow(
                                    title: downloadedSong.title,
                                    subtitle: downloadedSong.artist,
                                    detail: formatBytes(downloadedSong.fileSize),
                                    coverArtId: downloadedSong.coverArt,
                                    artworkSize: 42
                                ) {
                                    if player.currentSong?.id == downloadedSong.songId && player.isPlaying {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(WRhythmTypography.metadata)
                                            .foregroundStyle(WRhythmTheme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                presentedSheet = .trackQuality(songID: downloadedSong.songId)
                            } label: {
                                DownloadQualityBadge(label: DownloadsPresentationPolicy.qualityLabel(for: downloadedSong))
                            }
                            .buttonStyle(.plain)

                            WRhythmRowIconButton(
                                systemImage: "trash",
                                tint: WRhythmTheme.danger,
                                accessibilityLabel: "Delete download"
                            ) {
                                downloadManager.deleteSong(downloadedSong.songId)
                            }
                        }

                        if downloadedSong.songId != section.songs.last?.songId {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
            }
        }
        .navigationTitle(section.title)
        .platformNavigationBarTitleDisplayModeInline()
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .deleteAll:
                EmptyView()
            case .albumQuality:
                DownloadQualityPickerSheet(
                    title: section.title,
                    currentQualityLabel: section.qualitySummary
                ) { quality in
                    downloadManager.changeQuality(for: section.songs, to: quality)
                    presentedSheet = nil
                }
            case .trackQuality(let songID):
                if let downloadedSong = section.songs.first(where: { $0.songId == songID }) {
                    DownloadQualityPickerSheet(
                        title: downloadedSong.title,
                        currentQualityLabel: DownloadsPresentationPolicy.qualityLabel(for: downloadedSong)
                    ) { quality in
                        downloadManager.changeQuality(for: downloadedSong, to: quality)
                        presentedSheet = nil
                    }
                }
            }
        }
    }

    private func song(from downloadedSong: DownloadedSong) -> Song {
        Song(
            id: downloadedSong.songId,
            title: downloadedSong.title,
            album: downloadedSong.album,
            albumId: nil,
            artist: downloadedSong.artist,
            artistId: nil,
            track: nil,
            year: nil,
            genre: nil,
            coverArt: downloadedSong.coverArt,
            size: Int(downloadedSong.fileSize),
            contentType: nil,
            suffix: nil,
            duration: nil,
            bitRate: downloadedSong.downloadedBitRate,
            path: downloadedSong.filePath
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

private struct DownloadQualityBadge: View {
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
    }
}

private struct DownloadQualityPickerSheet: View {
    let title: String
    let currentQualityLabel: String
    let onSelect: (AudioQuality) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WRhythmScreen {
                WRhythmCard {
                    VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                        Text(title)
                            .font(WRhythmTypography.featureTitle)
                            .lineLimit(2)

                        Text("Current: \(currentQualityLabel)")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundStyle(.secondary)

                        ForEach(AudioQuality.allCases, id: \.rawValue) { quality in
                            Button {
                                onSelect(quality)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                                        Text(quality.shortDescription)
                                            .font(WRhythmTypography.rowTitle)
                                        Text(quality.description)
                                            .font(WRhythmTypography.metadata)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if quality.shortDescription == currentQualityLabel || quality.label == currentQualityLabel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(WRhythmTheme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, WRhythmSpacing.xs)

                            if quality != AudioQuality.allCases.last {
                                Divider()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Download Quality")
            .platformNavigationBarTitleDisplayModeInline()
            .platformModalCloseToolbar {
                dismiss()
            }
        }
        .platformExplicitCloseModal()
    }
}
