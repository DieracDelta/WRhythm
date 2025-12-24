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
