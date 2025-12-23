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
                                get: { player.currentTime },
                                set: { player.seek(to: $0) }
                            ),
                            in: 0...max(player.duration, 1)
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

                    if player.queue.count > 1 {
                        Text("Track \(player.currentIndex + 1) of \(player.queue.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
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
