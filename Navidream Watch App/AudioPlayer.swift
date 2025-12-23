//
//  AudioPlayer.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer

class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var queue: [Song] = []
    @Published var currentIndex: Int = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    func playSong(_ song: Song) {
        self.queue = [song]
        self.currentIndex = 0
        startPlayback(song)
    }

    func playQueue(_ songs: [Song], startingAt index: Int = 0) {
        guard !songs.isEmpty, index < songs.count else { return }

        self.queue = songs
        self.currentIndex = index
        startPlayback(songs[index])
    }

    private func startPlayback(_ song: Song) {
        print("🎵 AudioPlayer: startPlayback called")
        print("🎵 Song: \(song.title) by \(song.artist ?? "Unknown")")
        print("🎵 Song ID: \(song.id)")
        print("🎵 Content type: \(song.contentType ?? "unknown")")
        print("🎵 Suffix: \(song.suffix ?? "unknown")")

        self.currentSong = song

        // Check if song is downloaded first
        let playURL: URL
        if let localURL = DownloadManager.shared.getLocalURL(song.id) {
            playURL = localURL
            print("🎵 Playing from local file: \(localURL.lastPathComponent)")
        } else if let streamURL = NavidromeAPI.shared.getStreamURL(id: song.id) {
            playURL = streamURL
            print("🎵 Streaming from: \(streamURL.absoluteString)")
        } else {
            print("❌ Failed to get playback URL")
            return
        }

        print("🎵 Playback URL: \(playURL.absoluteString)")

        let playerItem = AVPlayerItem(url: playURL)
        player = AVPlayer(playerItem: playerItem)

        addPeriodicTimeObserver()
        observePlayerItem(playerItem)

        player?.play()
        isPlaying = true

        updateNowPlayingInfo()
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func next() {
        guard currentIndex < queue.count - 1 else { return }
        currentIndex += 1
        startPlayback(queue[currentIndex])
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            startPlayback(queue[currentIndex])
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1)
        player?.seek(to: cmTime)
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        item.publisher(for: \.status)
            .sink { [weak self] status in
                print("🎵 Player item status: \(status.rawValue)")
                if status == .readyToPlay {
                    print("✅ Player ready to play, duration: \(item.duration.seconds)s")
                    self?.duration = item.duration.seconds
                } else if status == .failed {
                    print("❌ Player item failed!")
                    if let error = item.error {
                        print("❌ Error: \(error.localizedDescription)")
                        print("❌ Error domain: \((error as NSError).domain)")
                        print("❌ Error code: \((error as NSError).code)")
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .sink { [weak self] _ in
                self?.handlePlaybackEnded()
            }
            .store(in: &cancellables)
    }

    private func handlePlaybackEnded() {
        if currentIndex < queue.count - 1 {
            next()
        } else {
            isPlaying = false
            currentTime = 0
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.artist ?? "Unknown Artist"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = song.album ?? ""

        if let duration = song.duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(duration)
        }

        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let coverArtId = song.coverArt,
           let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: coverURL)
                    if let image = UIImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        await MainActor.run {
                            var updatedInfo = nowPlayingInfo
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                        }
                    }
                } catch {
                    print("Failed to load cover art: \(error)")
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
}
