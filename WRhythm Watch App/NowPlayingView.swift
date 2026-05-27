//
//  NowPlayingView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI
import AVFoundation

struct PlaybackProgressRefreshPolicy: Sendable {
    static func shouldUseLiveTimeline(isPlaying: Bool) -> Bool {
        isPlaying
    }
}

struct PlaybackProgressTimeline<Content: View>: View {
    let isLive: Bool
    let content: () -> Content

    init(isLive: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isLive = isLive
        self.content = content
    }

    var body: some View {
        if PlaybackProgressRefreshPolicy.shouldUseLiveTimeline(isPlaying: isLive) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                content()
            }
        } else {
            content()
        }
    }
}

struct NowPlayingView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @State private var isStarring = false
    @State private var hasLoadedStarredSongs = false
    @State private var presentedSheet: NowPlayingSheet?
    @State private var scrubTime: TimeInterval?
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
#if os(watchOS)
        WatchNowPlayingView()
#elseif os(iOS)
        PhoneNowPlayingView(
            isStarring: isStarring,
            presentedSheet: $presentedSheet,
            scrubTime: $scrubTime,
            seekLocal: { seekLocal(by: $0) },
            toggleFavorite: { toggleFavorite(song: $0) }
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .volume:
                VolumeControlView()
            case .audioRoute:
                AudioRouteView()
            case .bufferedTracks:
                BufferedTracksListView(
                    availableSongs: player.availablePrebufferedSongs,
                    previousSongs: player.retainedPrebufferedSongs,
                    nextSongs: player.prebufferedSongs,
                    downloadStatuses: player.prebufferDownloadStatuses,
                    qualityLabels: player.availablePrebufferedTrackQualityLabels
                )
            }
        }
        .onAppear {
            if !hasLoadedStarredSongs {
                loadStarredSongs()
            }
        }
#else
        WRhythmScreen(coverArtId: primaryArtworkCoverArtId, contentMaxWidth: 980) {
            if let remote = primaryRemotePlayback {
                VStack(spacing: WRhythmSpacing.sm) {
                    PlaybackTargetPicker()
                    RemotePlaybackControls(playback: remote, compact: false)
                }
            } else if let song = player.currentSong {
                let localIsPlaying = deviceSyncManager.localPlaybackIsPlayingForDisplay
                VStack(spacing: WRhythmSpacing.sm) {
                    NowPlayingArtwork(coverArtId: song.coverArt, maxSize: localArtworkMaxSize)
                        .equatable()

                    VStack(spacing: WRhythmSpacing.xs) {
                        Text(song.title)
                            .font(WRhythmTypography.heroTitle)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)

                        if let artist = song.artist {
                            Text(artist)
                                .font(WRhythmTypography.subhead)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let album = song.album {
                            Text(album)
                                .font(WRhythmTypography.metadata)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            if player.isBuffering {
                                WRhythmStatusPill(
                                    text: player.currentBufferPercent.map { "Buffering \($0)%" } ?? "Buffering",
                                    systemImage: "hourglass",
                                    tint: WRhythmTheme.warning
                                )
                            }
                            if !player.availablePrebufferedSongs.isEmpty || !player.prebufferDownloadStatuses.isEmpty {
                                BufferedTracksButton(
                                    previousCount: player.retainedPrebufferedSongs.count,
                                    nextCount: player.prebufferedSongs.count,
                                    downloadingCount: player.prebufferDownloadStatuses.count
                                ) {
                                    presentedSheet = .bufferedTracks
                                }
                            }
                        }
                    }

                    WRhythmCard(padding: WRhythmSpacing.sm, style: .glass) {
                        VStack(spacing: WRhythmSpacing.xs) {
                            let safeDuration = max(1, player.duration.isFinite ? player.duration : 1)
                            let liveTime = player.currentTime.isFinite ? player.currentTime : 0
                            let displayedTime = min(max(scrubTime ?? liveTime, 0), safeDuration)

                            Slider(
                                value: Binding(
                                    get: { displayedTime },
                                    set: { scrubTime = min(max($0, 0), safeDuration) }
                                ),
                                in: 0...safeDuration,
                                onEditingChanged: { isEditing in
                                    guard !isEditing, let scrubTime else { return }
                                    player.seek(to: scrubTime)
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

                    HStack(spacing: WRhythmSpacing.sm) {
                        WRhythmTransportButton(systemImage: "backward.end.fill", size: .body, diameter: 38, action: player.previous)
                        .disabled(player.currentIndex == 0 && player.currentTime < 3)

                        WRhythmTransportButton(systemImage: "gobackward.15", size: .body, diameter: 38) {
                            seekLocal(by: -15)
                        }

                        WRhythmTransportButton(
                            systemImage: localIsPlaying ? "pause.fill" : "play.fill",
                            size: .title2,
                            prominent: true,
                            diameter: 56,
                            action: {
                                deviceSyncManager.setPlaying(
                                    !localIsPlaying,
                                    targetDeviceID: deviceSyncManager.localPlaybackTargetID
                                )
                            }
                        )

                        WRhythmTransportButton(systemImage: "goforward.15", size: .body, diameter: 38) {
                            seekLocal(by: 15)
                        }

                        WRhythmTransportButton(systemImage: "forward.end.fill", size: .body, diameter: 38, action: player.next)
                        .disabled(player.currentIndex >= player.queue.count - 1)

                        NowPlayingResyncButton(diameter: 38)
                    }

                    PlaybackTargetPicker()

                    InlineVolumeSlider(volume: Binding(
                        get: { player.volume },
                        set: { player.volume = $0 }
                    ))

                    WRhythmActionStrip {
                        Button(action: {
                            presentedSheet = .volume
                        }) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.title3)
                                .symbolVariant(.fill)
                                .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                        }
                        .accessibilityLabel("Volume")

                        Button(action: {
                            presentedSheet = .audioRoute
                        }) {
                            Image(systemName: "airpodsmax")
                                .font(.title3)
                                .symbolVariant(.fill)
                                .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                        }
                        .accessibilityLabel("Audio output")

                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "music.note.list")
                                .font(.title3)
                                .symbolVariant(.fill)
                                .foregroundStyle(WRhythmTheme.accent.gradient)
                        }
                        .accessibilityLabel("Playlist Gen")

                        WRhythmFavoriteButton(
                            isFavorite: downloadManager.starredSongIds.contains(song.id),
                            size: .action,
                            isBusy: isStarring
                        ) {
                            toggleFavorite(song: song)
                        }
                    }

                    HStack(spacing: 8) {
                        if player.queue.count > 1 {
                            Text("Track \(player.currentIndex + 1) of \(player.queue.count)")
                                .font(WRhythmTypography.metadata)
                                .foregroundColor(.secondary)
                        }

                        Button(action: player.toggleShuffle) {
                            Image(systemName: player.isShuffled ? "shuffle.circle.fill" : "shuffle.circle")
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundColor(player.isShuffled ? WRhythmTheme.accent : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: player.toggleRepeat) {
                            Image(systemName: player.repeatMode == .off ? "repeat.circle" :
                                  player.repeatMode == .all ? "repeat.circle.fill" : "repeat.1.circle.fill")
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundColor(player.repeatMode == .off ? .secondary : WRhythmTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)

                    if primaryRemotePlayback == nil,
                       deviceSyncManager.syncModeEnabled,
                       let remote = deviceSyncManager.activeSharedPlayback,
                       remote.song != nil {
                        Divider()
                        RemotePlaybackControls(playback: remote, compact: true)
                    }
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .id(song.id)
            } else if deviceSyncManager.syncModeEnabled,
                      let remote = deviceSyncManager.activeSharedPlayback,
                      remote.song != nil {
                VStack(spacing: WRhythmSpacing.sm) {
                    PlaybackTargetPicker()
                    RemotePlaybackControls(playback: remote, compact: false)
                }
            } else {
                VStack(spacing: 8) {
                    PlaybackTargetPicker()
                    NowPlayingResyncButton(diameter: 38)

                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No song playing")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Now Playing")
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .volume:
                VolumeControlView()
            case .audioRoute:
                AudioRouteView()
            case .bufferedTracks:
                BufferedTracksListView(
                    availableSongs: player.availablePrebufferedSongs,
                    previousSongs: player.retainedPrebufferedSongs,
                    nextSongs: player.prebufferedSongs,
                    downloadStatuses: player.prebufferDownloadStatuses,
                    qualityLabels: player.availablePrebufferedTrackQualityLabels
                )
            }
        }
        .onAppear {
            if !hasLoadedStarredSongs {
                loadStarredSongs()
            }
        }
#endif
    }

    private var primaryArtworkCoverArtId: String? {
        if let remote = primaryRemotePlayback {
            return remote.song?.coverArt
        }
        return player.currentSong?.coverArt
    }

    private var primaryRemotePlayback: PlaybackSnapshot? {
        deviceSyncManager.activeSharedPlayback
    }

    private var localArtworkMaxSize: CGFloat {
#if os(iOS)
        220
#else
        340
#endif
    }

    private func seekLocal(by delta: TimeInterval) {
        let upperBound = player.duration > 0 && player.duration.isFinite ? player.duration : .greatestFiniteMagnitude
        let target = min(max(player.currentTime + delta, 0), upperBound)
        player.seek(to: target)
    }

    private func loadStarredSongs() {
        Task {
            do {
                let starred = try await NavidromeAPI.shared.getStarred()
                let songIds = Set(starred.song?.map { $0.id } ?? [])
                await MainActor.run {
                    downloadManager.cacheStarredSongs(songIds)
                    hasLoadedStarredSongs = true
                }
            } catch {
                print("❌ Failed to load starred songs: \(error)")
            }
        }
    }

    private func toggleFavorite(song: Song) {
        isStarring = true

        let isCurrentlyStarred = downloadManager.starredSongIds.contains(song.id)

        if offlineMode {
            // Offline mode: just update locally and queue for sync
            if isCurrentlyStarred {
                downloadManager.unstarSong(song.id, isOffline: true)
            } else {
                downloadManager.starSong(song.id, isOffline: true)
            }
            isStarring = false
        } else {
            // Online mode: update server and local cache
            Task {
                do {
                    if isCurrentlyStarred {
                        try await NavidromeAPI.shared.unstar(songId: song.id)
                        await MainActor.run {
                            downloadManager.unstarSong(song.id, isOffline: false)
                            isStarring = false
                        }
                    } else {
                        try await NavidromeAPI.shared.star(songId: song.id)
                        await MainActor.run {
                            downloadManager.starSong(song.id, isOffline: false)
                            isStarring = false
                        }
                    }
                } catch {
                    print("❌ Failed to toggle favorite: \(error)")
                    await MainActor.run {
                        isStarring = false
                    }
                }
            }
        }
    }

    private func startRadio(for song: Song) {
        player.startPlaylistGeneration(for: song, count: 100)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else {
            return "0:00"
        }
        return Duration.seconds(Int(max(0, seconds)))
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }
}

private func bufferedTrackLabel(
    previousCount: Int,
    nextCount: Int,
    downloadingCount: Int = 0
) -> String {
    var parts: [String] = []
    if previousCount > 0 || nextCount > 0 {
        parts.append("\(previousCount) prev avail")
        parts.append("\(nextCount) next avail")
    }
    if downloadingCount > 0 {
        parts.append("\(downloadingCount) downloading")
    }
    return parts.isEmpty ? "No tracks ready" : parts.joined(separator: " | ")
}

private enum NowPlayingSheet: String, Identifiable {
    case volume
    case audioRoute
    case bufferedTracks

    var id: String { rawValue }
}

private struct NowPlayingResyncButton: View {
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    var diameter: CGFloat = 38

    var body: some View {
        WRhythmTransportButton(
            systemImage: "arrow.clockwise",
            size: .body,
            diameter: diameter,
            action: deviceSyncManager.searchForNearbyDevices
        )
        .disabled(!deviceSyncManager.syncModeEnabled && !deviceSyncManager.credentialSyncEnabled)
        .accessibilityLabel("Reconnect and resync nearby devices")
        .help("Reconnect and resync nearby devices")
    }
}

#if os(iOS)
private struct PhoneNowPlayingView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    let isStarring: Bool
    @Binding var presentedSheet: NowPlayingSheet?
    @Binding var scrubTime: TimeInterval?
    let seekLocal: (TimeInterval) -> Void
    let toggleFavorite: (Song) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: WRhythmSpacing.sm) {
                    PhonePlaybackTargetPicker()

                    if let remote = deviceSyncManager.activeSharedPlayback {
                        PhoneRemoteNowPlayingContent(
                            playback: remote,
                            availableSize: proxy.size,
                            presentedSheet: $presentedSheet,
                            scrubTime: $scrubTime
                        )
                    } else if let song = player.currentSong {
                        PhoneLocalNowPlayingContent(
                            song: song,
                            availableSize: proxy.size,
                            isStarring: isStarring,
                            presentedSheet: $presentedSheet,
                            scrubTime: $scrubTime,
                            seekLocal: seekLocal,
                            toggleFavorite: toggleFavorite
                        )
                    } else {
                        PhoneNoSongContent()
                    }
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .padding(.horizontal, WRhythmSpacing.md)
                .padding(.top, WRhythmSpacing.md)
                .padding(.bottom, WRhythmVisual.bottomNavigationClearance)
            }
            .scrollIndicators(.hidden)
            .wrhythmPageBackground(coverArtId: primaryCoverArtId)
        }
    }

    private var primaryCoverArtId: String? {
        if let remote = deviceSyncManager.activeSharedPlayback {
            return remote.song?.coverArt
        }
        return player.currentSong?.coverArt
    }
}

private struct PhoneLocalNowPlayingContent: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    let song: Song
    let availableSize: CGSize
    let isStarring: Bool
    @Binding var presentedSheet: NowPlayingSheet?
    @Binding var scrubTime: TimeInterval?
    let seekLocal: (TimeInterval) -> Void
    let toggleFavorite: (Song) -> Void

    var body: some View {
        let localIsPlaying = deviceSyncManager.localPlaybackIsPlayingForDisplay

        VStack(spacing: WRhythmSpacing.sm) {
            NowPlayingArtwork(coverArtId: song.coverArt, maxSize: artworkSize)
                .equatable()

            PhoneTrackSummary(
                title: song.title,
                artist: song.artist,
                album: song.album,
                isBuffering: player.isBuffering,
                previousBufferedCount: player.retainedPrebufferedSongs.count,
                nextBufferedCount: player.prebufferedSongs.count,
                downloadingCount: player.prebufferDownloadStatuses.count,
                showBufferedTracks: { presentedSheet = .bufferedTracks }
            )

            PhoneProgressControl(
                duration: player.duration,
                currentTime: player.currentTime,
                scrubTime: $scrubTime,
                seek: player.seek
            )

            HStack(spacing: WRhythmSpacing.xs) {
                WRhythmTransportButton(systemImage: "backward.end.fill", size: .body, diameter: 44, action: player.previous)
                    .disabled(player.currentIndex == 0 && player.currentTime < 3)

                WRhythmTransportButton(systemImage: "gobackward.15", size: .body, diameter: 44) {
                    seekLocal(-15)
                }

                WRhythmTransportButton(
                    systemImage: localIsPlaying ? "pause.fill" : "play.fill",
                    size: .title2,
                    prominent: true,
                    diameter: 58,
                    action: {
                        deviceSyncManager.setPlaying(
                            !localIsPlaying,
                            targetDeviceID: deviceSyncManager.localPlaybackTargetID
                        )
                    }
                )

                WRhythmTransportButton(systemImage: "goforward.15", size: .body, diameter: 44) {
                    seekLocal(15)
                }

                WRhythmTransportButton(systemImage: "forward.end.fill", size: .body, diameter: 44, action: player.next)
                    .disabled(player.currentIndex >= player.queue.count - 1)

                NowPlayingResyncButton(diameter: 44)
            }

            InlineVolumeSlider(volume: Binding(
                get: { player.volume },
                set: { player.volume = $0 }
            ))

            WRhythmActionStrip {
                Button(action: { presentedSheet = .volume }) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.title3)
                        .symbolVariant(.fill)
                        .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                }
                .accessibilityLabel("Volume")

                Button(action: { presentedSheet = .audioRoute }) {
                    Image(systemName: "airpodsmax")
                        .font(.title3)
                        .symbolVariant(.fill)
                        .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                }
                .accessibilityLabel("Audio output")

                NavigationLink(destination: RadioOptionsView(
                    sourceSong: song,
                    sourceTitle: song.title,
                    sourceType: .song
                )) {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .symbolVariant(.fill)
                        .foregroundStyle(WRhythmTheme.accent.gradient)
                }
                .accessibilityLabel("Playlist Gen")

                WRhythmFavoriteButton(
                    isFavorite: downloadManager.starredSongIds.contains(song.id),
                    size: .action,
                    isBusy: isStarring
                ) {
                    toggleFavorite(song)
                }
            }

            HStack(spacing: WRhythmSpacing.xs) {
                if player.queue.count > 1 {
                    WRhythmStatusPill(
                        text: "Track \(player.currentIndex + 1) of \(player.queue.count)",
                        systemImage: "list.bullet",
                        tint: .secondary
                    )
                }

                Button(action: player.toggleShuffle) {
                    Image(systemName: player.isShuffled ? "shuffle.circle.fill" : "shuffle.circle")
                        .font(.title3)
                        .foregroundColor(player.isShuffled ? WRhythmTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle")

                Button(action: player.toggleRepeat) {
                    Image(systemName: player.repeatMode == .off ? "repeat.circle" :
                          player.repeatMode == .all ? "repeat.circle.fill" : "repeat.1.circle.fill")
                        .font(.title3)
                        .foregroundColor(player.repeatMode == .off ? .secondary : WRhythmTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Repeat")
            }
        }
    }

    private var artworkSize: CGFloat {
        min(max(220, availableSize.height * 0.36), availableSize.width - 44)
    }
}

private struct PhoneRemoteNowPlayingContent: View {
    let playback: PlaybackSnapshot
    let availableSize: CGSize
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @Binding var presentedSheet: NowPlayingSheet?
    @Binding var scrubTime: TimeInterval?
    @State private var pendingVolume: Double?

    var body: some View {
        if let song = playback.song {
            VStack(spacing: WRhythmSpacing.sm) {
                NowPlayingArtwork(coverArtId: song.coverArt, maxSize: artworkSize)
                    .equatable()

                PhoneTrackSummary(
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    isBuffering: playback.isBuffering == true,
                    previousBufferedCount: 0,
                    nextBufferedCount: playback.prebufferedTrackCount ?? 0,
                    downloadingCount: 0,
                    showBufferedTracks: { presentedSheet = .bufferedTracks }
                )

                PlaybackProgressTimeline(isLive: playback.isPlaying) {
                    PhoneProgressControl(
                        duration: playback.duration,
                        currentTime: playback.estimatedCurrentTime,
                        scrubTime: $scrubTime,
                        seek: { deviceSyncManager.sendSeek(to: $0, targetDeviceID: playback.id) }
                    )
                }

                HStack(spacing: WRhythmSpacing.xs) {
                    WRhythmTransportButton(
                        systemImage: "backward.end.fill",
                        size: .body,
                        diameter: 44,
                        action: { deviceSyncManager.sendPrevious(targetDeviceID: playback.id) }
                    )

                    WRhythmTransportButton(systemImage: "gobackward.15", size: .body, diameter: 44) {
                        seekRemote(by: -15)
                    }

                    WRhythmTransportButton(
                        systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                        size: .title2,
                        prominent: true,
                        diameter: 58,
                        action: { deviceSyncManager.setPlaying(!playback.isPlaying, targetDeviceID: playback.id) }
                    )

                    WRhythmTransportButton(systemImage: "goforward.15", size: .body, diameter: 44) {
                        seekRemote(by: 15)
                    }

                    WRhythmTransportButton(
                        systemImage: "forward.end.fill",
                        size: .body,
                        diameter: 44,
                        action: { deviceSyncManager.sendNext(targetDeviceID: playback.id) }
                    )

                    NowPlayingResyncButton(diameter: 44)
                }

                InlineVolumeSlider(volume: Binding(
                    get: { displayedVolume },
                    set: { newVolume in
                        pendingVolume = newVolume
                        deviceSyncManager.setVolume(newVolume, targetDeviceID: playback.id)
                    }
                ))

                Button(action: deviceSyncManager.takeOverRemotePlayback) {
                    Label("Play Here", systemImage: "speaker.wave.2.fill")
                        .font(WRhythmTypography.subhead)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WRhythmTheme.accent)
            }
            .onChange(of: playback.volume ?? -1) { _, _ in
                pendingVolume = nil
            }
        } else {
            PhoneNoSongContent()
        }
    }

    private var displayedVolume: Double {
        let volume = pendingVolume ?? playback.volume ?? player.volume
        return min(max(volume.isFinite ? volume : 1, 0), 1)
    }

    private var artworkSize: CGFloat {
        min(max(220, availableSize.height * 0.36), availableSize.width - 44)
    }

    private func seekRemote(by delta: TimeInterval) {
        let upperBound = playback.duration > 0 && playback.duration.isFinite ? playback.duration : .greatestFiniteMagnitude
        let target = min(max(playback.estimatedCurrentTime + delta, 0), upperBound)
        deviceSyncManager.sendSeek(to: target, targetDeviceID: playback.id)
    }
}

private struct PhonePlaybackTargetPicker: View {
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        if deviceSyncManager.syncModeEnabled {
            let targets = deviceSyncManager.availablePlaybackTargets
            let selectedID = deviceSyncManager.validSelectedPlaybackTargetID
            let selectedTarget = targets.first(where: { $0.id == selectedID })

            Menu {
                ForEach(targets) { target in
                    Button {
                        deviceSyncManager.selectPlaybackTarget(target.id)
                    } label: {
                        Label(target.displayName, systemImage: target.iconName)
                    }
                }
            } label: {
                HStack(spacing: WRhythmSpacing.xs) {
                    Image(systemName: selectedTarget?.iconName ?? "speaker.wave.2")
                    Text(selectedTarget?.displayName ?? "This Device")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: WRhythmSpacing.xs)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .font(WRhythmTypography.subhead)
                .foregroundStyle(WRhythmTheme.accent)
                .padding(.horizontal, WRhythmSpacing.sm)
                .frame(height: 44)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .onAppear {
                Task { @MainActor in
                    deviceSyncManager.validateSelectedPlaybackTarget()
                }
            }
            .onChange(of: targets.map(\.id)) { _, _ in
                Task { @MainActor in
                    deviceSyncManager.validateSelectedPlaybackTarget()
                }
            }
        }
    }
}

private struct PhoneTrackSummary: View {
    let title: String
    let artist: String?
    let album: String?
    let isBuffering: Bool
    let previousBufferedCount: Int
    let nextBufferedCount: Int
    let downloadingCount: Int
    let showBufferedTracks: () -> Void

    var body: some View {
        VStack(spacing: WRhythmSpacing.xs) {
            Text(title)
                .font(WRhythmTypography.heroTitle)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)

            if let artist {
                Text(artist)
                    .font(WRhythmTypography.subhead)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let album {
                Text(album)
                    .font(WRhythmTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: WRhythmSpacing.xs) {
                if isBuffering {
                    WRhythmStatusPill(text: "Buffering", systemImage: "hourglass", tint: WRhythmTheme.warning)
                }

                if previousBufferedCount > 0 || nextBufferedCount > 0 || downloadingCount > 0 {
                    BufferedTracksButton(
                        previousCount: previousBufferedCount,
                        nextCount: nextBufferedCount,
                        downloadingCount: downloadingCount,
                        action: showBufferedTracks
                    )
                }
            }
        }
    }
}

private struct PhoneProgressControl: View {
    let duration: TimeInterval
    let currentTime: TimeInterval
    @Binding var scrubTime: TimeInterval?
    let seek: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: WRhythmSpacing.xs) {
            let safeDuration = max(1, duration.isFinite ? duration : 1)
            let liveTime = currentTime.isFinite ? currentTime : 0
            let displayedTime = min(max(scrubTime ?? liveTime, 0), safeDuration)

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
                Text(formatPhonePlaybackTime(displayedTime))
                    .font(WRhythmTypography.metadata)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-" + formatPhonePlaybackTime(max(0, safeDuration - displayedTime)))
                    .font(WRhythmTypography.metadata)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, WRhythmSpacing.sm)
        .padding(.vertical, WRhythmSpacing.xs)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius))
    }
}

private struct PhoneNoSongContent: View {
    var body: some View {
        VStack(spacing: WRhythmSpacing.sm) {
            Spacer(minLength: WRhythmSpacing.xl)
            Image(systemName: "music.note")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No song playing")
                .font(WRhythmTypography.subhead)
                .foregroundStyle(.secondary)
            NowPlayingResyncButton(diameter: 44)
            Spacer(minLength: WRhythmSpacing.xl)
        }
        .frame(maxWidth: .infinity)
    }
}

private func formatPhonePlaybackTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else {
        return "0:00"
    }
    return Duration.seconds(Int(max(0, seconds)))
        .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
}
#endif

private struct BufferedTracksButton: View {
    let previousCount: Int
    let nextCount: Int
    var downloadingCount = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WRhythmStatusPill(
                text: bufferedTrackLabel(
                    previousCount: previousCount,
                    nextCount: nextCount,
                    downloadingCount: downloadingCount
                ),
                systemImage: "arrow.down.circle",
                tint: .secondary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bufferedTrackLabel(
            previousCount: previousCount,
            nextCount: nextCount,
            downloadingCount: downloadingCount
        ))
    }
}

private struct NowPlayingArtwork: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme
    let coverArtId: String?
    let maxSize: CGFloat

    static func == (lhs: NowPlayingArtwork, rhs: NowPlayingArtwork) -> Bool {
        lhs.coverArtId == rhs.coverArtId && lhs.maxSize == rhs.maxSize
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .fill(.regularMaterial)

            if let coverArtId,
               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 420) {
                CachedAsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .padding(1)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: maxSize, maxHeight: maxSize)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06), radius: 12, y: 6)
        .frame(maxWidth: .infinity)
    }
}

struct PlaybackTargetPicker: View {
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        if deviceSyncManager.syncModeEnabled {
            let targets = deviceSyncManager.availablePlaybackTargets
            let selectedID = deviceSyncManager.validSelectedPlaybackTargetID
            let selectedTarget = targets.first(where: { $0.id == selectedID })

            Group {
                #if os(watchOS)
                NavigationLink {
                    List {
                        targetButtons(targets)
                    }
                    .navigationTitle("Play On")
                } label: {
                    targetLabel(selectedTarget)
                }
                .buttonStyle(.plain)
                #else
                Menu {
                    targetButtons(targets)
                } label: {
                    targetLabel(selectedTarget)
                }
                .buttonStyle(.plain)
                #endif
            }
            .font(WRhythmTypography.rowSubtitle)
            .onAppear {
                Task { @MainActor in
                    deviceSyncManager.validateSelectedPlaybackTarget()
                }
            }
            .onChange(of: targets.map(\.id)) { _, _ in
                Task { @MainActor in
                    deviceSyncManager.validateSelectedPlaybackTarget()
                }
            }
        }
    }

    @ViewBuilder
    private func targetButtons(_ targets: [PlaybackTargetDevice]) -> some View {
        ForEach(targets) { target in
            Button {
                deviceSyncManager.selectPlaybackTarget(target.id)
            } label: {
                Label(target.displayName, systemImage: target.iconName)
            }
        }
    }

    private func targetLabel(_ selectedTarget: PlaybackTargetDevice?) -> some View {
        HStack(spacing: WRhythmSpacing.xs) {
            Image(systemName: selectedTarget?.iconName ?? "speaker.wave.2")
            Text(selectedTarget?.displayName ?? "This Device")
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .contentShape(Capsule())
    }
}

struct RemotePlaybackControls: View {
    let playback: PlaybackSnapshot
    let compact: Bool
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @State private var pendingVolume: Double?
    @State private var scrubTime: TimeInterval?

    var body: some View {
        WRhythmCard(padding: compact ? WRhythmSpacing.xs : WRhythmSpacing.md, style: compact ? .grouped : .glass) {
            VStack(spacing: compact ? WRhythmSpacing.xs : WRhythmSpacing.sm) {
                HStack(spacing: WRhythmSpacing.xs) {
                    Image(systemName: platformIconName)
                        .foregroundColor(WRhythmTheme.accent)
                    Text(playback.deviceName)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundColor(.secondary)
                    Spacer()
                    if playback.isBuffering == true {
                        WRhythmStatusPill(text: "Buffering", systemImage: "hourglass", tint: WRhythmTheme.warning)
                    }
                    if let bufferedCount = playback.prebufferedTrackCount,
                       !playback.queue.isEmpty,
                       playback.currentIndex < playback.queue.count - 1 {
                        WRhythmStatusPill(
                            text: bufferedTrackLabel(previousCount: 0, nextCount: bufferedCount),
                            systemImage: "arrow.down.circle"
                        )
                    }
                }

                if let song = playback.song {
                    if !compact {
                        NowPlayingArtwork(coverArtId: song.coverArt, maxSize: 320)
                            .equatable()
                    }

                    VStack(spacing: WRhythmSpacing.xxs) {
                        Text(song.title)
                            .font(compact ? WRhythmTypography.rowSubtitle : WRhythmTypography.featureTitle)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        if let artist = song.artist {
                            Text(artist)
                                .font(WRhythmTypography.metadata)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if !compact {
                        PlaybackProgressTimeline(isLive: playback.isPlaying) {
                            let safeDuration = max(1, playback.duration.isFinite ? playback.duration : 1)
                            let liveTime = playback.estimatedCurrentTime
                            let currentTime = min(max(scrubTime ?? liveTime, 0), safeDuration)
                            VStack(spacing: WRhythmSpacing.xxs) {
                                Slider(
                                    value: Binding(
                                        get: { currentTime },
                                        set: { scrubTime = min(max($0, 0), safeDuration) }
                                    ),
                                    in: 0...safeDuration,
                                    onEditingChanged: { isEditing in
                                        guard !isEditing, let scrubTime else { return }
                                        deviceSyncManager.sendSeek(to: scrubTime, targetDeviceID: playback.id)
                                        self.scrubTime = nil
                                    }
                                )
                                .tint(WRhythmTheme.accent)

                                HStack {
                                    Text(formatTime(currentTime))
                                        .font(WRhythmTypography.metadata)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("-" + formatTime(max(0, safeDuration - currentTime)))
                                        .font(WRhythmTypography.metadata)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    HStack(spacing: compact ? WRhythmSpacing.xs : WRhythmSpacing.sm) {
                        WRhythmTransportButton(
                            systemImage: "backward.end.fill",
                            size: compact ? .caption : .title2,
                            diameter: compact ? 32 : 38,
                            action: { deviceSyncManager.sendPrevious(targetDeviceID: playback.id) }
                        )

                        WRhythmTransportButton(
                            systemImage: "gobackward.15",
                            size: compact ? .caption : .body,
                            diameter: compact ? 32 : 38,
                            action: { seekRemote(by: -15) }
                        )

                        WRhythmTransportButton(
                            systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                            size: compact ? .title3 : .title,
                            prominent: !compact,
                            diameter: compact ? 40 : 56,
                            action: { deviceSyncManager.setPlaying(!playback.isPlaying, targetDeviceID: playback.id) }
                        )

                        WRhythmTransportButton(
                            systemImage: "goforward.15",
                            size: compact ? .caption : .body,
                            diameter: compact ? 32 : 38,
                            action: { seekRemote(by: 15) }
                        )

                        WRhythmTransportButton(
                            systemImage: "forward.end.fill",
                            size: compact ? .caption : .title2,
                            diameter: compact ? 32 : 38,
                            action: { deviceSyncManager.sendNext(targetDeviceID: playback.id) }
                        )

                        WRhythmTransportButton(
                            systemImage: "speaker.wave.2.fill",
                            size: compact ? .title3 : .title2,
                            action: deviceSyncManager.takeOverRemotePlayback
                        )

                        NowPlayingResyncButton(diameter: compact ? 32 : 38)
                    }

                    InlineVolumeSlider(volume: Binding(
                        get: { displayedVolume },
                        set: { newVolume in
                            pendingVolume = newVolume
                            deviceSyncManager.setVolume(newVolume, targetDeviceID: playback.id)
                        }
                    ))
                }
            }
        }
        .onChange(of: playback.volume ?? -1) { _, _ in
            pendingVolume = nil
        }
    }

    private var displayedVolume: Double {
        let volume = pendingVolume ?? playback.volume ?? player.volume
        return min(max(volume.isFinite ? volume : 1, 0), 1)
    }

    private var platformIconName: String {
        switch playback.platform {
        case "Mac":
            return "desktopcomputer"
        case "iPhone":
            return "iphone"
        case "iPad":
            return "ipad"
        case "Apple Watch":
            return "applewatch"
        default:
            return "speaker.wave.2"
        }
    }

    private func seekRemote(by delta: TimeInterval) {
        let upperBound = playback.duration > 0 && playback.duration.isFinite ? playback.duration : .greatestFiniteMagnitude
        let target = min(max(playback.estimatedCurrentTime + delta, 0), upperBound)
        deviceSyncManager.sendSeek(to: target, targetDeviceID: playback.id)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else {
            return "0:00"
        }
        return Duration.seconds(Int(max(0, seconds)))
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }
}

struct InlineVolumeSlider: View {
    @Binding var volume: Double

    var body: some View {
#if os(watchOS)
        WatchVolumeControl(volume: $volume)
#else
        Slider(value: $volume, in: 0...1)
            .tint(WRhythmTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
#endif
    }
}

#if os(watchOS)
private struct WatchVolumeControl: View {
    @Binding var volume: Double

    var body: some View {
        HStack(spacing: 4) {
            volumeButton(systemImage: "speaker.minus.fill", accessibilityLabel: "Lower volume") {
                adjustVolume(by: -0.05)
            }

            WatchVolumeBar(volume: $volume)
                .frame(height: 22)

            volumeButton(systemImage: "speaker.plus.fill", accessibilityLabel: "Raise volume") {
                adjustVolume(by: 0.05)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
    }

    private func volumeButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(WRhythmTypography.metadataEmphasis)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WRhythmTheme.accent)
        .accessibilityLabel(accessibilityLabel)
    }

    private func adjustVolume(by delta: Double) {
        volume = min(max(volume + delta, 0), 1)
    }
}

private struct WatchVolumeBar: View {
    @Binding var volume: Double

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let clampedVolume = min(max(volume, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))

                Capsule()
                    .fill(WRhythmTheme.accent.gradient)
                    .frame(width: max(8, width * clampedVolume))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        volume = min(max(value.location.x / width, 0), 1)
                    }
            )
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int(clampedVolume * 100)) percent")
        }
    }
}
#endif

struct VolumeControlView: View {
    @ObservedObject var player = AudioPlayer.shared
    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Volume")
                        .font(WRhythmTypography.featureTitle)

                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                        Slider(value: $player.volume, in: 0...1)
                            .tint(WRhythmTheme.secondaryAccent)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                    }

                    Text("\(Int(player.volume * 100))%")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Volume")
            .platformNavigationBarTitleDisplayModeInline()
            .platformModalCloseToolbar {
                dismiss()
            }
        }
        .platformExplicitCloseModal()
#if os(watchOS)
        .focusable()
        .focused($isFocused)
        .digitalCrownRotation(
            $player.volume,
            from: 0.0,
            through: 1.0,
            by: 0.05,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onAppear {
            isFocused = true
        }
#endif
    }
}

#if os(iOS) || os(watchOS)
struct AudioRouteView: View {
    @Environment(\.dismiss) var dismiss
    @State private var activeOutputs: [(name: String, type: String, portType: AVAudioSession.Port)] = []

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: WRhythmSpacing.md) {
                Text("Audio Output")
                    .font(WRhythmTypography.featureTitle)

                VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                    if activeOutputs.isEmpty {
                        HStack {
                            Image(systemName: "speaker.slash")
                                .foregroundStyle(.secondary)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No Output")
                                    .font(WRhythmTypography.metadata)
                                    .foregroundColor(.secondary)
                                Text("Unable to detect audio output")
                                    .font(WRhythmTypography.rowSubtitle)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Text("Currently Active")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)

                        ForEach(Array(activeOutputs.enumerated()), id: \.element.name) { index, output in
                            HStack {
                                Image(systemName: audioRouteIcon(for: output.portType))
                                    .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(output.name)
                                        .font(WRhythmTypography.rowSubtitle)
                                        .fontWeight(.medium)
                                    Text(output.type)
                                        .font(WRhythmTypography.metadata)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(WRhythmTheme.success.gradient)
                                    .font(WRhythmTypography.rowSubtitle)
                            }
                            .padding(8)
                            .background(WRhythmTheme.secondaryAccent.opacity(0.10))
                            .cornerRadius(8)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(WRhythmTheme.secondaryAccent.gradient)
                            Text("How to Switch")
                                .font(WRhythmTypography.rowSubtitle)
                                .fontWeight(.semibold)
                        }

                        Text("1. Swipe up from the watch face to open Control Center")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)

                        Text("2. Tap the AirPlay icon")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)

                        Text("3. Select your preferred audio output (AirPods, Speaker, etc.)")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    Text("watchOS doesn't allow apps to programmatically list or switch audio devices. The system manages this through Control Center.")
                        .font(WRhythmTypography.metadata)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Audio Output")
        .platformNavigationBarTitleDisplayModeInline()
            .platformModalCloseToolbar {
                dismiss()
            }
        }
        .platformExplicitCloseModal()
        .onAppear {
            updateAudioRouteInfo()
            setupRouteChangeNotification()
        }
    }

    private func updateAudioRouteInfo() {
        let audioSession = AVAudioSession.sharedInstance()
        let route = audioSession.currentRoute

        // Get ALL current outputs (there can be multiple)
        activeOutputs = route.outputs.map { output in
            print("🎧 Active audio route: \(output.portName) (\(output.portType.rawValue))")
            return (name: output.portName, type: portTypeDescription(output.portType), portType: output.portType)
        }

        print("🎧 Total active outputs: \(activeOutputs.count)")
    }

    private func setupRouteChangeNotification() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("🎧 Audio route changed, updating...")
            Task { @MainActor in
                updateAudioRouteInfo()
            }
        }
    }

    private func portTypeDescription(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInSpeaker:
            return "Built-in Speaker"
        case .headphones:
            return "Headphones"
        case .bluetoothA2DP:
            return "Bluetooth Audio"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .bluetoothHFP:
            return "Bluetooth Handsfree"
        case .airPlay:
            return "AirPlay"
        default:
            return portType.rawValue
        }
    }

    private func audioRouteIcon(for portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInSpeaker:
            return "applewatch"
        case .headphones:
            return "headphones"
        case .bluetoothA2DP, .bluetoothLE:
            return "airpodsmax"
        case .bluetoothHFP:
            return "airpodspro"
        case .airPlay:
            return "airplayvideo"
        case .carAudio:
            return "car.fill"
        case .HDMI:
            return "tv.fill"
        default:
            return "hifispeaker"
        }
    }
}
#else
struct AudioRouteView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: WRhythmSpacing.sm) {
                Image(systemName: "airplayaudio")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Use the macOS audio menu to change output")
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Audio Output")
            .platformNavigationBarTitleDisplayModeInline()
            .platformModalCloseToolbar {
                dismiss()
            }
        }
        .platformExplicitCloseModal()
    }
}
#endif

#if os(watchOS)
private struct WatchNowPlayingView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @State private var isStarring = false
    @State private var hasLoadedStarredSongs = false
    @State private var presentedSheet: NowPlayingSheet?
    @State private var scrubTime: TimeInterval?
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        ScrollView {
            VStack(spacing: WRhythmSpacing.sm) {
                if let remote = primaryRemotePlayback {
                    WatchRemotePlaybackControls(playback: remote)
                } else if let song = player.currentSong {
                    localPlaybackContent(song: song)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 0)
            .padding(.bottom, WRhythmSpacing.xs)
        }
        .wrhythmPageBackground(coverArtId: primaryArtworkCoverArtId)
        .safeAreaPadding(.top, -34)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .volume:
                VolumeControlView()
            case .audioRoute:
                AudioRouteView()
            case .bufferedTracks:
                BufferedTracksListView(
                    availableSongs: player.availablePrebufferedSongs,
                    previousSongs: player.retainedPrebufferedSongs,
                    nextSongs: player.prebufferedSongs,
                    downloadStatuses: player.prebufferDownloadStatuses,
                    qualityLabels: player.availablePrebufferedTrackQualityLabels
                )
            }
        }
        .onAppear {
            if !hasLoadedStarredSongs {
                loadStarredSongs()
            }
        }
        .onChange(of: player.currentSong?.id) { _, _ in
            scrubTime = nil
        }
    }

    private var primaryArtworkCoverArtId: String? {
        if let remote = primaryRemotePlayback {
            return remote.song?.coverArt
        }
        return player.currentSong?.coverArt
    }

    private var primaryRemotePlayback: PlaybackSnapshot? {
        guard let remote = deviceSyncManager.activeSharedPlayback,
              remote.id != deviceSyncManager.localPlaybackTargetID else {
            return nil
        }
        return remote
    }

    private var localIsPlaying: Bool {
        deviceSyncManager.localPlaybackIsPlayingForDisplay
    }

    private func seekLocal(by delta: TimeInterval) {
        let upperBound = player.duration > 0 && player.duration.isFinite ? player.duration : .greatestFiniteMagnitude
        let target = min(max(player.currentTime + delta, 0), upperBound)
        player.seek(to: target)
    }

    @ViewBuilder
    private func localPlaybackContent(song: Song) -> some View {
        VStack(spacing: 4) {
            WatchTrackTitleBlock(song: song)

            NowPlayingArtwork(coverArtId: song.coverArt, maxSize: 52)
                .equatable()

            WatchProgressCard(
                currentTime: player.currentTime,
                duration: player.duration,
                scrubTime: $scrubTime,
                seek: player.seek(to:)
            )

            WatchTransportControls(
                isPlaying: localIsPlaying,
                previousDisabled: player.currentIndex == 0 && player.currentTime < 3,
                nextDisabled: player.currentIndex >= player.queue.count - 1,
                previous: player.previous,
                seekBackward: { seekLocal(by: -15) },
                togglePlay: {
                    deviceSyncManager.setPlaying(
                        !localIsPlaying,
                        targetDeviceID: deviceSyncManager.localPlaybackTargetID
                    )
                },
                seekForward: { seekLocal(by: 15) },
                next: player.next
            )

            WatchResyncButton()

            InlineVolumeSlider(volume: Binding(
                get: { player.volume },
                set: { player.volume = $0 }
            ))

            WatchNowPlayingActions(
                isStarred: downloadManager.starredSongIds.contains(song.id),
                isStarring: isStarring,
                song: song,
                showVolume: { presentedSheet = .volume },
                showAudioRoute: { presentedSheet = .audioRoute },
                toggleFavorite: { toggleFavorite(song: song) }
            )

            HStack(spacing: WRhythmSpacing.xs) {
                if player.queue.count > 1 {
                    Text("\(player.currentIndex + 1) of \(player.queue.count)")
                        .font(WRhythmTypography.metadata)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                PlaybackTargetPicker()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: WRhythmSpacing.xs) {
            PlaybackTargetPicker()

            Image(systemName: "music.note")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("No song playing")
                .font(WRhythmTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            WatchResyncButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius))
    }

    private func loadStarredSongs() {
        Task {
            do {
                let starred = try await NavidromeAPI.shared.getStarred()
                let songIds = Set(starred.song?.map { $0.id } ?? [])
                await MainActor.run {
                    downloadManager.cacheStarredSongs(songIds)
                    hasLoadedStarredSongs = true
                }
            } catch {
                print("❌ Failed to load starred songs: \(error)")
            }
        }
    }

    private func toggleFavorite(song: Song) {
        isStarring = true
        let isCurrentlyStarred = downloadManager.starredSongIds.contains(song.id)

        if offlineMode {
            if isCurrentlyStarred {
                downloadManager.unstarSong(song.id, isOffline: true)
            } else {
                downloadManager.starSong(song.id, isOffline: true)
            }
            isStarring = false
            return
        }

        Task {
            do {
                if isCurrentlyStarred {
                    try await NavidromeAPI.shared.unstar(songId: song.id)
                    await MainActor.run {
                        downloadManager.unstarSong(song.id, isOffline: false)
                        isStarring = false
                    }
                } else {
                    try await NavidromeAPI.shared.star(songId: song.id)
                    await MainActor.run {
                        downloadManager.starSong(song.id, isOffline: false)
                        isStarring = false
                    }
                }
            } catch {
                print("❌ Failed to toggle favorite: \(error)")
                await MainActor.run {
                    isStarring = false
                }
            }
        }
    }
}

private struct WatchRemotePlaybackControls: View {
    @Environment(\.colorScheme) private var colorScheme
    let playback: PlaybackSnapshot
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @State private var pendingVolume: Double?
    @State private var scrubTime: TimeInterval?

    var body: some View {
        VStack(spacing: WRhythmSpacing.xs) {
            HStack(spacing: WRhythmSpacing.xs) {
                Image(systemName: platformIconName)
                    .foregroundStyle(WRhythmTheme.accent)
                Text(playback.deviceName)
                    .font(WRhythmTypography.rowSubtitle)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            if let song = playback.song {
                WatchTrackTitleBlock(song: song)

                NowPlayingArtwork(coverArtId: song.coverArt, maxSize: 50)
                    .equatable()

                PlaybackProgressTimeline(isLive: playback.isPlaying) {
                    WatchProgressCard(
                        currentTime: playback.estimatedCurrentTime,
                        duration: playback.duration,
                        scrubTime: $scrubTime,
                        seek: { time in
                            deviceSyncManager.sendSeek(to: time, targetDeviceID: playback.id)
                        }
                    )
                }

                WatchTransportControls(
                    isPlaying: playback.isPlaying,
                    previousDisabled: false,
                    nextDisabled: false,
                    previous: { deviceSyncManager.sendPrevious(targetDeviceID: playback.id) },
                    seekBackward: { seekRemote(playback, by: -15) },
                    togglePlay: { deviceSyncManager.setPlaying(!playback.isPlaying, targetDeviceID: playback.id) },
                    seekForward: { seekRemote(playback, by: 15) },
                    next: { deviceSyncManager.sendNext(targetDeviceID: playback.id) }
                )

                WatchResyncButton()

                InlineVolumeSlider(volume: Binding(
                    get: { displayedVolume },
                    set: { newVolume in
                        pendingVolume = newVolume
                        deviceSyncManager.setVolume(newVolume, targetDeviceID: playback.id)
                    }
                ))

                Button("Play Here", systemImage: "speaker.wave.2.fill", action: deviceSyncManager.takeOverRemotePlayback)
                    .font(WRhythmTypography.rowSubtitle)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
        .onChange(of: playback.volume ?? -1) { _, _ in
            pendingVolume = nil
        }
    }

    private var displayedVolume: Double {
        let volume = pendingVolume ?? playback.volume ?? player.volume
        return min(max(volume.isFinite ? volume : 1, 0), 1)
    }

    private var platformIconName: String {
        switch playback.platform {
        case "Mac":
            return "desktopcomputer"
        case "iPhone":
            return "iphone"
        case "iPad":
            return "ipad"
        case "Apple Watch":
            return "applewatch"
        default:
            return "speaker.wave.2"
        }
    }

    private func seekRemote(_ playback: PlaybackSnapshot, by delta: TimeInterval) {
        let upperBound = playback.duration > 0 && playback.duration.isFinite ? playback.duration : .greatestFiniteMagnitude
        let target = min(max(playback.estimatedCurrentTime + delta, 0), upperBound)
        deviceSyncManager.sendSeek(to: target, targetDeviceID: playback.id)
    }
}

private struct WatchTrackTitleBlock: View {
    let song: Song

    var body: some View {
        VStack(spacing: 2) {
            Text(song.title)
                .font(WRhythmTypography.featureTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)

            if let artist = song.artist, !artist.isEmpty {
                Text(artist)
                    .font(WRhythmTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WatchProgressCard: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    @Binding var scrubTime: TimeInterval?
    let seek: (TimeInterval) -> Void

    var body: some View {
        let safeDuration = max(1, duration.isFinite ? duration : 1)
        let liveTime = currentTime.isFinite ? currentTime : 0
        let displayedTime = min(max(scrubTime ?? liveTime, 0), safeDuration)

        HStack(spacing: 4) {
            Text(watchFormatTime(displayedTime))
                .frame(width: 31, alignment: .leading)

            WatchScrubBar(
                displayedTime: displayedTime,
                duration: safeDuration,
                scrubTime: $scrubTime,
                seek: seek
            )
            .frame(height: 12)

            Text("-" + watchFormatTime(max(0, safeDuration - displayedTime)))
                .frame(width: 36, alignment: .trailing)
        }
        .font(WRhythmTypography.metadata)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct WatchScrubBar: View {
    let displayedTime: TimeInterval
    let duration: TimeInterval
    @Binding var scrubTime: TimeInterval?
    let seek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = min(max(displayedTime / max(duration, 1), 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))

                Capsule()
                    .fill(WRhythmTheme.accent.gradient)
                    .frame(width: max(8, width * progress))

                Circle()
                    .fill(Color.primary)
                    .frame(width: 7, height: 7)
                    .offset(x: min(max(width * progress - 3.5, 0), width - 7))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        scrubTime = fraction * duration
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        seek(fraction * duration)
                        scrubTime = nil
                    }
            )
            .accessibilityLabel("Playback position")
            .accessibilityValue(watchFormatTime(displayedTime))
        }
    }
}

private struct WatchTransportControls: View {
    let isPlaying: Bool
    let previousDisabled: Bool
    let nextDisabled: Bool
    let previous: () -> Void
    let seekBackward: () -> Void
    let togglePlay: () -> Void
    let seekForward: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            WatchTransportButton("Previous Track", systemImage: "backward.end.fill", action: previous)
                .disabled(previousDisabled)

            WatchTransportButton("Back 15 Seconds", systemImage: "gobackward.15", action: seekBackward)

            WatchTransportButton(
                isPlaying ? "Pause" : "Play",
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                prominent: true,
                action: togglePlay
            )

            WatchTransportButton("Forward 15 Seconds", systemImage: "goforward.15", action: seekForward)

            WatchTransportButton("Next Track", systemImage: "forward.end.fill", action: next)
                .disabled(nextDisabled)
        }
    }
}

private struct WatchTransportButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    init(_ title: String, systemImage: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(prominent ? .title3 : .caption.weight(.semibold))
            .frame(width: prominent ? 38 : 27, height: prominent ? 38 : 27)
            .background(prominent ? AnyShapeStyle(WRhythmTheme.accent.gradient) : AnyShapeStyle(.regularMaterial), in: Circle())
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(prominent ? 0.18 : 0.06), radius: prominent ? 8 : 4, y: prominent ? 4 : 2)
    }
}

private struct WatchResyncButton: View {
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        Button(action: deviceSyncManager.searchForNearbyDevices) {
            Label("Reconnect", systemImage: "arrow.clockwise")
                .font(WRhythmTypography.metadataEmphasis)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WRhythmTheme.accent)
        .disabled(!deviceSyncManager.syncModeEnabled && !deviceSyncManager.credentialSyncEnabled)
        .accessibilityLabel("Reconnect and resync nearby devices")
    }
}

private struct WatchNowPlayingActions: View {
    let isStarred: Bool
    let isStarring: Bool
    let song: Song
    let showVolume: () -> Void
    let showAudioRoute: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            watchActionButton("Volume", systemImage: "speaker.wave.3.fill", action: showVolume)
            watchActionButton("Output", systemImage: "airpodsmax", action: showAudioRoute)
            NavigationLink(destination: RadioOptionsView(sourceSong: song, sourceTitle: song.title, sourceType: .song)) {
                Image(systemName: "music.note.list")
                    .frame(width: 28, height: 28)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Radio")

            WRhythmFavoriteButton(
                isFavorite: isStarred,
                size: .watch,
                isBusy: isStarring,
                action: toggleFavorite
            )
        }
        .font(WRhythmTypography.controlLabelEmphasis)
        .buttonStyle(.plain)
        .foregroundStyle(WRhythmTheme.accent)
    }

    private func watchActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel(title)
    }
}

private func watchFormatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else {
        return "0:00"
    }
    return Duration.seconds(Int(max(0, seconds)))
        .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
}
#endif

#Preview {
    NavigationStack {
        NowPlayingView()
    }
}
