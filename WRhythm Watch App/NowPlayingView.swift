//
//  NowPlayingView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var isStarring = false
    @State private var isSyncing = false
    @State private var hasLoadedStarredSongs = false
    @State private var showVolumeControl = false
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        ScrollView {
            if let song = player.currentSong {
                VStack(spacing: 12) {
                    if let coverArtId = song.coverArt,
                       let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                        CachedAsyncImage(url: coverURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .frame(height: 120)
                        .cornerRadius(8)
                    }

                    VStack(spacing: 4) {
                        Text(song.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        if let artist = song.artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let album = song.album {
                            Text(album)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: {
                                    let time = player.currentTime
                                    return time.isNaN || time.isInfinite ? 0 : time
                                },
                                set: { player.seek(to: $0) }
                            ),
                            in: 0...max(1, player.duration.isNaN || player.duration.isInfinite ? 1 : player.duration)
                        )
                        .tint(.accentColor)

                        HStack {
                            Text(formatTime(player.currentTime))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("-" + formatTime(player.duration - player.currentTime))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 25) {
                        Button(action: player.previous) {
                            Image(systemName: "backward.end.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(player.currentIndex == 0 && player.currentTime < 3)

                        Button(action: player.togglePlayPause) {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.largeTitle)
                        }
                        .buttonStyle(.plain)

                        Button(action: player.next) {
                            Image(systemName: "forward.end.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(player.currentIndex >= player.queue.count - 1)
                    }

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
                        
                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: song,
                            sourceTitle: song.title,
                            sourceType: .song
                        )) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
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
                }
                .padding()
                .id(song.id)
            } else {
                VStack(spacing: 8) {
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
        .navigationTitle("Now Playing")
        .sheet(isPresented: $showVolumeControl) {
            VolumeControlView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    syncFavorites()
                }) {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isSyncing)
            }
        }
        .onAppear {
            if !hasLoadedStarredSongs {
                loadStarredSongs()
            }
        }
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

    private func syncFavorites() {
        isSyncing = true
        Task {
            do {
                // First, sync any pending local changes to server
                try await downloadManager.syncPendingStarChanges()

                // Then fetch the latest from server
                let starred = try await NavidromeAPI.shared.getStarred()
                let songIds = Set(starred.song?.map { $0.id } ?? [])
                await MainActor.run {
                    downloadManager.cacheStarredSongs(songIds)
                    isSyncing = false
                }
                print("✅ Favorites synced: \(songIds.count) songs")
            } catch {
                print("❌ Failed to sync favorites: \(error)")
                await MainActor.run {
                    isSyncing = false
                }
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
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs(id: song.id, count: 100)
                print("📻 getSimilarSongs returned \(similarSongs.count) songs")

                // Fallback 1: Try artist-based radio if no results
                if similarSongs.isEmpty, let artistId = song.artistId {
                    print("📻 Falling back to artist radio for artist ID: \(artistId)")
                    similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: 100)
                    print("📻 getSimilarSongs2 returned \(similarSongs.count) songs")
                }

                // Fallback 2: Try random songs if still empty
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
                        player.playQueue(queue, startingAt: 0)
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
    }
}

#Preview {
    NavigationView {
        NowPlayingView()
    }
}