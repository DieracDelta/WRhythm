//
//  AudioPlayer.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import AVFoundation
import Combine

#if os(macOS)
import ApplicationServices
import CoreGraphics
#endif

#if os(iOS) || os(watchOS)
import MediaPlayer
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
    @Published var playlistGenQueue: [Song] = []
    @Published var playlistGenSourceTitle: String?
    @Published var playlistGenSourceArtist: String?
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
#if os(macOS)
    private var mediaKeyMonitors: [Any] = []
    private var mediaKeyEventTap: CFMachPort?
    private var mediaKeyRunLoopSource: CFRunLoopSource?
#endif

    override init() {
        self.player = AVPlayer()
        super.init()

        setupRemoteCommands()
        addPeriodicTimeObserver()
    }

    private func prepareAudioSessionForPlayback() {
#if os(iOS) || os(watchOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("✅ Audio session configured for playback")
        } catch {
            print("❌ Failed to set up audio session: \(error)")
        }
#endif
    }

    private func setupRemoteCommands() {
#if os(iOS) || os(watchOS)
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
#elseif os(macOS)
        setupMacMediaKeyCommands()
#endif
    }

#if os(macOS)
    private func setupMacMediaKeyCommands() {
        if setupMacMediaKeyEventTap() {
            return
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard self?.handleMacMediaKeyEvent(event) == true else {
                return event
            }
            return nil
        }

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            _ = self?.handleMacMediaKeyEvent(event)
        }

        mediaKeyMonitors = [localMonitor, globalMonitor].compactMap { $0 }
    }

    private func setupMacMediaKeyEventTap() -> Bool {
        let accessibilityOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(accessibilityOptions) else {
            print("⚠️ WRhythm needs macOS Accessibility permission to fully claim media keys before Apple Music.")
            return false
        }

        let systemDefinedRawValue = UInt64(Self.systemDefinedEventType.rawValue)
        let eventMask = CGEventMask(1 << systemDefinedRawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: AudioPlayer.macMediaKeyEventTapCallback,
            userInfo: userInfo
        ) else {
            print("⚠️ Could not install macOS media key event tap; media keys may still reach the system music app.")
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            print("⚠️ Could not create macOS media key run loop source.")
            return false
        }

        mediaKeyEventTap = eventTap
        mediaKeyRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private static let systemDefinedEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue))!

    private static let macMediaKeyEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let player = Unmanaged<AudioPlayer>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let mediaKeyEventTap = player.mediaKeyEventTap {
                CGEvent.tapEnable(tap: mediaKeyEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              player.handleMacMediaKeyEvent(nsEvent) else {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }

    private func handleMacMediaKeyEvent(_ event: NSEvent) -> Bool {
        guard event.subtype.rawValue == 8 else { return false }

        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyState = Int((event.data1 & 0x0000FF00) >> 8)
        let isKeyDown = (keyState & 0xFF) == 0xA
        guard isKeyDown else { return false }

        switch keyCode {
        case 16:
            DispatchQueue.main.async { [weak self] in
                self?.togglePlayPause()
            }
        case 17:
            DispatchQueue.main.async { [weak self] in
                self?.next()
            }
        case 18:
            DispatchQueue.main.async { [weak self] in
                self?.previous()
            }
        default:
            return false
        }

        return true
    }
#endif

    func playSong(_ song: Song) {
        clearPlaylistGen()
        if DeviceSyncManager.shared.routePlaybackRequestToConnectedDevice([song], startingAt: 0) {
            return
        }
        self.queue = [song]
        self.currentIndex = 0
        startPlayback(song)
        DeviceSyncManager.shared.broadcastLocalQueueAsShared()
    }

    func playQueue(_ songs: [Song], startingAt index: Int = 0, clearGeneratedPlaylist: Bool = true) {
        guard !songs.isEmpty, index < songs.count else { return }
        if clearGeneratedPlaylist {
            clearPlaylistGen()
        }
        if DeviceSyncManager.shared.routePlaybackRequestToConnectedDevice(songs, startingAt: index) {
            return
        }

        self.isShuffled = false
        self.originalQueue = []
        self.queue = songs
        self.currentIndex = index
        startPlayback(songs[index])
        DeviceSyncManager.shared.broadcastLocalQueueAsShared()
    }

    func playGeneratedPlaylist(sourceSong: Song, songs: [Song], startingAt index: Int = 0) {
        guard !songs.isEmpty else { return }
        playlistGenSourceTitle = sourceSong.title
        playlistGenSourceArtist = sourceSong.artist
        playlistGenQueue = songs
        playQueue(songs, startingAt: index, clearGeneratedPlaylist: false)
    }

    func clearPlaylistGen() {
        playlistGenQueue = []
        playlistGenSourceTitle = nil
        playlistGenSourceArtist = nil
    }

    func playQueueShuffled(_ songs: [Song]) {
        guard !songs.isEmpty else {
            print("⚠️ playQueueShuffled called with empty array")
            return
        }

        clearPlaylistGen()
        print("🔀 playQueueShuffled called with \(songs.count) songs")
        if DeviceSyncManager.shared.routePlaybackRequestToConnectedDevice(songs, startingAt: 0, shuffled: true) {
            return
        }

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
        DeviceSyncManager.shared.broadcastLocalQueueAsShared()
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

    func enqueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        if DeviceSyncManager.shared.routeEnqueueRequestToConnectedDevice(songs) {
            return
        }

        queue.append(contentsOf: songs)
        if currentSong == nil, let firstSong = queue.first {
            currentIndex = 0
            startPlayback(firstSong)
        }
        DeviceSyncManager.shared.broadcastLocalQueueAsShared()
    }

    func mirrorQueueWithoutPlayback(_ songs: [Song], currentIndex index: Int, currentTime: TimeInterval = 0) {
        guard !songs.isEmpty else { return }
        let safeIndex = min(max(index, 0), songs.count - 1)
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = songs
        currentIndex = safeIndex
        currentSong = songs[safeIndex]
        self.currentTime = currentTime
        duration = TimeInterval(songs[safeIndex].duration ?? 0)
        isPlaying = false
    }

    private func isFormatSupportedNatively(_ contentType: String?, _ suffix: String?) -> Bool {
#if os(watchOS)
        let supportedTypes = ["audio/mpeg", "audio/mp3", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/wav", "audio/x-wav", "audio/aiff", "audio/x-aiff"]
        let supportedSuffixes = ["mp3", "aac", "m4a", "mp4", "wav", "aiff", "aif"]
#else
        let supportedTypes = ["audio/mpeg", "audio/mp3", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/wav", "audio/x-wav", "audio/aiff", "audio/x-aiff", "audio/flac", "audio/x-flac", "audio/alac", "audio/x-alac"]
        let supportedSuffixes = ["mp3", "aac", "m4a", "mp4", "wav", "aiff", "aif", "flac", "alac"]
#endif

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
            let streamingQuality = StreamingQuality.current
            let isNativelySupported = isFormatSupportedNatively(song.contentType, song.suffix)
            let shouldTranscode = streamingQuality != .original || !isNativelySupported

            if shouldTranscode {
                let bitRate = streamingQuality.maxBitRate ?? StreamingQuality.max.rawValue
                let reason = isNativelySupported ? streamingQuality.description : "Unsupported format"
                print("⚠️ \(reason) - requesting MP3 transcode at \(bitRate) kbps")
                if let streamURL = NavidromeAPI.shared.getStreamURL(id: song.id, format: "mp3", maxBitRate: bitRate, timeOffset: Int(startTime)) {
                    playURL = streamURL
                    print("🎵 Streaming transcoded: \(streamURL.absoluteString)")
                } else {
                    print("❌ Failed to get transcoded stream URL")
                    return
                }
            } else {
                print("✅ Streaming original format '\(song.contentType ?? song.suffix ?? "unknown")'")
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

        prepareAudioSessionForPlayback()

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
        prepareAudioSessionForPlayback()
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
        clearPlaylistGen()
        print("⏹️ Playback stopped and queue cleared")
    }

    func togglePlayPause() {
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.sendPlayPause()
            return
        }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func next() {
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.sendNext()
            return
        }
        guard currentIndex < queue.count - 1 else { return }
        currentIndex += 1
        startPlayback(queue[currentIndex])
    }

    func previous() {
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.sendPrevious()
            return
        }
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
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.sendSeek(to: time)
            return
        }
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
                                        print("❌ Error domain: \(errorEvent.errorDomain)")
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
#if os(iOS) || os(watchOS)
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
                    if let image = PlatformImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        await MainActor.run {
                            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
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
#endif
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }
}
