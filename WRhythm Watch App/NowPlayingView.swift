//
//  NowPlayingView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI
import AVFoundation

struct NowPlayingView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @State private var isStarring = false
    @State private var hasLoadedStarredSongs = false
    @State private var showVolumeControl = false
    @State private var showAudioRouteMenu = false
    @State private var scrubTime: TimeInterval?
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        ScrollView {
            if let remote = primaryRemotePlayback {
                VStack(spacing: 12) {
                    PlaybackTargetPicker()
                    RemotePlaybackControls(playback: remote, compact: false)
                }
                .padding()
            } else if let song = player.currentSong {
                VStack(spacing: 18) {
                    NowPlayingArtwork(coverArtId: song.coverArt, maxSize: 360)
                        .equatable()

                    VStack(spacing: 8) {
                        Text(song.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)

                        if let artist = song.artist {
                            Text(artist)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let album = song.album {
                            Text(album)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            WRhythmStatusPill(
                                text: player.isPlaying ? "Playing" : "Paused",
                                systemImage: player.isPlaying ? "waveform" : "pause.fill",
                                tint: player.isPlaying ? .accentColor : .secondary
                            )
                            if player.isBuffering {
                                WRhythmStatusPill(text: "Buffering", systemImage: "hourglass", tint: .orange)
                            }
                            if player.queue.count > player.currentIndex + 1 {
                                WRhythmStatusPill(
                                    text: bufferedTrackLabel(player.prebufferedTrackCount),
                                    systemImage: "arrow.down.circle",
                                    tint: .secondary
                                )
                            }
                        }
                    }

                    PlaybackTargetPicker()

                    VStack(spacing: 6) {
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
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))

                    HStack(spacing: 22) {
                        WRhythmTransportButton(systemImage: "backward.end.fill", action: player.previous)
                        .disabled(player.currentIndex == 0 && player.currentTime < 3)

                        WRhythmTransportButton(
                            systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                            size: .title,
                            prominent: true,
                            action: player.togglePlayPause
                        )

                        WRhythmTransportButton(systemImage: "forward.end.fill", action: player.next)
                        .disabled(player.currentIndex >= player.queue.count - 1)
                    }

                    InlineVolumeSlider(volume: Binding(
                        get: { player.volume },
                        set: { player.volume = $0 }
                    ))

                    // Action buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            showVolumeControl = true
                        }) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.title3)
                                .symbolVariant(.fill)
                                .foregroundStyle(.blue.gradient)
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            showAudioRouteMenu = true
                        }) {
                            Image(systemName: "airpodsmax")
                                .font(.title3)
                                .symbolVariant(.fill)
                                .foregroundStyle(.teal.gradient)
                        }
                        .buttonStyle(.bordered)

                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "music.note.list")
                                .font(.title3)
                                .symbolVariant(.fill)
                                .foregroundStyle(.purple.gradient)
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            toggleFavorite(song: song)
                        }) {
                            Image(systemName: downloadManager.starredSongIds.contains(song.id) ? "heart.fill" : "heart")
                                .font(.title3)
                                .symbolVariant(.fill)
                                .foregroundStyle(.red.gradient)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isStarring)
                    }

                    HStack(spacing: 8) {
                        if player.queue.count > 1 {
                            Text("Track \(player.currentIndex + 1) of \(player.queue.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Button(action: player.toggleShuffle) {
                            Image(systemName: player.isShuffled ? "shuffle.circle.fill" : "shuffle.circle")
                                .font(.caption)
                                .foregroundColor(player.isShuffled ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: player.toggleRepeat) {
                            Image(systemName: player.repeatMode == .off ? "repeat.circle" :
                                  player.repeatMode == .all ? "repeat.circle.fill" : "repeat.1.circle.fill")
                                .font(.caption)
                                .foregroundColor(player.repeatMode == .off ? .secondary : .accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)

                    if primaryRemotePlayback == nil,
                       deviceSyncManager.syncModeEnabled,
                       let remote = deviceSyncManager.activeSharedPlayback ?? deviceSyncManager.remotePlayback,
                       remote.song != nil {
                        Divider()
                        RemotePlaybackControls(playback: remote, compact: true)
                    }
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .id(song.id)
            } else if deviceSyncManager.syncModeEnabled,
                      let remote = deviceSyncManager.activeSharedPlayback ?? deviceSyncManager.remotePlayback,
                      remote.song != nil {
                VStack(spacing: 12) {
                    PlaybackTargetPicker()
                    RemotePlaybackControls(playback: remote, compact: false)
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    PlaybackTargetPicker()

                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No song playing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .background(WRhythmArtworkBackdrop(coverArtId: primaryArtworkCoverArtId).ignoresSafeArea())
        .navigationTitle("Now Playing")
        .sheet(isPresented: $showVolumeControl) {
            VolumeControlView()
        }
        .sheet(isPresented: $showAudioRouteMenu) {
            AudioRouteView()
        }
        .onAppear {
            if !hasLoadedStarredSongs {
                loadStarredSongs()
            }
        }
    }

    private var primaryArtworkCoverArtId: String? {
        if let remote = primaryRemotePlayback {
            return remote.song?.coverArt
        }
        return player.currentSong?.coverArt
    }

    private var primaryRemotePlayback: PlaybackSnapshot? {
        if let sharedPlayback = deviceSyncManager.activeSharedPlayback {
            return sharedPlayback
        }

        guard deviceSyncManager.syncModeEnabled,
              let remote = deviceSyncManager.remotePlayback,
              remote.song != nil else {
            return nil
        }

        if player.currentSong == nil || deviceSyncManager.validSelectedPlaybackTargetID == remote.id {
            return remote
        }

        return nil
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
        Task {
            do {
                print("🎵 Starting radio for: \(song.title)")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(song, count: 100)
                print("📻 ID3 similar songs returned \(similarSongs.count) songs")

                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: 100)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found even with fallbacks, playing original song")
                        player.playSong(song)
                    } else {
                        // Filter out the source song if it appears in results
                        let filteredSongs = similarSongs.filter { $0.id != song.id }

                        // Build queue with source song first, then similar songs
                        var queue = [song]
                        queue.append(contentsOf: filteredSongs)

                        print("✅ Radio queue ready: 1 source song + \(filteredSongs.count) similar songs = \(queue.count) total")
                        player.playGeneratedPlaylist(sourceSong: song, songs: queue)
                        print("📻 Queue after playQueue: \(player.queue.count) songs")
                    }
                }
            } catch {
                print("❌ Failed to start radio: \(error)")
                // Final fallback: just play the song
                await MainActor.run {
                    player.playSong(song)
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else {
            return "0:00"
        }
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private func bufferedTrackLabel(_ count: Int) -> String {
    "\(count) \(count == 1 ? "track" : "tracks") buffered"
}

private struct NowPlayingArtwork: View, Equatable {
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
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)
        .frame(maxWidth: .infinity)
    }
}

struct PlaybackTargetPicker: View {
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        if deviceSyncManager.syncModeEnabled {
            let targets = deviceSyncManager.availablePlaybackTargets
            Picker(
                "Play On",
                selection: Binding(
                    get: { deviceSyncManager.validSelectedPlaybackTargetID },
                    set: { deviceSyncManager.selectPlaybackTarget($0) }
                )
            ) {
                ForEach(targets) { target in
                    Label(target.displayName, systemImage: target.iconName)
                        .tag(target.id)
                }
            }
            #if os(watchOS)
            .pickerStyle(.navigationLink)
            #else
            .pickerStyle(.menu)
            #endif
            .font(.caption)
            .onAppear {
                deviceSyncManager.validateSelectedPlaybackTarget()
            }
            .onChange(of: targets.map(\.id)) { _, _ in
                deviceSyncManager.validateSelectedPlaybackTarget()
            }
        }
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
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Image(systemName: playback.platform == "Mac" ? "desktopcomputer" : playback.platform == "iPhone" ? "iphone" : "applewatch")
                    .foregroundColor(.accentColor)
                Text(playback.deviceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                WRhythmStatusPill(
                    text: playback.isPlaying ? "Playing" : "Paused",
                    systemImage: playback.isPlaying ? "waveform" : "pause.fill",
                    tint: playback.isPlaying ? .accentColor : .secondary
                )
                if playback.isBuffering == true {
                    WRhythmStatusPill(text: "Buffering", systemImage: "hourglass", tint: .orange)
                }
                if let bufferedCount = playback.prebufferedTrackCount,
                   !playback.queue.isEmpty,
                   playback.currentIndex < playback.queue.count - 1 {
                    WRhythmStatusPill(text: "\(bufferedCount) buffered", systemImage: "arrow.down.circle")
                }
            }

            if let song = playback.song {
                if !compact {
                    NowPlayingArtwork(coverArtId: song.coverArt, maxSize: 320)
                        .equatable()
                }

                VStack(spacing: 4) {
                    Text(song.title)
                        .font(compact ? .caption : .headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let artist = song.artist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if !compact {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let safeDuration = max(1, playback.duration.isFinite ? playback.duration : 1)
                        let liveTime = playback.estimatedCurrentTime
                        let currentTime = min(max(scrubTime ?? liveTime, 0), safeDuration)
                        VStack(spacing: 4) {
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
                            .tint(.accentColor)

                            HStack {
                                Text(formatTime(currentTime))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("-" + formatTime(max(0, safeDuration - currentTime)))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                HStack(spacing: compact ? 14 : 22) {
                    WRhythmTransportButton(
                        systemImage: "backward.end.fill",
                        size: compact ? .caption : .title2,
                        action: { deviceSyncManager.sendPrevious(targetDeviceID: playback.id) }
                    )

                    WRhythmTransportButton(
                        systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                        size: compact ? .title3 : .title,
                        prominent: !compact,
                        action: { deviceSyncManager.setPlaying(!playback.isPlaying, targetDeviceID: playback.id) }
                    )

                    WRhythmTransportButton(
                        systemImage: "forward.end.fill",
                        size: compact ? .caption : .title2,
                        action: { deviceSyncManager.sendNext(targetDeviceID: playback.id) }
                    )

                    WRhythmTransportButton(
                        systemImage: "speaker.wave.2.fill",
                        size: compact ? .title3 : .title2,
                        action: deviceSyncManager.takeOverRemotePlayback
                    )
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
        .padding(compact ? 10 : 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: compact ? WRhythmVisual.compactCornerRadius : WRhythmVisual.cornerRadius, style: .continuous))
        .onChange(of: playback.volume ?? -1) { _, _ in
            pendingVolume = nil
        }
    }

    private var displayedVolume: Double {
        let volume = pendingVolume ?? playback.volume ?? player.volume
        return min(max(volume.isFinite ? volume : 1, 0), 1)
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

struct InlineVolumeSlider: View {
    @Binding var volume: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .foregroundColor(.secondary)
            Slider(value: $volume, in: 0...1)
                .tint(.accentColor)
            Image(systemName: "speaker.wave.3.fill")
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
    }
}

struct VolumeControlView: View {
    @ObservedObject var player = AudioPlayer.shared
    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Volume")
                    .font(.headline)

                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.green.gradient)
                    Slider(value: $player.volume, in: 0...1)
                        .tint(.green)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.green.gradient)
                }

                Text("\(Int(player.volume * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
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
        ScrollView {
            VStack(spacing: 16) {
                Text("Audio Output")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    if activeOutputs.isEmpty {
                        HStack {
                            Image(systemName: "speaker.slash")
                                .foregroundStyle(.secondary)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No Output")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Unable to detect audio output")
                                    .font(.caption)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Text("Currently Active")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        ForEach(Array(activeOutputs.enumerated()), id: \.element.name) { index, output in
                            HStack {
                                Image(systemName: audioRouteIcon(for: output.portType))
                                    .foregroundStyle(.teal.gradient)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(output.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(output.type)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green.gradient)
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(Color.teal.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue.gradient)
                            Text("How to Switch")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        Text("1. Swipe up from the watch face to open Control Center")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("2. Tap the AirPlay icon")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("3. Select your preferred audio output (AirPods, Speaker, etc.)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    Text("watchOS doesn't allow apps to programmatically list or switch audio devices. The system manages this through Control Center.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
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
            updateAudioRouteInfo()
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
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplayaudio")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Use the macOS audio menu to change output")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
#endif

#Preview {
    NavigationView {
        NowPlayingView()
    }
}
