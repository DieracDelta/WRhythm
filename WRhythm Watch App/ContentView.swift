//
//  ContentView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var api = NavidromeAPI.shared
    @ObservedObject var player = AudioPlayer.shared
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
                    MenuView()
                        .tabItem {
                            Label("Menu", systemImage: "list.bullet")
                        }
                        .tag(0)

                    NavigationView {
                        NowPlayingView()
                    }
                    .tabItem {
                        Label("Playing", systemImage: "play.circle.fill")
                    }
                    .tag(1)
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // When app becomes active, go to Now Playing if music is playing
                        if player.isPlaying {
                            selectedTab = 1
                        }
                    }
                }
#endif
            } else {
                LoginView()
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
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    ForEach(MacDestination.allCases, id: \.self) { destination in
                        NavigationLink(value: destination) {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                    }
                }

                Section(localQueueSectionTitle) {
                    if player.queue.isEmpty {
                        Text("No queued songs")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(player.queue.enumerated()), id: \.offset) { index, song in
                            Button(action: {
                                selection = .nowPlaying
                                player.playQueue(player.queue, startingAt: index)
                            }) {
                                HStack(spacing: 8) {
                                    if player.currentSong?.id == song.id {
                                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker")
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
                            .buttonStyle(.plain)
                            .contextMenu {
                                TrackContextMenuItems(song: song)
                            }
                        }
                    }
                }

                if deviceSyncManager.syncModeEnabled,
                   let remote = activeRemotePlayback,
                   !remoteQueueMatchesLocal {
                    Section("\(remote.deviceName) Queue") {
                        if remoteQueue.isEmpty {
                            Text("No queued songs")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(remoteQueue.enumerated()), id: \.offset) { index, song in
                                Button(action: {
                                    selection = .nowPlaying
                                    deviceSyncManager.playRemoteQueueItem(remote, at: index)
                                }) {
                                    HStack(spacing: 8) {
                                        if remote.currentIndex == index {
                                            Image(systemName: remote.isPlaying ? "speaker.wave.2.fill" : "speaker")
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
                                .buttonStyle(.plain)
                                .contextMenu {
                                    TrackContextMenuItems(song: song)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("WRhythm")
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    destinationView(for: selection ?? .nowPlaying)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if selection != .nowPlaying,
                       player.currentSong != nil || deviceSyncManager.remotePlayback?.song != nil {
                        Divider()
                        MacMiniPlayerBar(selection: $selection)
                    }
                }
            }
        }
    }

    private var activeRemotePlayback: PlaybackSnapshot? {
        guard let remote = deviceSyncManager.remotePlayback, remote.song != nil else { return nil }
        return remote
    }

    private var remoteQueue: [Song] {
        guard let remote = activeRemotePlayback else { return [] }
        return remote.queue.isEmpty ? remote.song.map { [$0] } ?? [] : remote.queue
    }

    private var remoteQueueMatchesLocal: Bool {
        guard !player.queue.isEmpty, !remoteQueue.isEmpty else { return false }
        return player.queue.map(\.id) == remoteQueue.map(\.id)
    }

    private var localQueueSectionTitle: String {
        remoteQueueMatchesLocal ? "Shared Queue" : "Mac Queue"
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

struct MacMiniPlayerBar: View {
    @Binding var selection: MacDestination?
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if let song = player.currentSong, !shouldHideLocalRow {
                miniRow(
                    title: song.title,
                    subtitle: [song.artist, song.album].compactMap { $0 }.joined(separator: " • "),
                    isPlaying: player.isPlaying,
                    queuePosition: player.queue.count > 1 ? "\(localLabel): \(player.currentIndex + 1) of \(player.queue.count)" : localLabel,
                    previous: player.previous,
                    toggle: player.togglePlayPause,
                    next: player.next,
                    previousDisabled: player.currentIndex == 0 && player.currentTime < 3,
                    nextDisabled: player.currentIndex >= player.queue.count - 1
                )
            }

            if deviceSyncManager.syncModeEnabled,
               let remote = deviceSyncManager.remotePlayback,
               let song = remote.song,
               !shouldHideRemoteRow {
                if player.currentSong != nil, !shouldHideLocalRow {
                    Divider()
                }
                miniRow(
                    title: song.title,
                    subtitle: [song.artist, song.album].compactMap { $0 }.joined(separator: " • "),
                    isPlaying: remote.isPlaying,
                    queuePosition: remote.queue.count > 1 ? "\(remote.deviceName): \(remote.currentIndex + 1) of \(remote.queue.count)" : remote.deviceName,
                    previous: { deviceSyncManager.sendPrevious(targetDeviceID: remote.id) },
                    toggle: { deviceSyncManager.sendPlayPause(targetDeviceID: remote.id) },
                    next: { deviceSyncManager.sendNext(targetDeviceID: remote.id) },
                    previousDisabled: remote.currentIndex == 0 && remote.currentTime < 3,
                    nextDisabled: remote.currentIndex >= remote.queue.count - 1
                )
            }
        }
        .background(.bar)
    }

    private var remoteQueue: [Song] {
        guard let remote = deviceSyncManager.remotePlayback else { return [] }
        return remote.queue.isEmpty ? remote.song.map { [$0] } ?? [] : remote.queue
    }

    private var remoteQueueMatchesLocal: Bool {
        guard !player.queue.isEmpty, !remoteQueue.isEmpty else { return false }
        return player.queue.map(\.id) == remoteQueue.map(\.id)
    }

    private var shouldHideLocalRow: Bool {
        remoteQueueMatchesLocal && !player.isPlaying
    }

    private var shouldHideRemoteRow: Bool {
        remoteQueueMatchesLocal && player.isPlaying
    }

    private var localLabel: String {
        remoteQueueMatchesLocal ? "Shared Queue" : "Mac"
    }

    private func miniRow(
        title: String,
        subtitle: String,
        isPlaying: Bool,
        queuePosition: String,
        previous: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        previousDisabled: Bool,
        nextDisabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                selection = .nowPlaying
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(queuePosition)
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

            Button(action: previous) {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(previousDisabled)

            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Button(action: next) {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(nextDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
#endif
