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

#if os(iOS) || os(watchOS) || os(macOS)
import MediaPlayer
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
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
    @Published var isBuffering = false
    @Published private(set) var prebufferedTrackCount = 0
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

    enum RepeatMode: String, Codable {
        case off
        case all
        case one
    }

    private struct PersistedPlaybackState: Codable {
        let version: Int
        let queue: [Song]
        let currentIndex: Int
        let currentTime: TimeInterval
        let duration: TimeInterval
        let wasPlaying: Bool
        let volume: Double
        let isShuffled: Bool
        let repeatMode: RepeatMode
        let originalQueue: [Song]
        let originalIndex: Int
        let playlistGenQueue: [Song]
        let playlistGenSourceTitle: String?
        let playlistGenSourceArtist: String?
        let queueFinished: Bool
        let updatedAt: Date
    }

    private struct PreparedPrebuffer: @unchecked Sendable {
        let url: URL
        let asset: AVURLAsset
    }

    private enum PrebufferPreparationError: Error {
        case notPlayable
    }

    private static let persistedPlaybackStateKey = "audioPlayerPersistedPlaybackState.v1"
    private static let persistedPlaybackVersion = 1

    private let player: AVPlayer
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var playerItemCancellables = Set<AnyCancellable>()
    private var originalQueue: [Song] = []
    private var originalIndex: Int = 0
    private var baseTimeOffset: TimeInterval = 0
    private var queueFinished = false
    private var isRestoringPlaybackState = false
    private var lastPersistenceWrite = Date.distantPast
    private var pendingPersistenceTask: Task<Void, Never>?
    private let prebufferAheadCount = 8
    private let maxConcurrentPrebuffers = 3
    private var prebufferTasks: [String: Task<Void, Never>] = [:]
    private var prebufferURLs: [String: URL] = [:]
    private var preparedPrebuffers: [String: PreparedPrebuffer] = [:]
    private var currentPlaybackURL: URL?
    private var currentPlaybackIsLocalFile = false
    private var playbackRetryTask: Task<Void, Never>?
    private var playbackRetryAttemptsBySongID: [String: Int] = [:]
    private let maxPlaybackRetryAttempts = 4
    private let maxPlaybackRetryBackoff: TimeInterval = 30
#if os(macOS)
    private var mediaKeyMonitors: [Any] = []
    private var mediaKeyEventTap: CFMachPort?
    private var mediaKeyRunLoopSource: CFRunLoopSource?
    private var lastMacMediaKeyActionDate = Date.distantPast
    private let macMediaKeyDuplicateWindow: TimeInterval = 0.45

    private enum MacMediaKeyAction {
        case play
        case pause
        case toggle
        case next
        case previous
    }
#endif

    override init() {
        self.player = AVPlayer()
        super.init()

        setupRemoteCommands()
        addPeriodicTimeObserver()
        observePlayerBuffering()
        restorePersistedPlaybackState()
        setupPlaybackPersistence()
    }

    var liveCurrentTime: TimeInterval {
        let playerSeconds = player.currentTime().seconds
        guard playerSeconds.isFinite else {
            return currentTime
        }

        let absoluteTime = max(0, baseTimeOffset + playerSeconds)
        guard duration.isFinite, duration > 0 else {
            return absoluteTime
        }
        return min(absoluteTime, duration)
    }

    func persistPlaybackStateNow() {
        persistPlaybackState()
    }

    private func setupPlaybackPersistence() {
        Publishers.CombineLatest4($currentSong, $isPlaying, $queue, $currentIndex)
            .dropFirst()
            .sink { [weak self] _, _, _, _ in
                self?.schedulePlaybackPersistence()
                self?.scheduleQueuePrebuffer()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4($volume, $isShuffled, $repeatMode, $playlistGenQueue)
            .dropFirst()
            .sink { [weak self] _, _, _, _ in
                self?.schedulePlaybackPersistence()
            }
            .store(in: &cancellables)

        $currentTime
            .removeDuplicates { abs($0 - $1) < 5 }
            .dropFirst()
            .sink { [weak self] _ in
                self?.schedulePlaybackPersistence()
            }
            .store(in: &cancellables)
    }

    private func observePlayerBuffering() {
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                guard let self else { return }
                self.isBuffering = self.isPlaying && (status == .waitingToPlayAtSpecifiedRate || self.player.currentItem?.isPlaybackBufferEmpty == true)
            }
            .store(in: &cancellables)
    }

    private func schedulePlaybackPersistence() {
        guard !isRestoringPlaybackState else { return }
        let elapsed = Date().timeIntervalSince(lastPersistenceWrite)
        if elapsed >= 5 {
            persistPlaybackState()
            return
        }

        pendingPersistenceTask?.cancel()
        let delay = max(0.5, 5 - elapsed)
        pendingPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.persistPlaybackState()
        }
    }

    private func persistPlaybackState() {
        guard !isRestoringPlaybackState else { return }
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil
        lastPersistenceWrite = Date()

        let songs = queue.isEmpty ? currentSong.map { [$0] } ?? [] : queue
        guard !songs.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.persistedPlaybackStateKey)
            return
        }

        let safeIndex = min(max(currentIndex, 0), songs.count - 1)
        let position = max(0, liveCurrentTime.isFinite ? liveCurrentTime : currentTime)
        let state = PersistedPlaybackState(
            version: Self.persistedPlaybackVersion,
            queue: songs,
            currentIndex: safeIndex,
            currentTime: position,
            duration: duration.isFinite ? duration : 0,
            wasPlaying: isPlaying,
            volume: min(max(volume.isFinite ? volume : 1, 0), 1),
            isShuffled: isShuffled,
            repeatMode: repeatMode,
            originalQueue: originalQueue,
            originalIndex: originalIndex,
            playlistGenQueue: playlistGenQueue,
            playlistGenSourceTitle: playlistGenSourceTitle,
            playlistGenSourceArtist: playlistGenSourceArtist,
            queueFinished: queueFinished,
            updatedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: Self.persistedPlaybackStateKey)
        } catch {
            print("⚠️ Failed to persist playback state: \(error)")
        }
    }

    private func restorePersistedPlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedPlaybackStateKey) else { return }

        do {
            let state = try JSONDecoder().decode(PersistedPlaybackState.self, from: data)
            guard state.version == Self.persistedPlaybackVersion,
                  !state.queue.isEmpty else {
                UserDefaults.standard.removeObject(forKey: Self.persistedPlaybackStateKey)
                return
            }

            isRestoringPlaybackState = true
            defer { isRestoringPlaybackState = false }

            let safeIndex = min(max(state.currentIndex, 0), state.queue.count - 1)
            let song = state.queue[safeIndex]
            let songDuration = TimeInterval(song.duration ?? 0)
            let restoredDuration = state.duration > 0 ? state.duration : songDuration
            let restoredTime = min(max(state.currentTime, 0), restoredDuration > 0 ? restoredDuration : state.currentTime)

            queue = state.queue
            currentIndex = safeIndex
            currentSong = song
            currentTime = restoredTime
            duration = restoredDuration
            volume = min(max(state.volume.isFinite ? state.volume : 1, 0), 1)
            isShuffled = state.isShuffled
            repeatMode = state.repeatMode
            originalQueue = state.originalQueue
            originalIndex = state.originalIndex
            playlistGenQueue = state.playlistGenQueue
            playlistGenSourceTitle = state.playlistGenSourceTitle
            playlistGenSourceArtist = state.playlistGenSourceArtist
            queueFinished = state.queueFinished

            if state.wasPlaying, !state.queueFinished {
                startPlayback(song, startTime: restoredTime)
            } else {
                isPlaying = false
                updateNowPlayingInfo()
                scheduleQueuePrebuffer()
            }

            print("✅ Restored playback state: \(song.title) at \(Int(restoredTime))s")
        } catch {
            print("⚠️ Failed to restore playback state: \(error)")
            UserDefaults.standard.removeObject(forKey: Self.persistedPlaybackStateKey)
        }
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
#if os(iOS) || os(watchOS) || os(macOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { _ in
#if os(macOS)
            Task { @MainActor in
                AudioPlayer.shared.performMacMediaKeyAction(.play)
            }
#else
            Task { @MainActor in
                AudioPlayer.shared.play()
            }
#endif
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
#if os(macOS)
            Task { @MainActor in
                AudioPlayer.shared.performMacMediaKeyAction(.pause)
            }
#else
            Task { @MainActor in
                AudioPlayer.shared.pause()
            }
#endif
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { _ in
#if os(macOS)
            Task { @MainActor in
                AudioPlayer.shared.performMacMediaKeyAction(.toggle)
            }
#else
            Task { @MainActor in
                AudioPlayer.shared.togglePlayPause()
            }
#endif
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { _ in
#if os(macOS)
            Task { @MainActor in
                AudioPlayer.shared.performMacMediaKeyAction(.next)
            }
#else
            Task { @MainActor in
                AudioPlayer.shared.next()
            }
#endif
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { _ in
#if os(macOS)
            Task { @MainActor in
                AudioPlayer.shared.performMacMediaKeyAction(.previous)
            }
#else
            Task { @MainActor in
                AudioPlayer.shared.previous()
            }
#endif
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                AudioPlayer.shared.seek(to: event.positionTime)
            }
            return .success
        }
#if os(macOS)
        setupMacMediaKeyCommands()
#endif
#endif
    }

#if os(macOS)
    @MainActor
    private func performMacMediaKeyAction(_ action: MacMediaKeyAction) {
        let now = Date()
        guard now.timeIntervalSince(lastMacMediaKeyActionDate) >= macMediaKeyDuplicateWindow else {
            print("⏭️ Ignored duplicate macOS media key event")
            return
        }

        lastMacMediaKeyActionDate = now

        switch action {
        case .play:
            PlaybackKeyboardActions.setPlaying(true)
        case .pause:
            PlaybackKeyboardActions.setPlaying(false)
        case .toggle:
            PlaybackKeyboardActions.togglePlayback()
        case .next:
            PlaybackKeyboardActions.nextTrack()
        case .previous:
            PlaybackKeyboardActions.previousTrack()
        }
    }

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
            "AXTrustedCheckOptionPrompt": true
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
            Task { @MainActor in
                self.performMacMediaKeyAction(.toggle)
            }
        case 17:
            Task { @MainActor in
                self.performMacMediaKeyAction(.next)
            }
        case 18:
            Task { @MainActor in
                self.performMacMediaKeyAction(.previous)
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

        let appendedStartIndex = queue.count
        let shouldStartAppendedSongs = queueFinished || currentSong == nil
        queue.append(contentsOf: songs)
        if shouldStartAppendedSongs, queue.indices.contains(appendedStartIndex) {
            currentIndex = appendedStartIndex
            startPlayback(queue[appendedStartIndex])
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
        queueFinished = false
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

    private var prebufferDirectory: URL {
#if os(macOS)
        let baseURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WRhythm", isDirectory: true)
#else
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
#endif
        let directory = baseURL.appendingPathComponent("PlaybackPrebuffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func shouldTranscodeForPlayback(_ song: Song) -> Bool {
        let streamingQuality = StreamingQuality.current
        return streamingQuality != .original || !isFormatSupportedNatively(song.contentType, song.suffix)
    }

    private func streamURLForPlayback(_ song: Song) -> URL? {
        if shouldTranscodeForPlayback(song) {
            let bitRate = StreamingQuality.current.maxBitRate ?? StreamingQuality.max.rawValue
            return NavidromeAPI.shared.getStreamURL(id: song.id, format: "mp3", maxBitRate: bitRate)
        }

        return NavidromeAPI.shared.getStreamURL(id: song.id)
    }

    private func prebufferKey(for song: Song) -> String {
        "\(song.id)|q\(StreamingQuality.current.rawValue)"
    }

    private func sanitizedPrebufferFilename(for song: Song) -> String {
        let key = prebufferKey(for: song)
        let safeKey = key.map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let extensionName = shouldTranscodeForPlayback(song) ? "mp3" : (song.suffix?.isEmpty == false ? song.suffix! : "audio")
        return "\(String(safeKey)).\(extensionName)"
    }

    private func prebufferURL(for song: Song) -> URL {
        prebufferDirectory.appendingPathComponent(sanitizedPrebufferFilename(for: song))
    }

    private func existingPrebufferURL(for song: Song) -> URL? {
        let key = prebufferKey(for: song)
        if let cachedURL = prebufferURLs[key],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        let url = prebufferURL(for: song)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        prebufferURLs[key] = url
        return url
    }

    private func preparedPrebuffer(for song: Song) -> PreparedPrebuffer? {
        let key = prebufferKey(for: song)
        guard let prebuffer = preparedPrebuffers[key],
              FileManager.default.fileExists(atPath: prebuffer.url.path) else {
            preparedPrebuffers.removeValue(forKey: key)
            return nil
        }
        return prebuffer
    }

    private func isPrebuffered(_ song: Song) -> Bool {
        preparedPrebuffer(for: song) != nil
    }

    private nonisolated static func playbackMimeType(contentType: String?, url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "flac":
            return "audio/flac"
        case "wav":
            return "audio/wav"
        case "aiff", "aif":
            return "audio/aiff"
        default:
            return contentType
        }
    }

    private func playbackMimeType(for song: Song, url: URL) -> String? {
        Self.playbackMimeType(contentType: song.contentType, url: url)
    }

    private nonisolated static func playbackAssetOptions(contentType: String?, url: URL) -> [String: Any] {
        var assetOptions: [String: Any] = [:]
        if let contentType = playbackMimeType(contentType: contentType, url: url) {
            let fixedContentType = contentType == "audio/x-flac" ? "audio/flac" : contentType
            assetOptions["AVURLAssetOutOfBandMIMETypeKey"] = fixedContentType

            if fixedContentType.contains("flac") {
                assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = true
            }
        }
        return assetOptions
    }

    private func playbackAssetOptions(for song: Song, url: URL) -> [String: Any] {
        Self.playbackAssetOptions(contentType: song.contentType, url: url)
    }

    private func makePlaybackAsset(for song: Song, url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: playbackAssetOptions(for: song, url: url))
    }

    private nonisolated static func preparePrebufferAsset(for song: Song, url: URL) async throws -> PreparedPrebuffer {
        let asset = AVURLAsset(url: url, options: playbackAssetOptions(contentType: song.contentType, url: url))
        let isPlayable = try await asset.load(.isPlayable)
        _ = try? await asset.load(.duration)
        guard isPlayable else { throw PrebufferPreparationError.notPlayable }
        return PreparedPrebuffer(url: url, asset: asset)
    }

    private func scheduleQueuePrebuffer() {
        guard !queue.isEmpty else {
            prebufferTasks.values.forEach { $0.cancel() }
            prebufferTasks.removeAll()
            preparedPrebuffers.removeAll()
            updatePrebufferedTrackCount()
            return
        }

        let start = currentIndex + 1
        guard start < queue.count else {
            prebufferTasks.values.forEach { $0.cancel() }
            prebufferTasks.removeAll()
            preparedPrebuffers.removeAll()
            updatePrebufferedTrackCount()
            return
        }

        let end = min(queue.count, start + prebufferAheadCount)
        let upcomingSongs = Array(queue[start..<end])
        let desiredKeys = Set(upcomingSongs.map(prebufferKey))
        let currentSongKey = currentSong.map(prebufferKey)

        let staleKeys = prebufferTasks.keys.filter { !desiredKeys.contains($0) }
        for key in staleKeys {
            prebufferTasks[key]?.cancel()
            prebufferTasks.removeValue(forKey: key)
        }

        for key in Array(preparedPrebuffers.keys) where !desiredKeys.contains(key) {
            preparedPrebuffers.removeValue(forKey: key)
        }

        prunePrebufferCache(keeping: desiredKeys.union(currentSongKey.map { [$0] } ?? []))
        updatePrebufferedTrackCount()

        for song in upcomingSongs {
            guard prebufferTasks.count < maxConcurrentPrebuffers else { break }
            let key = prebufferKey(for: song)
            guard prebufferTasks[key] == nil,
                  preparedPrebuffer(for: song) == nil else { continue }
            if let downloadedURL = DownloadManager.shared.getLocalURL(song.id) {
                preparePrebufferedFile(song, key: key, url: downloadedURL)
                continue
            }
            if let existingURL = existingPrebufferURL(for: song) {
                preparePrebufferedFile(song, key: key, url: existingURL)
                continue
            }
            startPrebuffering(song, key: key)
        }
    }

    private func startPrebuffering(_ song: Song, key: String) {
        guard let url = streamURLForPlayback(song) else { return }
        let destinationURL = prebufferURL(for: song)

        prebufferTasks[key] = Task { [weak self] in
            do {
                let (temporaryURL, _) = try await URLSession.shared.download(from: url)
                try Task.checkCancellation()

                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

                await self?.prepareDownloadedPrebuffer(song, key: key, url: destinationURL)
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let player = self else { return }
                    player.prebufferTasks.removeValue(forKey: key)
                    player.updatePrebufferedTrackCount()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let player = self else { return }
                    player.prebufferTasks.removeValue(forKey: key)
                    player.updatePrebufferedTrackCount()
                    print("⚠️ Failed to prebuffer \(song.title): \(error)")
                }
            }
        }
    }

    private func preparePrebufferedFile(_ song: Song, key: String, url: URL) {
        prebufferTasks[key] = Task { [weak self] in
            await self?.prepareDownloadedPrebuffer(song, key: key, url: url)
        }
    }

    private func prepareDownloadedPrebuffer(_ song: Song, key: String, url: URL) async {
        do {
            let prebuffer = try await Self.preparePrebufferAsset(for: song, url: url)
            try Task.checkCancellation()

            await MainActor.run { [weak self] in
                guard let player = self else { return }
                player.prebufferURLs[key] = prebuffer.url
                player.preparedPrebuffers[key] = prebuffer
                player.prebufferTasks.removeValue(forKey: key)
                player.updatePrebufferedTrackCount()
                print("✅ Prebuffered and prepared next queue item: \(song.title)")
                player.scheduleQueuePrebuffer()
            }
        } catch is CancellationError {
            await MainActor.run { [weak self] in
                guard let player = self else { return }
                player.prebufferTasks.removeValue(forKey: key)
                player.updatePrebufferedTrackCount()
            }
        } catch {
            await MainActor.run { [weak self] in
                guard let player = self else { return }
                player.prebufferTasks.removeValue(forKey: key)
                player.preparedPrebuffers.removeValue(forKey: key)
                player.prebufferURLs.removeValue(forKey: key)
                try? FileManager.default.removeItem(at: url)
                player.updatePrebufferedTrackCount()
                print("⚠️ Failed to prepare prebuffered file for \(song.title): \(error)")
            }
        }
    }

    private func updatePrebufferedTrackCount() {
        guard !queue.isEmpty else {
            prebufferedTrackCount = 0
            return
        }

        let start = currentIndex + 1
        guard start < queue.count else {
            prebufferedTrackCount = 0
            return
        }

        let end = min(queue.count, start + prebufferAheadCount)
        let count = queue[start..<end].filter { isPrebuffered($0) }.count
        if prebufferedTrackCount != count {
            prebufferedTrackCount = count
        }
    }

    private func prunePrebufferCache(keeping keepKeys: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: prebufferDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let knownSongs = queue + (currentSong.map { [$0] } ?? [])
        let keepFilenames = Set(keepKeys.compactMap { key -> String? in
            if let song = knownSongs.first(where: { prebufferKey(for: $0) == key }) {
                return sanitizedPrebufferFilename(for: song)
            }
            return nil
        })

        for key in Array(preparedPrebuffers.keys) where !keepKeys.contains(key) {
            preparedPrebuffers.removeValue(forKey: key)
            prebufferURLs.removeValue(forKey: key)
        }

        for url in files where !keepFilenames.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        updatePrebufferedTrackCount()
    }

    private func startPlayback(_ song: Song, startTime: TimeInterval = 0, autoplay: Bool = true) {
        print("🎵 AudioPlayer: startPlayback called with startTime: \(startTime)")
        print("🎵 Song: \(song.title) by \(song.artist ?? "Unknown")")
        print("🎵 Song ID: \(song.id)")
        print("🎵 Content type: \(song.contentType ?? "unknown")")
        print("🎵 Suffix: \(song.suffix ?? "unknown")")

        if currentSong?.id != song.id {
            playbackRetryTask?.cancel()
            playbackRetryTask = nil
            playbackRetryAttemptsBySongID.removeAll()
        }

        queueFinished = false
        self.currentSong = song
        self.currentTime = startTime

        // AVPlayer is the source of truth for progress. Seek the item after it is ready
        // instead of assuming the Subsonic timeOffset parameter was honored.
        self.baseTimeOffset = 0

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
        let preparedAsset: AVURLAsset?
        let prebufferKey = prebufferKey(for: song)
        prebufferTasks[prebufferKey]?.cancel()
        prebufferTasks.removeValue(forKey: prebufferKey)

        if let prebuffer = preparedPrebuffer(for: song) {
            playURL = prebuffer.url
            preparedAsset = prebuffer.asset
            print("🎵 Playing from prepared local queue file: \(prebuffer.url.lastPathComponent)")
        } else if let localURL = DownloadManager.shared.getLocalURL(song.id) {
            playURL = localURL
            preparedAsset = nil
            print("🎵 Playing from local file before preparation completed: \(localURL.lastPathComponent)")
        } else if let prebufferURL = existingPrebufferURL(for: song) {
            playURL = prebufferURL
            preparedAsset = nil
            print("🎵 Playing from cached queue file before preparation completed: \(prebufferURL.lastPathComponent)")
        } else {
            if shouldTranscodeForPlayback(song) {
                let bitRate = StreamingQuality.current.maxBitRate ?? StreamingQuality.max.rawValue
                let isNativelySupported = isFormatSupportedNatively(song.contentType, song.suffix)
                let reason = isNativelySupported ? StreamingQuality.current.description : "Unsupported format"
                print("⚠️ \(reason) - requesting MP3 transcode at \(bitRate) kbps")
                if let streamURL = streamURLForPlayback(song) {
                    playURL = streamURL
                    preparedAsset = nil
                    print("🎵 Streaming transcoded: \(streamURL.absoluteString)")
                } else {
                    print("❌ Failed to get transcoded stream URL")
                    return
                }
            } else {
                print("✅ Streaming original format '\(song.contentType ?? song.suffix ?? "unknown")'")
                if let streamURL = streamURLForPlayback(song) {
                    playURL = streamURL
                    preparedAsset = nil
                    print("🎵 Streaming from: \(streamURL.absoluteString)")
                } else {
                    print("❌ Failed to get stream URL")
                    return
                }
            }
        }

        print("🎵 Playback URL: \(playURL.absoluteString)")
        currentPlaybackURL = playURL
        currentPlaybackIsLocalFile = playURL.isFileURL

        // Remove old time observer if exists
        // if let observer = timeObserver {
        //    player?.removeTimeObserver(observer)
        //    timeObserver = nil
        // }

        // Clear per-item subscriptions to prevent duplicate notifications.
        playerItemCancellables.removeAll()
        isBuffering = true

        prepareAudioSessionForPlayback()

        // Follow Submariner's approach: Always use AVURLAsset with options
        // This works reliably on both macOS and watchOS
        print("🎵 Creating player item from asset...")

        if let contentType = playbackMimeType(for: song, url: playURL) {
            // Fix FLAC MIME type (Submariner workaround)
            let fixedContentType = contentType == "audio/x-flac" ? "audio/flac" : contentType
            print("🎵 Setting MIME type: \(fixedContentType)")
        }

        let asset = preparedAsset ?? makePlaybackAsset(for: song, url: playURL)
        let playerItem = AVPlayerItem(asset: asset)

        // Configure player item for better streaming
        // Let AVPlayer decide buffer size (default is usually aggressive buffering, which is better for stability)
        // playerItem.preferredForwardBufferDuration = 5.0

        // Reuse existing player instance
        player.replaceCurrentItem(with: playerItem)
        player.volume = Float(volume)

        observePlayerItem(playerItem, requestedStartTime: startTime, autoplay: autoplay)

        updateNowPlayingInfo()
    }

    func play() {
        prepareAudioSessionForPlayback()
        if queueFinished, queue.indices.contains(currentIndex) {
            startPlayback(queue[currentIndex])
            DeviceSyncManager.shared.broadcastLocalQueueAsShared()
            return
        }
        if player.currentItem == nil, let currentSong {
            startPlayback(currentSong, startTime: currentTime)
            DeviceSyncManager.shared.broadcastLocalQueueAsShared()
            return
        }
        player.play()
        isPlaying = true
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate || player.currentItem?.isPlaybackBufferEmpty == true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isBuffering = false
        isPlaying = false
        updateNowPlayingInfo()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isBuffering = false
        isPlaying = false
        currentSong = nil
        currentPlaybackURL = nil
        currentPlaybackIsLocalFile = false
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        queueFinished = false
        clearPlaylistGen()
        persistPlaybackState()
        updateNowPlayingInfo()
        print("⏹️ Playback stopped and queue cleared")
    }

    func togglePlayPause() {
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.toggleSelectedPlaybackTarget()
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
           (DownloadManager.shared.getLocalURL(currentSong.id) != nil || currentPlaybackIsLocalFile) {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let actualTime = self.player.currentTime().seconds
                    self.currentTime = actualTime.isFinite ? actualTime : time
                    self.persistPlaybackState()
                    self.updateNowPlayingInfo()
                }
            }
            currentTime = time
            return
        }
        
        // If streaming, we likely have a chunked stream which cannot be seeked backward 
        // or far forward easily. We should re-request the stream at the new offset.
        if let currentSong = currentSong {
            print("⏩ Seeking stream to \(time)s (reloading stream)")
            startPlayback(currentSong, startTime: time, autoplay: isPlaying)
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // AVPlayer's item time is the actual playback position. Keep the optional
                // offset at zero unless a future stream type explicitly requires it.
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
    }

    private func observePlayerItem(_ item: AVPlayerItem, requestedStartTime: TimeInterval, autoplay: Bool) {
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

                    self?.finishStartingPlayback(item, requestedStartTime: requestedStartTime, autoplay: autoplay)
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
                    self?.schedulePlaybackRetry(reason: "player item failure")
                }
            }
            .store(in: &playerItemCancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .sink { [weak self] _ in
                self?.handlePlaybackEnded()
            }
            .store(in: &playerItemCancellables)

        item.publisher(for: \.isPlaybackBufferEmpty)
            .sink { [weak self] isEmpty in
                guard let self, self.player.currentItem === item else { return }
                if self.isPlaying {
                    self.isBuffering = isEmpty
                }
            }
            .store(in: &playerItemCancellables)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] likelyToKeepUp in
                guard let self, self.player.currentItem === item else { return }
                if likelyToKeepUp {
                    self.isBuffering = false
                }
            }
            .store(in: &playerItemCancellables)
    }

    private func finishStartingPlayback(_ item: AVPlayerItem, requestedStartTime: TimeInterval, autoplay: Bool) {
        guard player.currentItem === item else { return }

        let clampedStart = max(0, requestedStartTime)
        guard clampedStart > 0.25 else {
            currentTime = 0
            isPlaying = autoplay
            if autoplay {
                player.play()
                isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate || item.isPlaybackBufferEmpty
            } else {
                isBuffering = false
            }
            updateNowPlayingInfo()
            scheduleQueuePrebuffer()
            return
        }

        let target = CMTime(seconds: clampedStart, preferredTimescale: 600)
        print("⏩ Seeking player item to \(clampedStart)s before playback")
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      let item,
                      self.player.currentItem === item else { return }

                let actualTime = self.player.currentTime().seconds
                if actualTime.isFinite {
                    self.currentTime = actualTime
                } else {
                    self.currentTime = clampedStart
                }

                if !finished {
                    print("⚠️ Initial seek did not finish cleanly; playing from \(self.currentTime)s")
                }

                if autoplay {
                    self.isPlaying = true
                    self.player.play()
                    self.isBuffering = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate || item.isPlaybackBufferEmpty
                } else {
                    self.isPlaying = false
                    self.isBuffering = false
                }
                self.updateNowPlayingInfo()
                self.scheduleQueuePrebuffer()
            }
        }
    }

    private func handlePlaybackEnded() {
        print("🛑 handlePlaybackEnded called. CurrentTime: \(currentTime), Duration: \(duration)")
        print("🛑 RepeatMode: \(repeatMode), Queue Count: \(queue.count), CurrentIndex: \(currentIndex)")

        // Protect against premature ending (e.g. network drop masquerading as end of file)
        // If we are less than 95% through and song is longer than 10s, it's likely an error
        if duration > 10, currentTime > 0, currentTime < (duration * 0.95) {
             print("⚠️ Premature end detected (Time: \(currentTime)/\(duration)). Attempting to resume playback from \(currentTime)...")
             schedulePlaybackRetry(reason: "premature stream end")
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
                player.replaceCurrentItem(with: nil)
                let finishedTime = duration > 0 ? duration : currentTime
                queueFinished = true
                isPlaying = false
                currentTime = finishedTime
                updateNowPlayingInfo()
                DeviceSyncManager.shared.broadcastLocalQueueAsShared()
                DeviceSyncManager.shared.publishLocalPlaybackStateNow()
                print("⏸️ Queue finished - stopped playback")
            }
        }
    }

    private func schedulePlaybackRetry(reason: String) {
        guard playbackRetryTask == nil else { return }
        guard let song = currentSong else { return }

        let attempt = playbackRetryAttemptsBySongID[song.id, default: 0]
        guard attempt < maxPlaybackRetryAttempts else {
            print("🛑 Giving up playback retry for \(song.title) after \(attempt) attempts (\(reason))")
            player.pause()
            isBuffering = false
            isPlaying = false
            updateNowPlayingInfo()
            DeviceSyncManager.shared.publishLocalPlaybackStateNow()
            return
        }

        let delay = min(pow(2.0, Double(attempt)), maxPlaybackRetryBackoff)
        let retryStartTime = currentTime
        let shouldAutoplay = isPlaying
        playbackRetryAttemptsBySongID[song.id] = attempt + 1
        isBuffering = shouldAutoplay
        print("⏳ Retrying playback for \(song.title) in \(Int(delay))s after \(reason) (attempt \(attempt + 1))")

        playbackRetryTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.playbackRetryTask = nil
            guard self.currentSong?.id == song.id else { return }
            self.startPlayback(song, startTime: retryStartTime, autoplay: shouldAutoplay)
        }
    }

    private func updateNowPlayingInfo() {
#if os(iOS) || os(watchOS) || os(macOS)
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

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
            let artworkSongID = song.id
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: coverURL)
                    if let image = PlatformImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        await MainActor.run {
                            guard self.currentSong?.id == artworkSongID else { return }
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

    @MainActor
    deinit {
        pendingPersistenceTask?.cancel()
        playbackRetryTask?.cancel()
        prebufferTasks.values.forEach { $0.cancel() }
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }
}
