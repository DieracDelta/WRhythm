//
//  AudioPlayer.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer

class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    @Published var currentSong: Song? {
        didSet {
            print("🎵 AudioPlayer.currentSong changed to: \(currentSong?.title ?? "nil")")
        }
    }
    @Published var isPlaying = false {
        didSet {
            print("▶️ AudioPlayer.isPlaying changed to: \(isPlaying)")
        }
    }
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var queue: [Song] = []
    @Published var currentIndex: Int = 0
    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 1.0 {
        didSet {
            player?.volume = Float(volume)
        }
    }

    enum RepeatMode {
        case off
        case all
        case one
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var originalQueue: [Song] = []
    private var originalIndex: Int = 0

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("✅ Audio session configured for background playback")
        } catch {
            print("❌ Failed to set up audio session: \(error)")
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

        self.isShuffled = false
        self.originalQueue = []
        self.queue = songs
        self.currentIndex = index
        startPlayback(songs[index])
    }

    func playQueueShuffled(_ songs: [Song]) {
        guard !songs.isEmpty else {
            print("⚠️ playQueueShuffled called with empty array")
            return
        }

        print("🔀 playQueueShuffled called with \(songs.count) songs")
        self.isShuffled = true
        self.originalQueue = songs
        self.originalIndex = 0

        // Shuffle the queue
        var shuffled = songs
        shuffled.shuffle()

        self.queue = shuffled
        self.currentIndex = 0
        print("🔀 Queue set to \(self.queue.count) songs, currentIndex=\(self.currentIndex)")
        startPlayback(shuffled[0])
    }

    func toggleRepeat() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        print("🔁 Repeat mode changed to: \(repeatMode)")
    }

    func toggleShuffle() {
        if isShuffled {
            // Turn off shuffle - restore original queue
            guard let currentSong = currentSong,
                  let originalIdx = originalQueue.firstIndex(where: { $0.id == currentSong.id }) else {
                return
            }
            self.queue = originalQueue
            self.currentIndex = originalIdx
            self.isShuffled = false
            self.originalQueue = []
        } else {
            // Turn on shuffle - save current queue and shuffle
            guard let currentSong = currentSong else { return }

            self.originalQueue = queue
            self.originalIndex = currentIndex
            self.isShuffled = true

            var shuffled = queue
            shuffled.shuffle()

            // Find current song in shuffled queue
            if let newIdx = shuffled.firstIndex(where: { $0.id == currentSong.id }) {
                self.currentIndex = newIdx
            } else {
                self.currentIndex = 0
            }
            self.queue = shuffled
        }
    }

    private func startPlayback(_ song: Song) {
        print("🎵 AudioPlayer: startPlayback called")
        print("🎵 Song: \(song.title) by \(song.artist ?? "Unknown")")
        print("🎵 Song ID: \(song.id)")
        print("🎵 Content type: \(song.contentType ?? "unknown")")
        print("🎵 Suffix: \(song.suffix ?? "unknown")")

        self.currentSong = song
        self.currentTime = 0

        // Use song metadata duration if available, otherwise will try to get from stream
        if let songDuration = song.duration, songDuration > 0 {
            self.duration = TimeInterval(songDuration)
            print("🔄 Set duration from song metadata: \(songDuration)s")
        } else {
            self.duration = 0
            print("🔄 Reset duration to 0, will try to get from stream")
        }

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

        // Remove old time observer if exists
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Clear all old subscriptions to prevent duplicate notifications
        cancellables.removeAll()

        // Re-activate audio session before playback
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ Audio session re-activated for playback")
        } catch {
            print("⚠️ Failed to re-activate audio session: \(error)")
        }

        // Use AVURLAsset for better control over loading (especially important on watchOS)
        // Set MIME type explicitly to prevent AVPlayer from treating stream as ICY/HLS
        var assetOptions: [String: Any] = [:]

        if let contentType = song.contentType {
            print("🎵 Setting MIME type: \(contentType)")
            assetOptions["AVURLAssetOutOfBandMIMETypeKey"] = contentType
        }

        // Prefer precise duration for better seeking (especially for FLAC)
        assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = true

        let asset = AVURLAsset(url: playURL, options: assetOptions)

        print("🎵 Creating player item from asset...")
        let playerItem = AVPlayerItem(asset: asset)

        // Configure player item for better streaming
        playerItem.preferredForwardBufferDuration = 5.0

        player = AVPlayer(playerItem: playerItem)
        player?.volume = Float(volume)  // Apply current volume

        // Set automatic waiting to minimize stalls
        player?.automaticallyWaitsToMinimizeStalling = true

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

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        currentSong = nil
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        print("⏹️ Playback stopped and queue cleared")
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
            guard let self = self else { return }
            self.currentTime = time.seconds

            // Update duration if it's available and we don't have it yet
            if let item = self.player?.currentItem {
                let itemDuration = item.duration

                if (self.duration == 0 || self.duration.isNaN),
                   itemDuration.isNumeric && itemDuration.seconds > 0 {
                    self.duration = itemDuration.seconds
                    print("✅ Duration updated from time observer to: \(self.duration)s")
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        item.publisher(for: \.status)
            .sink { [weak self] status in
                print("🎵 Player item status changed: \(status.rawValue) (0=unknown, 1=ready, 2=failed)")
                if status == .readyToPlay {
                    let dur = item.duration
                    print("✅ Player ready to play")
                    print("📊 Duration details - seconds: \(dur.seconds), isNumeric: \(dur.isNumeric), isIndefinite: \(dur.isIndefinite), isValid: \(dur.isValid)")

                    // Always prefer actual stream duration over metadata (metadata can be wrong)
                    if dur.isNumeric && dur.seconds > 0 {
                        self?.duration = dur.seconds
                        print("✅ Duration set from stream: \(dur.seconds)s")
                    } else {
                        print("⚠️ Stream duration not available (isIndefinite: \(dur.isIndefinite))")
                        if let currentDuration = self?.duration, currentDuration > 0 {
                            print("ℹ️ Using song metadata duration: \(currentDuration)s")
                        }
                    }
                } else if status == .failed {
                    print("❌ Player item failed!")
                    if let error = item.error {
                        print("❌ Error: \(error.localizedDescription)")
                        let nsError = error as NSError
                        print("❌ Error domain: \(nsError.domain)")
                        print("❌ Error code: \(nsError.code)")
                        print("❌ Error userInfo: \(nsError.userInfo)")

                        // Provide specific guidance for common errors
                        if nsError.code == -11850 {
                            print("💡 Error -11850 (AVErrorOperationStopped): Stream was stopped")
                            print("💡 Possible causes: Network issue, invalid URL, unsupported format, or ATS restriction")
                        }

                        // Try to get more details from the access log
                        if let accessLog = item.accessLog() {
                            print("📊 Access log events: \(accessLog.events.count)")
                            for event in accessLog.events {
                                print("📊 URI: \(event.uri ?? "nil")")
                                print("📊 Server address: \(event.serverAddress ?? "nil")")
                                print("📊 Number of server address changes: \(event.numberOfServerAddressChanges)")
                                if let errorLog = item.errorLog() {
                                    print("❌ Error log events: \(errorLog.events.count)")
                                    for errorEvent in errorLog.events {
                                        print("❌ Error status code: \(errorEvent.errorStatusCode)")
                                        print("❌ Error domain: \(errorEvent.errorDomain ?? "nil")")
                                        print("❌ Error comment: \(errorEvent.errorComment ?? "nil")")
                                    }
                                }
                            }
                        }
                    } else {
                        print("❌ Player failed but no error object available")
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
        switch repeatMode {
        case .one:
            // Repeat current song
            seek(to: 0)
            play()
        case .all:
            // Move to next song, or loop back to beginning
            if currentIndex < queue.count - 1 {
                next()
            } else {
                // Loop back to first song
                currentIndex = 0
                if let firstSong = queue.first {
                    currentSong = firstSong
                    startPlayback(firstSong)
                }
            }
        case .off:
            // Normal behavior - advance or stop
            if currentIndex < queue.count - 1 {
                next()
            } else {
                // Stop playback completely
                player?.pause()
                isPlaying = false
                currentTime = 0
                print("⏸️ Queue finished - stopped playback")
            }
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
