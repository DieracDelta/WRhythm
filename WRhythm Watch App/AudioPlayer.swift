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
            player.volume = Float(volume)
        }
    }

    enum RepeatMode {
        case off
        case all
        case one
    }

    private let player: AVPlayer
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var originalQueue: [Song] = []
    private var originalIndex: Int = 0
    private var baseTimeOffset: TimeInterval = 0

    override init() {
        self.player = AVPlayer()
        super.init()

        setupAudioSession()
        setupRemoteCommands()
        addPeriodicTimeObserver()
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

    // Check if a format is natively supported by watchOS
    private func isFormatSupportedOnWatchOS(_ contentType: String?, _ suffix: String?) -> Bool {
        // watchOS natively supports: MP3, AAC, ALAC, WAV, AIFF
        // watchOS does NOT support: FLAC, Ogg Vorbis, Opus, WMA, etc.

        let supportedTypes = ["audio/mpeg", "audio/mp3", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/wav", "audio/x-wav", "audio/aiff", "audio/x-aiff"]
        let supportedSuffixes = ["mp3", "aac", "m4a", "mp4", "wav", "aiff", "aif"]

        if let contentType = contentType?.lowercased() {
            if supportedTypes.contains(where: { contentType.contains($0) }) {
                return true
            }
        }

        if let suffix = suffix?.lowercased() {
            if supportedSuffixes.contains(suffix) {
                return true
            }
        }

        return false
    }

    private func startPlayback(_ song: Song, startTime: TimeInterval = 0) {
        print("🎵 AudioPlayer: startPlayback called with startTime: \(startTime)")
        print("🎵 Song: \(song.title) by \(song.artist ?? "Unknown")")
        print("🎵 Song ID: \(song.id)")
        print("🎵 Content type: \(song.contentType ?? "unknown")")
        print("🎵 Suffix: \(song.suffix ?? "unknown")")

        self.currentSong = song
        self.currentTime = startTime

        // Store the offset we are requesting so we can add it to the player's reported time
        self.baseTimeOffset = startTime

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
            // Local file seeking is handled by AVPlayer seek, not URL offset
            self.baseTimeOffset = 0
        } else {
            // Check if we need transcoding for unsupported formats
            let needsTranscoding = !isFormatSupportedOnWatchOS(song.contentType, song.suffix)

            if needsTranscoding {
                // Request transcoding to MP3 for unsupported formats
                print("⚠️ Format '\(song.contentType ?? song.suffix ?? "unknown")' not natively supported - requesting MP3 transcode")
                if let streamURL = NavidromeAPI.shared.getStreamURL(id: song.id, format: "mp3", maxBitRate: 128, timeOffset: Int(startTime)) {
                    playURL = streamURL
                    print("🎵 Streaming transcoded: \(streamURL.absoluteString)")
                } else {
                    print("❌ Failed to get transcoded stream URL")
                    return
                }
            } else {
                // Native format - stream as-is WITHOUT format parameter
                print("✅ Format '\(song.contentType ?? song.suffix ?? "unknown")' natively supported")
                if let streamURL = NavidromeAPI.shared.getStreamURL(id: song.id, timeOffset: Int(startTime)) {
                    playURL = streamURL
                    print("🎵 Streaming from: \(streamURL.absoluteString)")
                } else {
                    print("❌ Failed to get stream URL")
                    return
                }
            }
        }

        print("🎵 Playback URL: \(playURL.absoluteString)")

        // Remove old time observer if exists
        // if let observer = timeObserver {
        //    player?.removeTimeObserver(observer)
        //    timeObserver = nil
        // }

        // Clear all old subscriptions to prevent duplicate notifications
        cancellables.removeAll()

        // Re-activate audio session before playback
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ Audio session re-activated for playback")
        } catch {
            print("⚠️ Failed to re-activate audio session: \(error)")
        }

        // Follow Submariner's approach: Always use AVURLAsset with options
        // This works reliably on both macOS and watchOS
        print("🎵 Creating player item from asset...")

        var assetOptions: [String: Any] = [:]
        if let contentType = song.contentType {
            // Fix FLAC MIME type (Submariner workaround)
            let fixedContentType = contentType == "audio/x-flac" ? "audio/flac" : contentType
            print("🎵 Setting MIME type: \(fixedContentType)")
            assetOptions["AVURLAssetOutOfBandMIMETypeKey"] = fixedContentType

            // Seeking is inaccurate with FLACs otherwise (Submariner approach)
            if fixedContentType.contains("flac") {
                assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = true
            }
        }

        let asset = AVURLAsset(url: playURL, options: assetOptions)
        let playerItem = AVPlayerItem(asset: asset)

        // Configure player item for better streaming
        // Let AVPlayer decide buffer size (default is usually aggressive buffering, which is better for stability)
        // playerItem.preferredForwardBufferDuration = 5.0

        // Reuse existing player instance
        player.replaceCurrentItem(with: playerItem)
        player.volume = Float(volume)

        observePlayerItem(playerItem)

        // If resuming a local file, we need to seek.
        // For streams, the timeOffset in URL handles it (so we start at 0 relative to the chunk).
        if startTime > 0 && playURL.isFileURL {
             let cmTime = CMTime(seconds: startTime, preferredTimescale: 1)
             player.seek(to: cmTime)
        }

        player.play()
        isPlaying = true

        updateNowPlayingInfo()
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
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
        // If we are playing a local file, standard seek works
        if let currentSong = currentSong, 
           DownloadManager.shared.getLocalURL(currentSong.id) != nil {
             let cmTime = CMTime(seconds: time, preferredTimescale: 1)
             player.seek(to: cmTime)
             return
        }
        
        // If streaming, we likely have a chunked stream which cannot be seeked backward 
        // or far forward easily. We should re-request the stream at the new offset.
        if let currentSong = currentSong {
            print("⏩ Seeking stream to \(time)s (reloading stream)")
            startPlayback(currentSong, startTime: time)
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // Calculate absolute time by adding the base offset (if we resumed stream)
            // For normal playback, baseTimeOffset is 0.
            // For resumed stream, player time is relative to chunk, so we add offset.
            self.currentTime = self.baseTimeOffset + time.seconds

            // Update duration if it's available and we don't have it yet
            if let item = self.player.currentItem {
                let itemDuration = item.duration

                // Only update global duration if we started from 0, otherwise the chunk duration is partial
                if self.baseTimeOffset == 0,
                   (self.duration == 0 || self.duration.isNaN),
                   itemDuration.isNumeric && itemDuration.seconds > 0 {
                    self.duration = itemDuration.seconds
                    print("✅ Duration updated from time observer to: \(self.duration)s")
                }
                
                // Manual check for end of playback if duration is available but player thinks it's indefinite
                // (Common issue with some streams where AVPlayer treats them as live radio)
                if itemDuration.isIndefinite,
                   self.duration > 0,
                   self.currentTime >= (self.duration + 5) {
                    print("🛑 Forced end of playback because duration reached (\(self.currentTime) >= \(self.duration) + 5s buffer)")
                    self.handlePlaybackEnded()
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        // Simple status observer (Submariner approach)
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
        print("🛑 handlePlaybackEnded called. CurrentTime: \(currentTime), Duration: \(duration)")
        print("🛑 RepeatMode: \(repeatMode), Queue Count: \(queue.count), CurrentIndex: \(currentIndex)")

        // Protect against premature ending (e.g. network drop masquerading as end of file)
        // If we are less than 95% through and song is longer than 10s, it's likely an error
        if duration > 10, currentTime > 0, currentTime < (duration * 0.95) {
             print("⚠️ Premature end detected (Time: \(currentTime)/\(duration)). Attempting to resume playback from \(currentTime)...")
             if let song = currentSong {
                 // Restart playback but ask server for offset
                 startPlayback(song, startTime: currentTime)
             }
             return
        }

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
                player.pause()
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
            player.removeTimeObserver(observer)
        }
    }
}
