//
//  ContentView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

extension Notification.Name {
    static let wrhythmShowPlaylistGen = Notification.Name("wrhythmShowPlaylistGen")
}

struct ContentView: View {
    @ObservedObject var api = NavidromeAPI.shared
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var hasPresentedInitialLoading = false
#if os(macOS)
    @State private var selectedMacDestination: MacDestination? = .nowPlaying
#else
    @State private var selectedTab = 0
#endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasPresentedInitialLoading {
                appContent
            } else {
                WRhythmAppLoadingView()
            }
        }
        .wrhythmPageBackground()
        .task {
            guard !hasPresentedInitialLoading else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            hasPresentedInitialLoading = true
        }
#if os(macOS)
        .macSpacebarPlaybackShortcut()
#endif
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                DeviceSyncManager.shared.requestPlaybackSyncRefresh()
#if !os(macOS)
                // When app becomes active, go to Now Playing if music is playing
                if AudioPlayer.shared.isPlaying {
#if os(watchOS)
                    selectedTab = 0
#else
                    selectedTab = 2
#endif
                }
#endif
            case .inactive, .background:
                AudioPlayer.shared.persistPlaybackStateNow()
            @unknown default:
                AudioPlayer.shared.persistPlaybackStateNow()
            }
        }
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .wrhythmShowPlaylistGen)) { _ in
            selectedMacDestination = .playlistGen
        }
#endif
#if os(iOS)
        .safeAreaInset(edge: .top) {
            if let notice = downloadManager.downloadNotice {
                DownloadNoticeBanner(message: notice.message) {
                    selectedTab = 4
                    downloadManager.clearDownloadNotice(notice.id)
                }
                .padding(.horizontal, WRhythmSpacing.md)
                .padding(.top, WRhythmSpacing.xs)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if player.playlistGenIsGenerating {
                PlaylistGenerationStatusBanner()
                    .padding(.horizontal, WRhythmSpacing.md)
                    .padding(.bottom, WRhythmSpacing.sm)
            }
        }
        .onChange(of: downloadManager.downloadNotice?.id) { _, noticeID in
            guard let noticeID else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                downloadManager.clearDownloadNotice(noticeID)
            }
        }
#endif
    }

    @ViewBuilder
    private var appContent: some View {
        if api.isAuthenticated {
#if os(macOS)
            MacContentLayout(selection: $selectedMacDestination)
#elseif os(watchOS)
            TabView(selection: $selectedTab) {
                NavigationStack {
                    NowPlayingView()
                }
                .tag(0)

                NavigationStack {
                    MenuView()
                }
                .tag(1)
            }
#else
            TabView(selection: $selectedTab) {
                NavigationStack {
                    MenuView()
                }
#if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarHidden(true)
#endif
                .tabItem {
                    Label("Library", systemImage: "square.grid.2x2")
                }
                .tag(0)

                NavigationStack {
                    TracksView()
                }
#if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarHidden(true)
#endif
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(1)

                NavigationStack {
                    NowPlayingView()
                }
#if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarHidden(true)
#endif
                .tabItem {
                    Label("Playing", systemImage: "play.circle.fill")
                }
                .tag(2)

#if os(iOS)
                NavigationStack {
                    PhoneQueueView()
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarHidden(true)
                .tabItem {
                    Label("Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .tag(3)
#endif

                NavigationStack {
                    DownloadsView()
                }
#if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarHidden(true)
#endif
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .tag(4)
            }
#if os(iOS)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
#endif
#endif
        } else {
            LoginView()
        }
    }
}

#Preview {
    ContentView()
}

#if os(iOS)
private struct DownloadNoticeBanner: View {
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WRhythmSpacing.sm) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(WRhythmTheme.downloads)

                Text(message)
                    .font(WRhythmTypography.metadataEmphasis)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: WRhythmSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(WRhythmTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, WRhythmSpacing.md)
            .padding(.vertical, WRhythmSpacing.sm)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(WRhythmTheme.downloads.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message)
    }
}
#endif

private struct PlaylistGenerationStatusBanner: View {
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(WRhythmTheme.playlistGen)

            VStack(alignment: .leading, spacing: 2) {
                Text("Generating Playlist")
                    .font(WRhythmTypography.metadataEmphasis)
                if let title = player.playlistGenGeneratingTitle {
                    Text(title)
                        .font(WRhythmTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WRhythmSpacing.sm)

            Button("Cancel", role: .cancel) {
                player.cancelPlaylistGeneration()
            }
            .font(WRhythmTypography.metadataEmphasis)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, WRhythmSpacing.md)
        .padding(.vertical, WRhythmSpacing.sm)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(WRhythmTheme.playlistGen.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#if os(macOS)
enum MacDestination: String, Hashable, CaseIterable {
    case nowPlaying
    case artists
    case playlists
    case favorites
    case recentlyPlayed
    case playlistGen
    case tracks
    case spontaneous
    case albums
    case availableTracks
    case downloads
    case settings

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .artists: return "Artists"
        case .playlists: return "Playlists"
        case .favorites: return "Favorites"
        case .recentlyPlayed: return "Recently Played"
        case .playlistGen: return "Playlist Gen"
        case .tracks: return "Search"
        case .spontaneous: return "Spontaneous"
        case .albums: return "Albums"
        case .availableTracks: return "Available Tracks"
        case .downloads: return "Downloads"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .nowPlaying: return "play.circle.fill"
        case .artists: return "person.2"
        case .playlists: return "music.note.list"
        case .favorites: return "star.fill"
        case .recentlyPlayed: return "clock.arrow.circlepath"
        case .playlistGen: return "music.note.list"
        case .tracks: return "magnifyingglass"
        case .spontaneous: return "shuffle"
        case .albums: return "square.stack"
        case .availableTracks: return "externaldrive.fill"
        case .downloads: return "arrow.down.circle"
        case .settings: return "gear"
        }
    }
}

struct MacContentLayout: View {
    @Binding var selection: MacDestination?

    var body: some View {
        NavigationSplitView {
            MacSidebar(selection: $selection)
        } detail: {
            MacDetailContent(selection: $selection)
        }
    }
}

struct MacSidebar: View {
    @Binding var selection: MacDestination?
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(MacDestination.allCases, id: \.self) { destination in
                    NavigationLink(value: destination) {
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                }
            }
            .listRowBackground(Color.clear)

            Section(localQueueSectionTitle) {
                if displayedQueue.isEmpty {
                    Text("No queued songs")
                        .foregroundColor(.secondary)
                } else {
                    SlidingRenderWindowForEach(
                        queueItems(displayedQueue),
                        estimatedRowHeight: 50,
                        resetToken: SongRenderWindowPolicy.sidebarQueueResetToken(
                            songIds: displayedQueue.map(\.id),
                            currentIndex: displayedCurrentIndex
                        ),
                        anchorIndexHint: displayedCurrentIndex,
                        renderMode: .fullRangeLoaded
                    ) { _, item in
                        Button(action: {
                            selection = .nowPlaying
                            if deviceSyncManager.sharedSession != nil {
                                deviceSyncManager.playSharedQueueItem(at: item.index)
                            } else {
                                player.playQueue(player.queue, startingAt: item.index)
                            }
                        }) {
                            MacQueueRow(
                                song: item.song,
                                isCurrent: displayedCurrentIndex == item.index,
                                isPlaying: displayedQueueIsPlaying
                            )
                        }
                        .buttonStyle(.plain)
                        .wrhythmQueueTrackActions(
                            song: item.song,
                            canRemoveFromQueue: canRemoveDisplayedQueueItem(at: item.index),
                            removeFromQueue: {
                                removeDisplayedQueueItem(at: item.index)
                            },
                            clearQueue: {
                                clearDisplayedQueue()
                            }
                        )
                    }
                }
            }
            .listRowBackground(Color.clear)

            if deviceSyncManager.syncModeEnabled,
               let remote = activeRemotePlayback,
               !remoteQueueMatchesDisplayed {
                Section("\(remote.deviceName) Queue") {
                    if remoteQueue.isEmpty {
                        Text("No queued songs")
                            .foregroundColor(.secondary)
                    } else {
                        SlidingRenderWindowForEach(
                            queueItems(remoteQueue),
                            estimatedRowHeight: 50,
                            resetToken: SongRenderWindowPolicy.sidebarQueueResetToken(
                                songIds: remoteQueue.map(\.id),
                                currentIndex: remote.currentIndex
                            ),
                            anchorIndexHint: remote.currentIndex,
                            renderMode: .fullRangeLoaded
                        ) { _, item in
                            Button(action: {
                                selection = .nowPlaying
                                deviceSyncManager.playRemoteQueueItem(remote, at: item.index)
                            }) {
                                MacQueueRow(
                                    song: item.song,
                                    isCurrent: remote.currentIndex == item.index,
                                    isPlaying: remote.isPlaying
                                )
                            }
                            .buttonStyle(.plain)
                            .wrhythmTrackActions(song: item.song)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("WRhythm")
        .macTransparentSidebarSurface()
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
            localTitle: "Mac Queue"
        )
    }

    private func queueItems(_ songs: [Song]) -> [QueueDisplayItem] {
        songs.enumerated().map { index, song in
            QueueDisplayItem(index: index, song: song)
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

private extension View {
    func macTransparentSidebarSurface() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}

private struct QueueDisplayItem: Identifiable {
    let index: Int
    let song: Song

    var id: String {
        "\(song.id)-\(index)"
    }
}

private struct MacQueueRow: View {
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: WRhythmSpacing.xs) {
            WRhythmArtworkThumbnail(coverArtId: song.coverArt, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WRhythmSpacing.xs) {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(WRhythmTheme.accent)
                    }

                    Text(song.title)
                        .font(WRhythmTypography.queueCompactTitle(isCurrent: isCurrent))
                        .lineLimit(1)
                }

                if let artist = song.artist {
                    Text(artist)
                        .font(WRhythmTypography.metadata)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WRhythmTheme.accent.opacity(0.18))
            }
        }
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WRhythmTheme.accent.opacity(0.55), lineWidth: 1)
            }
        }
    }
}

struct MacDetailContent: View {
    @Binding var selection: MacDestination?
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                destinationView(for: selection ?? .nowPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                MacMiniPlayerAttachment(selection: $selection)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = player.playbackError {
                MacPlaybackErrorBanner(error: error) {
                    player.dismissPlaybackError()
                }
                .padding(.horizontal, WRhythmSpacing.md)
                .padding(.bottom, WRhythmSpacing.sm)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: MacDestination) -> some View {
        switch destination {
        case .nowPlaying:
            NowPlayingView()
        case .artists:
            ArtistsView()
        case .playlists:
            PlaylistsView()
        case .favorites:
            FavouritesView()
        case .recentlyPlayed:
            RecentlyPlayedView()
        case .playlistGen:
            RadioPlaylistsView()
        case .tracks:
            TracksView()
        case .spontaneous:
            SpontaneousMusicView()
        case .albums:
            AlbumsView()
        case .availableTracks:
            AvailableTracksView()
        case .downloads:
            DownloadsView()
        case .settings:
            SettingsView()
        }
    }
}

private struct MacPlaybackErrorBanner: View {
    let error: PlaybackErrorInfo
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: WRhythmSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(WRhythmTheme.danger)
                Text(error.title)
                    .font(WRhythmTypography.controlLabelEmphasis)
                Spacer()
#if os(macOS) || os(iOS)
                Button("Copy Error", action: copyError)
                    .buttonStyle(.borderless)
                    .foregroundStyle(WRhythmTheme.accent)
                    .accessibilityLabel("Copy playback error")
#endif
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss playback error")
            }

            Text(error.message)
                .font(WRhythmTypography.metadata)
                .foregroundStyle(.secondary)

            Text(error.technicalDetails)
                .font(WRhythmTypography.timer)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Text(error.recoverySuggestion)
                .font(WRhythmTypography.metadata)
                .foregroundStyle(WRhythmTheme.accent)
        }
        .padding(WRhythmSpacing.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                .stroke(WRhythmTheme.danger.opacity(0.35), lineWidth: 1)
        }
    }

#if os(macOS) || os(iOS)
    private func copyError() {
        WRhythmClipboard.copy(
            WRhythmErrorCopyPolicy.copyText(
                title: error.title,
                message: error.message,
                technicalDetails: error.technicalDetails,
                recoverySuggestion: error.recoverySuggestion
            )
        )
    }
#endif
}

struct MacMiniPlayerAttachment: View {
    @Binding var selection: MacDestination?
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        if selection != .nowPlaying,
           player.currentSong != nil || deviceSyncManager.activeSharedPlayback?.song != nil {
            Divider()
            MacMiniPlayerBar(selection: $selection)
        }
    }
}

struct MacMiniPlayerBar: View {
    @Binding var selection: MacDestination?
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @State private var bufferedTracksSheet: BufferedTracksSheetPayload?

    var body: some View {
        VStack(spacing: 0) {
            if let song = player.currentSong, displayVisibility.showsLocal {
                let isPlaying = deviceSyncManager.localPlaybackIsPlayingForDisplay
                miniRow(
                    coverArtId: song.coverArt,
                    title: song.title,
                    subtitle: [song.artist, song.album].compactMap { $0 }.joined(separator: " • "),
                    isPlaying: isPlaying,
                    isBuffering: player.isBuffering,
                    bufferStatusText: player.queueBufferStatusSummary,
                    availableBufferedSongs: player.availablePrebufferedSongs,
                    availableQualityLabels: player.availablePrebufferedTrackQualityLabels,
                    previousBufferedSongs: player.retainedPrebufferedSongs,
                    nextBufferedSongs: player.prebufferedSongs,
                    downloadStatuses: player.prebufferDownloadStatuses,
                    queuePosition: player.queue.count > 1 ? "\(localLabel): \(player.currentIndex + 1) of \(player.queue.count)" : localLabel,
                    previous: player.previous,
                    toggle: { deviceSyncManager.setPlaying(!isPlaying, targetDeviceID: deviceSyncManager.localPlaybackTargetID) },
                    next: player.next,
                    currentTime: { player.currentTime },
                    duration: player.duration,
                    seek: { player.seek(to: $0) },
                    progressIsLive: isPlaying,
                    previousDisabled: player.currentIndex == 0 && player.currentTime < 3,
                    nextDisabled: player.currentIndex >= player.queue.count - 1
                )
            }

            if deviceSyncManager.syncModeEnabled,
               let remote = deviceSyncManager.activeSharedPlayback,
               let song = remote.song,
               displayVisibility.showsRemote {
                if player.currentSong != nil, displayVisibility.showsLocal {
                    Divider()
                }
                miniRow(
                    coverArtId: song.coverArt,
                    title: song.title,
                    subtitle: [song.artist, song.album].compactMap { $0 }.joined(separator: " • "),
                    isPlaying: remote.isPlaying,
                    isBuffering: remote.isBuffering == true,
                    bufferStatusText: nil,
                    availableBufferedSongs: bufferedSongs(for: remote),
                    availableQualityLabels: [:],
                    previousBufferedSongs: [],
                    nextBufferedSongs: bufferedSongs(for: remote),
                    downloadStatuses: [],
                    queuePosition: remote.queue.count > 1 ? "\(remote.deviceName): \(remote.currentIndex + 1) of \(remote.queue.count)" : remote.deviceName,
                    previous: { deviceSyncManager.sendPrevious(targetDeviceID: remote.id) },
                    toggle: { deviceSyncManager.setPlaying(!remote.isPlaying, targetDeviceID: remote.id) },
                    next: { deviceSyncManager.sendNext(targetDeviceID: remote.id) },
                    currentTime: { remote.estimatedCurrentTime },
                    duration: remote.duration,
                    seek: { deviceSyncManager.sendSeek(to: $0, targetDeviceID: remote.id) },
                    progressIsLive: remote.isPlaying,
                    previousDisabled: remote.currentIndex == 0 && remote.currentTime < 3,
                    nextDisabled: remote.currentIndex >= remote.queue.count - 1
                )
            }

            if player.currentSong != nil || deviceSyncManager.activeSharedPlayback?.song != nil {
                Divider()
                Slider(value: $player.volume, in: 0...1)
                    .tint(WRhythmTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(.bar)
        .sheet(item: $bufferedTracksSheet) { sheet in
            BufferedTracksListView(
                availableSongs: sheet.availableSongs,
                previousSongs: sheet.previousSongs,
                nextSongs: sheet.nextSongs,
                downloadStatuses: sheet.downloadStatuses,
                qualityLabels: sheet.qualityLabels
            )
        }
    }

    private var remoteQueue: [Song] {
        guard let remote = deviceSyncManager.activeSharedPlayback else { return [] }
        return remote.queue.isEmpty ? remote.song.map { [$0] } ?? [] : remote.queue
    }

    private var remoteQueueMatchesLocal: Bool {
        guard !player.queue.isEmpty, !remoteQueue.isEmpty else { return false }
        return player.queue.map(\.id) == remoteQueue.map(\.id)
    }

    private var displayVisibility: PlaybackDisplayVisibility {
        let sharedPlayback = deviceSyncManager.activeSharedPlayback
        return PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: player.currentSong != nil,
            localIsPlaying: deviceSyncManager.localPlaybackIsPlayingForDisplay,
            hasRemotePlayback: sharedPlayback?.song != nil,
            hasActiveSharedPlayback: deviceSyncManager.activeSharedPlayback != nil,
            remoteQueueMatchesLocal: remoteQueueMatchesLocal,
            localIsPlaybackOutput: deviceSyncManager.isLocalPlaybackOutput
        )
    }

    private var localLabel: String {
        remoteQueueMatchesLocal ? "Shared Queue" : "Mac"
    }

    private func bufferedSongs(for remote: PlaybackSnapshot) -> [Song] {
        guard let count = remote.prebufferedTrackCount, count > 0 else { return [] }
        let queue = remote.queue.isEmpty ? remote.song.map { [$0] } ?? [] : remote.queue
        let start = remote.currentIndex + 1
        guard start < queue.count else { return [] }
        return Array(queue[start..<min(queue.count, start + count)])
    }

    private func miniRow(
        coverArtId: String?,
        title: String,
        subtitle: String,
        isPlaying: Bool,
        isBuffering: Bool,
        bufferStatusText: String?,
        availableBufferedSongs: [Song],
        availableQualityLabels: [String: String],
        previousBufferedSongs: [Song],
        nextBufferedSongs: [Song],
        downloadStatuses: [PrebufferDownloadStatus],
        queuePosition: String,
        previous: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        currentTime: @escaping () -> TimeInterval,
        duration: TimeInterval,
        seek: @escaping (TimeInterval) -> Void,
        progressIsLive: Bool,
        previousDisabled: Bool,
        nextDisabled: Bool
    ) -> some View {
        let availableSongs = availableBufferedSongs.isEmpty ? previousBufferedSongs + nextBufferedSongs : availableBufferedSongs

        return VStack(spacing: WRhythmSpacing.xs) {
            HStack(spacing: WRhythmSpacing.sm) {
                MiniPlayerArtwork(coverArtId: coverArtId)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: WRhythmSpacing.xs) {
                        Text(title)
                            .font(WRhythmTypography.featureTitle)
                            .lineLimit(1)
                        Text(miniStatusText(
                            queuePosition: queuePosition,
                            isBuffering: isBuffering,
                            bufferStatusText: bufferStatusText
                        ))
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if !availableSongs.isEmpty || !downloadStatuses.isEmpty {
                        Button(action: {
                            bufferedTracksSheet = BufferedTracksSheetPayload(
                                availableSongs: availableSongs,
                                previousSongs: previousBufferedSongs,
                                nextSongs: nextBufferedSongs,
                                downloadStatuses: downloadStatuses,
                                qualityLabels: availableQualityLabels
                            )
                        }) {
                            Label(
                                availableTracksSummary(
                                    previous: previousBufferedSongs.count,
                                    next: nextBufferedSongs.count,
                                    downloading: downloadStatuses.count
                                ),
                                systemImage: "arrow.down.circle"
                            )
                                .font(WRhythmTypography.metadata)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = .nowPlaying
                }

                Spacer()

                WRhythmTransportButton(systemImage: "backward.end.fill", size: .caption, diameter: 32, action: previous)
                .disabled(previousDisabled)

                WRhythmTransportButton(
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                    size: .headline,
                    prominent: true,
                    diameter: 40,
                    action: toggle
                )

                WRhythmTransportButton(systemImage: "forward.end.fill", size: .caption, diameter: 32, action: next)
                .disabled(nextDisabled)
            }

            MiniPlayerProgressControl(
                currentTime: currentTime,
                duration: duration,
                seek: seek,
                isLive: progressIsLive
            )
        }
        .padding(.horizontal, WRhythmSpacing.md)
        .padding(.vertical, WRhythmSpacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        .padding(.horizontal, WRhythmSpacing.sm)
        .padding(.vertical, WRhythmSpacing.xs)
    }

    private func miniStatusText(queuePosition: String, isBuffering: Bool, bufferStatusText: String?) -> String {
        var parts = [queuePosition]
        if let bufferStatusText {
            parts.append(bufferStatusText)
        } else if isBuffering {
            parts.append("Buffering")
        }
        return parts.joined(separator: " • ")
    }

    private func availableTracksSummary(previous: Int, next: Int, downloading: Int) -> String {
        var parts: [String] = []
        if previous > 0 || next > 0 {
            parts.append("\(previous) prev avail")
            parts.append("\(next) next avail")
        }
        if downloading > 0 {
            parts.append("\(downloading) downloading")
        }
        return parts.isEmpty ? "No tracks ready" : parts.joined(separator: " | ")
    }
}

private struct BufferedTracksSheetPayload: Identifiable {
    let id = UUID()
    let availableSongs: [Song]
    let previousSongs: [Song]
    let nextSongs: [Song]
    var downloadStatuses: [PrebufferDownloadStatus] = []
    var qualityLabels: [String: String] = [:]
}

private struct MiniPlayerArtwork: View {
    @Environment(\.colorScheme) private var colorScheme
    let coverArtId: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)

            if let coverArtId,
               let coverURL = StoredAlbumArtworkCache.displayURL(for: coverArtId, size: 96) {
                CachedAsyncImage(url: coverURL, storedCoverArtId: coverArtId) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
    }
}

struct MiniPlayerProgressControl: View {
    let currentTime: () -> TimeInterval
    let duration: TimeInterval
    let seek: (TimeInterval) -> Void
    let isLive: Bool
    @State private var scrubTime: TimeInterval?

    var body: some View {
        PlaybackProgressTimeline(isLive: isLive) {
            let liveTime = sanitizedTime(currentTime())
            let displayedTime = min(max(scrubTime ?? liveTime, 0), safeDuration)

            VStack(spacing: WRhythmSpacing.xxs) {
                Slider(
                    value: Binding(
                        get: { displayedTime },
                        set: { scrubTime = min(max($0, 0), safeDuration) }
                    ),
                    in: 0...safeDuration,
                    onEditingChanged: { isEditing in
                        guard !isEditing, let scrubTime else { return }
                        seek(scrubTime)
                        self.scrubTime = nil
                    }
                )
                .tint(WRhythmTheme.accent)

                HStack {
                    Text(formatTime(displayedTime))
                        .font(WRhythmTypography.metadata)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("-" + formatTime(max(0, safeDuration - displayedTime)))
                        .font(WRhythmTypography.metadata)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var safeDuration: TimeInterval {
        let fallback: TimeInterval = 1
        guard duration.isFinite, duration > 0 else { return fallback }
        return duration
    }

    private func sanitizedTime(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? seconds : 0
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else {
            return "0:00"
        }
        return Duration.seconds(Int(max(0, seconds)))
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }

}
#endif
