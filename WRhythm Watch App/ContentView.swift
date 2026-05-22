//
//  ContentView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var api = NavidromeAPI.shared
#if os(macOS)
    @State private var selectedMacDestination: MacDestination? = .nowPlaying
#else
    @State private var selectedTab = 0
#endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if api.isAuthenticated {
#if os(macOS)
                MacContentLayout(selection: $selectedMacDestination)
#else
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        MenuView()
                    }
                        .tabItem {
                            Label("Library", systemImage: "square.grid.2x2")
                        }
                        .tag(0)

                    NavigationStack {
                        TracksView()
                    }
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(1)

                    NavigationStack {
                        NowPlayingView()
                    }
                    .tabItem {
                        Label("Playing", systemImage: "play.circle.fill")
                    }
                    .tag(2)

                    NavigationStack {
                        DownloadsView()
                    }
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    .tag(3)
                }
#endif
            } else {
                LoginView()
            }
        }
        .wrhythmPageBackground()
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                DeviceSyncManager.shared.requestPlaybackSyncRefresh()
#if !os(macOS)
                // When app becomes active, go to Now Playing if music is playing
                if AudioPlayer.shared.isPlaying {
                    selectedTab = 2
                }
#endif
            case .inactive, .background:
                AudioPlayer.shared.persistPlaybackStateNow()
            @unknown default:
                AudioPlayer.shared.persistPlaybackStateNow()
            }
        }
    }
}

#Preview {
    ContentView()
}

#if os(macOS)
enum MacDestination: String, Hashable, CaseIterable {
    case nowPlaying
    case artists
    case playlists
    case favorites
    case playlistGen
    case tracks
    case spontaneous
    case albums
    case downloads
    case settings

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .artists: return "Artists"
        case .playlists: return "Playlists"
        case .favorites: return "Favorites"
        case .playlistGen: return "Playlist Gen"
        case .tracks: return "Tracks"
        case .spontaneous: return "Spontaneous"
        case .albums: return "Albums"
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
        case .playlistGen: return "music.note.list"
        case .tracks: return "magnifyingglass"
        case .spontaneous: return "shuffle"
        case .albums: return "square.stack"
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

                Section(localQueueSectionTitle) {
                    if displayedQueue.isEmpty {
                        Text("No queued songs")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(queueItems(displayedQueue)) { item in
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
                            .contextMenu {
                                TrackContextMenuItems(song: item.song)
                            }
                        }
                    }
                }

                if deviceSyncManager.syncModeEnabled,
                   let remote = activeRemotePlayback,
                   !remoteQueueMatchesDisplayed {
                    Section("\(remote.deviceName) Queue") {
                        if remoteQueue.isEmpty {
                            Text("No queued songs")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(queueItems(remoteQueue)) { item in
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
                                .contextMenu {
                                    TrackContextMenuItems(song: item.song)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("WRhythm")
            .wrhythmListSurface()
    }

    private var activeRemotePlayback: PlaybackSnapshot? {
        deviceSyncManager.activeSharedPlayback
    }

    private var displayedQueue: [Song] {
        if !deviceSyncManager.sharedQueue.isEmpty {
            return deviceSyncManager.sharedQueue
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
        deviceSyncManager.sharedSession != nil || remoteQueueMatchesLocal ? "Shared Queue" : "Mac Queue"
    }

    private func queueItems(_ songs: [Song]) -> [QueueDisplayItem] {
        songs.enumerated().map { index, song in
            QueueDisplayItem(index: index, song: song)
        }
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
        HStack(spacing: 8) {
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct MacDetailContent: View {
    @Binding var selection: MacDestination?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                destinationView(for: selection ?? .nowPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                MacMiniPlayerAttachment(selection: $selection)
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
        case .playlistGen:
            RadioPlaylistsView()
        case .tracks:
            TracksView()
        case .spontaneous:
            SpontaneousMusicView()
        case .albums:
            AlbumsView()
        case .downloads:
            DownloadsView()
        case .settings:
            SettingsView()
        }
    }
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
                    prebufferedTrackCount: player.prebufferedTrackCount,
                    queuePosition: player.queue.count > 1 ? "\(localLabel): \(player.currentIndex + 1) of \(player.queue.count)" : localLabel,
                    previous: player.previous,
                    toggle: { deviceSyncManager.setPlaying(!isPlaying, targetDeviceID: deviceSyncManager.localPlaybackTargetID) },
                    next: player.next,
                    currentTime: { player.currentTime },
                    duration: player.duration,
                    seek: { player.seek(to: $0) },
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
                    prebufferedTrackCount: remote.prebufferedTrackCount,
                    queuePosition: remote.queue.count > 1 ? "\(remote.deviceName): \(remote.currentIndex + 1) of \(remote.queue.count)" : remote.deviceName,
                    previous: { deviceSyncManager.sendPrevious(targetDeviceID: remote.id) },
                    toggle: { deviceSyncManager.setPlaying(!remote.isPlaying, targetDeviceID: remote.id) },
                    next: { deviceSyncManager.sendNext(targetDeviceID: remote.id) },
                    currentTime: { remote.estimatedCurrentTime },
                    duration: remote.duration,
                    seek: { deviceSyncManager.sendSeek(to: $0, targetDeviceID: remote.id) },
                    previousDisabled: remote.currentIndex == 0 && remote.currentTime < 3,
                    nextDisabled: remote.currentIndex >= remote.queue.count - 1
                )
            }

            if player.currentSong != nil || deviceSyncManager.activeSharedPlayback?.song != nil {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.secondary)
                    Slider(value: $player.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(.bar)
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

    private func miniRow(
        coverArtId: String?,
        title: String,
        subtitle: String,
        isPlaying: Bool,
        isBuffering: Bool,
        prebufferedTrackCount: Int?,
        queuePosition: String,
        previous: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        currentTime: @escaping () -> TimeInterval,
        duration: TimeInterval,
        seek: @escaping (TimeInterval) -> Void,
        previousDisabled: Bool,
        nextDisabled: Bool
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                MiniPlayerArtwork(coverArtId: coverArtId)

                Button(action: {
                    selection = .nowPlaying
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(miniStatusText(queuePosition: queuePosition, isBuffering: isBuffering, prebufferedTrackCount: prebufferedTrackCount))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

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
                seek: seek
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func miniStatusText(queuePosition: String, isBuffering: Bool, prebufferedTrackCount: Int?) -> String {
        var parts = [queuePosition]
        if isBuffering {
            parts.append("Buffering")
        }
        if let prebufferedTrackCount {
            parts.append("\(prebufferedTrackCount) buffered")
        }
        return parts.joined(separator: " • ")
    }
}

private struct MiniPlayerArtwork: View {
    let coverArtId: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)

            if let coverArtId,
               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 96) {
                CachedAsyncImage(url: coverURL) { image in
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
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

struct MiniPlayerProgressControl: View {
    let currentTime: () -> TimeInterval
    let duration: TimeInterval
    let seek: (TimeInterval) -> Void
    @State private var scrubTime: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let liveTime = sanitizedTime(currentTime())
            let displayedTime = min(max(scrubTime ?? liveTime, 0), safeDuration)

            VStack(spacing: 2) {
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
                .tint(.accentColor)

                HStack {
                    Text(formatTime(displayedTime))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("-" + formatTime(max(0, safeDuration - displayedTime)))
                        .font(.caption2)
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
        let minutes = Int(max(0, seconds)) / 60
        let remainingSeconds = Int(max(0, seconds)) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

}
#endif
