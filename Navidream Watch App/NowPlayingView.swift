//
//  NowPlayingView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        ScrollView {
            if let song = player.currentSong {
                VStack(spacing: 12) {
                    if let coverArtId = song.coverArt,
                       let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                        AsyncImage(url: coverURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray
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

                        HStack {
                            Text(formatTime(player.currentTime))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(player.duration))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 20) {
                        Button(action: player.previous) {
                            Image(systemName: "backward.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(player.currentIndex == 0 && player.currentTime < 3)

                        Button(action: player.togglePlayPause) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        Button(action: player.next) {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(player.currentIndex >= player.queue.count - 1)
                    }

                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Slider(value: $player.volume, in: 0...1)
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }

                    // Radio button
                    NavigationLink(destination: RadioOptionsView(
                        sourceSong: song,
                        sourceTitle: song.title,
                        sourceType: .song
                    )) {
                        Label("Radio", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    if player.queue.count > 1 {
                        HStack(spacing: 8) {
                            Text("Track \(player.currentIndex + 1) of \(player.queue.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Button(action: player.toggleShuffle) {
                                Image(systemName: player.isShuffled ? "shuffle.circle.fill" : "shuffle.circle")
                                    .font(.caption)
                                    .foregroundColor(player.isShuffled ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
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

#Preview {
    NavigationView {
        NowPlayingView()
    }
}
