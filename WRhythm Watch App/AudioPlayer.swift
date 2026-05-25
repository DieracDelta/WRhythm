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

struct PlaybackRetryPolicy: Sendable {
    static func shouldRunRetry(
        capturedSongID: String,
        currentSongID: String?,
        capturedIntentRevision: Int,
        currentIntentRevision: Int,
        capturedShouldAutoplay: Bool,
        isCurrentlyPlaying: Bool,
        capturedQueueIDs: [String]? = nil,
        currentQueueIDs: [String]? = nil,
        capturedIndex: Int? = nil,
        currentIndex: Int? = nil
    ) -> Bool {
        guard currentSongID == capturedSongID else { return false }
        guard capturedIntentRevision == currentIntentRevision else { return false }
        if let capturedQueueIDs {
            guard currentQueueIDs == capturedQueueIDs else { return false }
        }
        if let capturedIndex {
            guard currentIndex == capturedIndex else { return false }
        }
        guard capturedShouldAutoplay else { return true }
        return isCurrentlyPlaying
    }
}

struct PrebufferSchedulingPolicy: Sendable {
    static func upcomingKeys(queueKeys: [String], currentIndex: Int, aheadCount: Int) -> [String] {
        guard aheadCount > 0, !queueKeys.isEmpty else { return [] }
        let start = min(max(currentIndex + 1, 0), queueKeys.count)
        let end = min(queueKeys.count, start + aheadCount)
        guard start < end else { return [] }
        return Array(queueKeys[start..<end])
    }

    static func previousKeys(queueKeys: [String], currentIndex: Int, keepCount: Int) -> [String] {
        guard keepCount > 0, currentIndex > 0, !queueKeys.isEmpty else { return [] }
        let end = min(currentIndex, queueKeys.count)
        let start = max(0, end - keepCount)
        guard start < end else { return [] }
        return Array(queueKeys[start..<end])
    }

    static func desiredKeys(currentKey: String?, upcomingKeys: [String]) -> Set<String> {
        var keys = Set(upcomingKeys)
        if let currentKey {
            keys.insert(currentKey)
        }
        return keys
    }

    static func orderedCandidateKeys(currentKey: String?, upcomingKeys: [String]) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for key in ([currentKey].compactMap { $0 } + upcomingKeys) where !seen.contains(key) {
            seen.insert(key)
            keys.append(key)
        }
        return keys
    }

    static func readyCount(upcomingKeys: [String], preparedKeys: Set<String>) -> Int {
        upcomingKeys.filter { preparedKeys.contains($0) }.count
    }

    static func keysToSchedule(
        candidateKeys: [String],
        activeKeys: Set<String>,
        preparedKeys: Set<String>,
        failedKeys: Set<String>,
        maxConcurrentTasks: Int
    ) -> [String] {
        var availableSlots = max(0, maxConcurrentTasks - activeKeys.count)
        guard availableSlots > 0 else { return [] }

        var scheduled: [String] = []
        for key in candidateKeys {
            guard availableSlots > 0 else { break }
            guard !activeKeys.contains(key),
                  !preparedKeys.contains(key),
                  !failedKeys.contains(key) else {
                continue
            }
            scheduled.append(key)
            availableSlots -= 1
        }
        return scheduled
    }
}

struct PrebufferCachePruningPolicy: Sendable {
    static func shouldRemove(filename: String, keepFilenames: Set<String>) -> Bool {
        guard !filename.hasSuffix(".download") else { return false }
        return !keepFilenames.contains(filename)
    }
}

struct PrebufferRetryPolicy: Sendable {
    static let maxRetryDelay: TimeInterval = 30
    static let maxRetryAttempts = 6

    static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attempt))), maxRetryDelay)
    }

    static func shouldRetry(afterAttempt attempt: Int) -> Bool {
        attempt < maxRetryAttempts
    }
}

struct PrebufferProgressPolicy: Sendable {
    static func normalizedProgress(receivedBytes: Int64, expectedBytes: Int64) -> Double? {
        guard expectedBytes > 0 else { return nil }
        let progress = Double(max(0, receivedBytes)) / Double(expectedBytes)
        return min(max(progress, 0), 0.99)
    }

    static func percent(for progress: Double?) -> Int? {
        guard let progress else { return nil }
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return 0 }
        return min(99, max(1, Int((clamped * 100).rounded())))
    }

    static func aggregatePercent(progressByKey: [String: Double], activeKeys: Set<String>) -> Int? {
        let activeProgress = activeKeys.compactMap { progressByKey[$0] }
        guard !activeProgress.isEmpty else { return nil }
        let average = activeProgress.reduce(0, +) / Double(activeProgress.count)
        return percent(for: average)
    }

    static func downloadStatuses(
        for songs: [Song],
        activeKeys: Set<String>,
        progressByKey: [String: Double],
        keyForSong: (Song) -> String
    ) -> [PrebufferDownloadStatus] {
        var seen = Set<String>()
        return songs.compactMap { song in
            let key = keyForSong(song)
            guard activeKeys.contains(key), !seen.contains(key) else { return nil }
            seen.insert(key)
            return PrebufferDownloadStatus(
                song: song,
                progressPercent: percent(for: progressByKey[key])
            )
        }
    }

    static func statusSummary(
        readyCount: Int,
        activeCount: Int,
        activePercent: Int?,
        playerIsBuffering: Bool,
        playerBufferPercent: Int?
    ) -> String? {
        var parts: [String] = []
        if readyCount > 0 {
            parts.append("\(readyCount) available")
        }
        if activeCount > 0 {
            if let activePercent {
                parts.append("\(activeCount) downloading \(activePercent)%")
            } else {
                parts.append("\(activeCount) downloading")
            }
        }
        if playerIsBuffering {
            if let playerBufferPercent, playerBufferPercent > 0 {
                parts.append("buffering \(playerBufferPercent)%")
            } else {
                parts.append("buffering")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

struct PrebufferDownloadStatus: Identifiable, Equatable, Sendable {
    let song: Song
    let progressPercent: Int?

    var id: String { song.id }

    static func == (lhs: PrebufferDownloadStatus, rhs: PrebufferDownloadStatus) -> Bool {
        lhs.song.id == rhs.song.id && lhs.progressPercent == rhs.progressPercent
    }
}

struct PrebufferPublicationPolicy: Sendable {
    static func shouldPublishPreparedBuffer(
        key: String,
        desiredKeys: Set<String>,
        activeTaskKeys: Set<String>,
        capturedToken: String,
        activeToken: String?
    ) -> Bool {
        desiredKeys.contains(key) && activeTaskKeys.contains(key) && activeToken == capturedToken
    }
}

struct AsyncTaskOwnershipPolicy: Sendable {
    static func isCurrent(capturedToken: String, activeToken: String?) -> Bool {
        activeToken == capturedToken
    }
}

struct NowPlayingArtworkLoadPolicy: Sendable {
    static func shouldStartLoad(songID: String, inFlightSongID: String?, cachedSongIDs: Set<String>) -> Bool {
        guard !cachedSongIDs.contains(songID) else { return false }
        return inFlightSongID != songID
    }
}

struct PlayerItemEventPolicy: Sendable {
    static func shouldHandle(currentItemMatches: Bool) -> Bool {
        currentItemMatches
    }
}

struct PlaybackStartupStatePolicy: Sendable {
    static func isPlayingDuringStartup(autoplay: Bool) -> Bool {
        autoplay
    }
}

struct PlaybackErrorInfo: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let technicalDetails: String
    let recoverySuggestion: String
}

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
    @Published private(set) var currentBufferPercent: Int?
    @Published private(set) var playbackError: PlaybackErrorInfo?
    @Published private(set) var prebufferedTrackCount = 0
    @Published private(set) var prebufferedSongs: [Song] = []
    @Published private(set) var retainedPrebufferedSongs: [Song] = []
    @Published private(set) var availablePrebufferedSongs: [Song] = []
    @Published private(set) var prebufferDownloadStatuses: [PrebufferDownloadStatus] = []
    @Published private(set) var prebufferingTrackCount = 0
    @Published private(set) var prebufferingProgressPercent: Int?
    @Published var queue: [Song] = []
    @Published var currentIndex: Int = 0
    @Published var playlistGenQueue: [Song] = []
    @Published var playlistGenSourceTitle: String?
    @Published var playlistGenSourceArtist: String?
    @Published private(set) var playlistGenIsGenerating = false
    @Published private(set) var playlistGenGeneratingTitle: String?
    @Published private(set) var playlistGenErrorMessage: String?
    @Published private(set) var playlistGenErrorDetails: String?
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

    private struct PlaylistGenRestoreState {
        let queue: [Song]
        let currentIndex: Int
        let currentSong: Song?
        let currentTime: TimeInterval
        let duration: TimeInterval
        let wasPlaying: Bool
        let playlistGenQueue: [Song]
        let playlistGenSourceTitle: String?
        let playlistGenSourceArtist: String?
    }

    private enum PrebufferPreparationError: Error {
        case notPlayable
    }

    private enum PlaylistGenerationError: LocalizedError {
        case noSongs

        var errorDescription: String? {
            switch self {
            case .noSongs:
                return "No similar songs were returned by the server."
            }
        }
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
    private let maxConcurrentPrebuffers = 3
    private var prebufferAheadCount: Int {
        let saved = UserDefaults.standard.object(forKey: "prebufferAheadCount") as? Int ?? 8
        return PrebufferSettingsPolicy.sanitizeAheadCount(saved)
    }

    private var retainPreviousPrebufferCount: Int {
        let saved = UserDefaults.standard.object(forKey: "retainPreviousPrebufferCount") as? Int ?? 3
        return PrebufferSettingsPolicy.sanitizePreviousCount(saved)
    }
    private var prebufferTasks: [String: Task<Void, Never>] = [:]
    private var prebufferTaskTokens: [String: String] = [:]
    private var prebufferProgressByKey: [String: Double] = [:]
    private var prebufferURLs: [String: URL] = [:]
    private var preparedPrebuffers: [String: PreparedPrebuffer] = [:]
    private var currentPlaybackURL: URL?
    private var currentPlaybackIsLocalFile = false
    private var playbackRetryTask: Task<Void, Never>?
    private var playbackRetryAttemptsBySongID: [String: Int] = [:]
    private var playbackIntentRevision = 0
    private var playlistGenTask: Task<Void, Never>?
    private var playlistGenRestoreState: PlaylistGenRestoreState?
    private var scrobbleTracker = ScrobbleProgressTracker()
    private let maxPlaybackRetryAttempts = 4
    private let maxPlaybackRetryBackoff: TimeInterval = 30
    private var prebufferRetryAttemptsByKey: [String: Int] = [:]
    private var prebufferRetryTasksByKey: [String: Task<Void, Never>] = [:]
    private var exhaustedPrebufferRetryKeys: Set<String> = []
#if os(iOS) || os(watchOS) || os(macOS)
    private var nowPlayingArtworkTask: Task<Void, Never>?
    private var nowPlayingArtworkSongID: String?
    private var nowPlayingArtworkCache: [String: MPMediaItemArtwork] = [:]
    private let maxNowPlayingArtworkCacheEntries = 20
#endif
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

    var queueBufferStatusSummary: String? {
        PrebufferProgressPolicy.statusSummary(
            readyCount: availablePrebufferedSongs.count,
            activeCount: prebufferingTrackCount,
            activePercent: prebufferingProgressPercent,
            playerIsBuffering: isBuffering,
            playerBufferPercent: currentBufferPercent
        )
    }

    private func recordPlaybackIntentChange() {
        playbackIntentRevision += 1
    }

    private func recordQueueIntentChange() {
        recordPlaybackIntentChange()
        playbackRetryTask?.cancel()
        playbackRetryTask = nil
    }

    private var scrobblingEnabled: Bool {
        UserDefaults.standard.object(forKey: "scrobblingEnabled") as? Bool ?? true
    }

    private var scrobblingAllowedForCurrentContext: Bool {
        ScrobbleDispatchPolicy.shouldTrack(
            scrobblingEnabled: scrobblingEnabled,
            offlineMode: UserDefaults.standard.bool(forKey: "offlineMode"),
            hasCredentials: NavidromeAPI.shared.hasCredentials,
            isPlaybackOwner: true
        )
    }

    private func beginScrobbleTracking(for song: Song, startTime: TimeInterval) {
        guard scrobblingAllowedForCurrentContext else {
            scrobbleTracker.reset()
            return
        }

        sendScrobbleEvent(scrobbleTracker.start(songID: song.id, currentTime: startTime, now: Date()))
    }

    private func updateScrobbleTracking() {
        guard let song = currentSong else {
            scrobbleTracker.reset()
            return
        }

        guard scrobblingAllowedForCurrentContext else {
            scrobbleTracker.reset()
            return
        }

        let effectiveDuration = duration > 0 ? duration : TimeInterval(song.duration ?? 0)
        if let event = scrobbleTracker.update(
            songID: song.id,
            currentTime: liveCurrentTime,
            duration: effectiveDuration,
            isPlaying: isPlaying,
            now: Date()
        ) {
            sendScrobbleEvent(event)
        }
    }

    private func sendScrobbleEvent(_ event: ScrobblePlaybackEvent) {
        Task { @MainActor in
            do {
                switch event {
                case .nowPlaying(let songID):
                    try await NavidromeAPI.shared.scrobble(songId: songID, submission: false)
                case .submission(let songID):
                    try await NavidromeAPI.shared.scrobble(songId: songID, submission: true)
                }
            } catch {
                print("⚠️ Scrobble failed: \(error.localizedDescription)")
            }
        }
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
            .receive(on: DispatchQueue.main)
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
                PlaybackKeyboardActions.setLocalPlaying(true)
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
                PlaybackKeyboardActions.setLocalPlaying(false)
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
                PlaybackKeyboardActions.toggleLocalPlayback()
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
        recordQueueIntentChange()
        self.queue = [song]
        self.currentIndex = 0
        startPlayback(song)
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
    }

    func playQueue(_ songs: [Song], startingAt index: Int = 0, startTime: TimeInterval = 0, clearGeneratedPlaylist: Bool = true) {
        guard !songs.isEmpty, index < songs.count else { return }
        if clearGeneratedPlaylist {
            clearPlaylistGen()
        }
        if DeviceSyncManager.shared.routePlaybackRequestToConnectedDevice(songs, startingAt: index) {
            return
        }

        recordQueueIntentChange()
        self.isShuffled = false
        self.originalQueue = []
        self.queue = songs
        self.currentIndex = index
        startPlayback(songs[index], startTime: startTime)
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
    }

    func playGeneratedPlaylist(sourceSong: Song, songs: [Song], startingAt index: Int = 0) {
        guard !songs.isEmpty else { return }
        playlistGenTask?.cancel()
        playlistGenTask = nil
        playlistGenRestoreState = nil
        playlistGenIsGenerating = false
        playlistGenGeneratingTitle = nil
        playlistGenErrorMessage = nil
        playlistGenErrorDetails = nil
        playlistGenSourceTitle = sourceSong.title
        playlistGenSourceArtist = sourceSong.artist
        playlistGenQueue = songs
        playQueue(songs, startingAt: index, clearGeneratedPlaylist: false)
    }

    func clearPlaylistGen() {
        playlistGenTask?.cancel()
        playlistGenTask = nil
        playlistGenRestoreState = nil
        playlistGenIsGenerating = false
        playlistGenGeneratingTitle = nil
        playlistGenQueue = []
        playlistGenSourceTitle = nil
        playlistGenSourceArtist = nil
    }

    func dismissPlaylistGenError() {
        playlistGenErrorMessage = nil
        playlistGenErrorDetails = nil
    }

    func dismissPlaybackError() {
        playbackError = nil
    }

    func cancelPlaylistGeneration() {
        playlistGenTask?.cancel()
        playlistGenTask = nil
        restorePlaylistGenState()
        playlistGenIsGenerating = false
        playlistGenGeneratingTitle = nil
    }

    func startPlaylistGeneration(for sourceSong: Song, count: Int, fallbackToRandom: Bool = true) {
        playlistGenTask?.cancel()
        playlistGenTask = nil

        playlistGenRestoreState = PlaylistGenRestoreState(
            queue: queue,
            currentIndex: currentIndex,
            currentSong: currentSong,
            currentTime: liveCurrentTime,
            duration: duration,
            wasPlaying: isPlaying,
            playlistGenQueue: playlistGenQueue,
            playlistGenSourceTitle: playlistGenSourceTitle,
            playlistGenSourceArtist: playlistGenSourceArtist
        )

        playlistGenIsGenerating = true
        playlistGenGeneratingTitle = sourceSong.title
        playlistGenErrorMessage = nil
        playlistGenErrorDetails = nil
        playlistGenQueue = []
        playlistGenSourceTitle = sourceSong.title
        playlistGenSourceArtist = sourceSong.artist

        pause()
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: false)
#if os(macOS)
        NotificationCenter.default.post(name: .wrhythmShowPlaylistGen, object: nil)
#endif

        let requestedCount = max(count, 1)
        playlistGenTask = Task { [weak self] in
            do {
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(sourceSong, count: requestedCount)
                if similarSongs.isEmpty && fallbackToRandom {
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: requestedCount)
                }
                try Task.checkCancellation()

                let filteredSongs = similarSongs.filter { $0.id != sourceSong.id }
                guard !filteredSongs.isEmpty else {
                    throw PlaylistGenerationError.noSongs
                }
                let generatedQueue = [sourceSong] + filteredSongs

                await MainActor.run {
                    guard let self, self.playlistGenIsGenerating else { return }
                    self.playlistGenTask = nil
                    self.playGeneratedPlaylist(sourceSong: sourceSong, songs: generatedQueue)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.playlistGenTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.handlePlaylistGenerationFailure(error, sourceTitle: sourceSong.title)
                }
            }
        }
    }

    private func handlePlaylistGenerationFailure(_ error: Error, sourceTitle: String) {
        playlistGenTask = nil
        restorePlaylistGenState()
        playlistGenIsGenerating = false
        playlistGenGeneratingTitle = nil
        playlistGenErrorMessage = "Unable to generate playlist"
        playlistGenErrorDetails = "Playlist Gen for \"\(sourceTitle)\" failed: \(error.localizedDescription)"
    }

    private func restorePlaylistGenState() {
        guard let state = playlistGenRestoreState else { return }
        playlistGenRestoreState = nil

        playlistGenQueue = state.playlistGenQueue
        playlistGenSourceTitle = state.playlistGenSourceTitle
        playlistGenSourceArtist = state.playlistGenSourceArtist

        queue = state.queue
        currentIndex = min(max(state.currentIndex, 0), max(state.queue.count - 1, 0))
        currentSong = state.currentSong
        currentTime = state.currentTime
        duration = state.duration
        queueFinished = false

        guard state.currentSong != nil else {
            pause()
            return
        }

        seek(to: state.currentTime)
        if state.wasPlaying {
            play()
            DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
        } else {
            pause()
            DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: false)
        }
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

        recordQueueIntentChange()
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
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
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

        recordQueueIntentChange()
        let appendedStartIndex = queue.count
        let shouldStartAppendedSongs = queueFinished || currentSong == nil
        queue.append(contentsOf: songs)
        if shouldStartAppendedSongs, queue.indices.contains(appendedStartIndex) {
            currentIndex = appendedStartIndex
            startPlayback(queue[appendedStartIndex])
        }
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: shouldStartAppendedSongs ? true : nil)
    }

    @discardableResult
    func removeQueueItem(at index: Int) -> Bool {
        guard queue.indices.contains(index), index != currentIndex else { return false }
        recordQueueIntentChange()
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if currentIndex >= queue.count {
            currentIndex = max(queue.count - 1, 0)
        }
        queueFinished = false
        return true
    }

    @discardableResult
    func clearQueueKeepingCurrent() -> Bool {
        let retainedSong = currentSong ?? (queue.indices.contains(currentIndex) ? queue[currentIndex] : nil)
        guard queue.count != 1 || queue.first?.id != retainedSong?.id else { return false }

        recordQueueIntentChange()
        if let retainedSong {
            queue = [retainedSong]
            currentIndex = 0
        } else {
            queue = []
            currentIndex = 0
        }
        queueFinished = false
        return true
    }

    func mirrorQueueWithoutPlayback(_ songs: [Song], currentIndex index: Int, currentTime: TimeInterval = 0) {
        guard !songs.isEmpty else { return }
        recordQueueIntentChange()
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

    private nonisolated static func downloadPrebufferFile(
        from url: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Double?) async -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).download", isDirectory: false)
        try? FileManager.default.removeItem(at: temporaryURL)
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)

        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        var didMoveFile = false
        defer {
            try? fileHandle.close()
            if !didMoveFile {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let expectedBytes = response.expectedContentLength
        await progressHandler(PrebufferProgressPolicy.normalizedProgress(receivedBytes: 0, expectedBytes: expectedBytes))

        var receivedBytes: Int64 = 0
        var chunk = Data()
        chunk.reserveCapacity(64 * 1_024)

        for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)

            if chunk.count >= 64 * 1_024 {
                try fileHandle.write(contentsOf: chunk)
                receivedBytes += Int64(chunk.count)
                chunk.removeAll(keepingCapacity: true)
                await progressHandler(PrebufferProgressPolicy.normalizedProgress(receivedBytes: receivedBytes, expectedBytes: expectedBytes))
            }
        }

        if !chunk.isEmpty {
            try fileHandle.write(contentsOf: chunk)
            receivedBytes += Int64(chunk.count)
            chunk.removeAll(keepingCapacity: true)
            await progressHandler(PrebufferProgressPolicy.normalizedProgress(receivedBytes: receivedBytes, expectedBytes: expectedBytes))
        }

        try fileHandle.close()
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        didMoveFile = true
    }

    private func scheduleQueuePrebuffer() {
        guard !queue.isEmpty else {
            prebufferTasks.values.forEach { $0.cancel() }
            prebufferTasks.removeAll()
            prebufferTaskTokens.removeAll()
            prebufferProgressByKey.removeAll()
            preparedPrebuffers.removeAll()
            clearPrebufferRetryState()
            updatePrebufferedTrackCount()
            return
        }

        let queueKeys = queue.map(prebufferKey)
        let currentQueueSong = queue.indices.contains(currentIndex) ? queue[currentIndex] : currentSong
        let currentKey = currentQueueSong.map(prebufferKey)
        let start = min(max(currentIndex + 1, 0), queue.count)
        let end = min(queue.count, start + prebufferAheadCount)
        let upcomingSongs = start < end ? Array(queue[start..<end]) : []
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: currentIndex,
            aheadCount: prebufferAheadCount
        )
        let retainedPreviousKeys = Set(PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: currentIndex,
            keepCount: retainPreviousPrebufferCount
        ))
        let desiredKeys = PrebufferSchedulingPolicy.desiredKeys(currentKey: currentKey, upcomingKeys: upcomingKeys)
        let retainedKeys = desiredKeys.union(retainedPreviousKeys)
        let candidateKeys = PrebufferSchedulingPolicy.orderedCandidateKeys(currentKey: currentKey, upcomingKeys: upcomingKeys)
        var songsByKey: [String: Song] = [:]
        if let currentQueueSong, let currentKey {
            songsByKey[currentKey] = currentQueueSong
        }
        for song in upcomingSongs {
            songsByKey[prebufferKey(for: song)] = song
        }

        let staleKeys = prebufferTasks.keys.filter { !desiredKeys.contains($0) }
        for key in staleKeys {
            prebufferTasks[key]?.cancel()
            prebufferTasks.removeValue(forKey: key)
            prebufferTaskTokens.removeValue(forKey: key)
            prebufferProgressByKey.removeValue(forKey: key)
        }

        for key in Array(preparedPrebuffers.keys) where !retainedKeys.contains(key) {
            preparedPrebuffers.removeValue(forKey: key)
        }
        prunePrebufferRetryState(keeping: desiredKeys)

        prunePrebufferCache(keeping: retainedKeys)
        updatePrebufferedTrackCount()

        let keysToSchedule = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: candidateKeys,
            activeKeys: Set(prebufferTasks.keys),
            preparedKeys: Set(preparedPrebuffers.keys),
            failedKeys: Set(prebufferRetryTasksByKey.keys).union(exhaustedPrebufferRetryKeys),
            maxConcurrentTasks: maxConcurrentPrebuffers
        )

        for key in keysToSchedule {
            guard let song = songsByKey[key] else { continue }
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
        let taskToken = UUID().uuidString
        prebufferTaskTokens[key] = taskToken
        prebufferProgressByKey[key] = 0
        updatePrebufferedTrackCount()

        prebufferTasks[key] = Task { [weak self] in
            do {
                try await Self.downloadPrebufferFile(from: url, to: destinationURL) { [weak self] progress in
                    await MainActor.run { [weak self] in
                        guard let player = self else { return }
                        guard AsyncTaskOwnershipPolicy.isCurrent(capturedToken: taskToken, activeToken: player.prebufferTaskTokens[key]) else { return }
                        if let progress {
                            player.prebufferProgressByKey[key] = progress
                        } else {
                            player.prebufferProgressByKey.removeValue(forKey: key)
                        }
                        player.updatePrebufferedTrackCount()
                    }
                }
                try Task.checkCancellation()

                await self?.prepareDownloadedPrebuffer(song, key: key, url: destinationURL, taskToken: taskToken)
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let player = self else { return }
                    guard AsyncTaskOwnershipPolicy.isCurrent(capturedToken: taskToken, activeToken: player.prebufferTaskTokens[key]) else { return }
                    player.prebufferTasks.removeValue(forKey: key)
                    player.prebufferTaskTokens.removeValue(forKey: key)
                    player.prebufferProgressByKey.removeValue(forKey: key)
                    player.updatePrebufferedTrackCount()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let player = self else { return }
                    guard AsyncTaskOwnershipPolicy.isCurrent(capturedToken: taskToken, activeToken: player.prebufferTaskTokens[key]) else { return }
                    player.prebufferTasks.removeValue(forKey: key)
                    player.prebufferTaskTokens.removeValue(forKey: key)
                    player.prebufferProgressByKey.removeValue(forKey: key)
                    player.updatePrebufferedTrackCount()
                    print("⚠️ Failed to prebuffer \(song.title): \(error)")
                    player.schedulePrebufferRetry(for: song, key: key)
                }
            }
        }
    }

    private func preparePrebufferedFile(_ song: Song, key: String, url: URL) {
        let taskToken = UUID().uuidString
        prebufferTaskTokens[key] = taskToken
        prebufferTasks[key] = Task { [weak self] in
            await self?.prepareDownloadedPrebuffer(song, key: key, url: url, taskToken: taskToken)
        }
    }

    private func prepareDownloadedPrebuffer(_ song: Song, key: String, url: URL, taskToken: String) async {
        do {
            let prebuffer = try await Self.preparePrebufferAsset(for: song, url: url)
            try Task.checkCancellation()

            await MainActor.run { [weak self] in
                guard let player = self else { return }
                guard PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
                    key: key,
                    desiredKeys: player.desiredPrebufferKeys(),
                    activeTaskKeys: Set(player.prebufferTasks.keys),
                    capturedToken: taskToken,
                    activeToken: player.prebufferTaskTokens[key]
                ) else {
                    if AsyncTaskOwnershipPolicy.isCurrent(capturedToken: taskToken, activeToken: player.prebufferTaskTokens[key]) {
                        player.prebufferTasks.removeValue(forKey: key)
                        player.prebufferTaskTokens.removeValue(forKey: key)
                        player.prebufferProgressByKey.removeValue(forKey: key)
                        player.preparedPrebuffers.removeValue(forKey: key)
                        player.prebufferURLs.removeValue(forKey: key)
                        if player.prebufferURL(for: song) == url {
                            try? FileManager.default.removeItem(at: url)
                        }
                        player.updatePrebufferedTrackCount()
                    }
                    return
                }
                player.prebufferURLs[key] = prebuffer.url
                player.preparedPrebuffers[key] = prebuffer
                player.clearPrebufferRetryState(for: key)
                player.prebufferTasks.removeValue(forKey: key)
                player.prebufferTaskTokens.removeValue(forKey: key)
                player.prebufferProgressByKey.removeValue(forKey: key)
                player.updatePrebufferedTrackCount()
                print("✅ Prebuffered and prepared next queue item: \(song.title)")
                player.scheduleQueuePrebuffer()
            }
        } catch is CancellationError {
            await MainActor.run { [weak self] in
                guard let player = self else { return }
                guard AsyncTaskOwnershipPolicy.isCurrent(capturedToken: taskToken, activeToken: player.prebufferTaskTokens[key]) else { return }
                player.prebufferTasks.removeValue(forKey: key)
                player.prebufferTaskTokens.removeValue(forKey: key)
                player.prebufferProgressByKey.removeValue(forKey: key)
                player.updatePrebufferedTrackCount()
            }
        } catch {
            await MainActor.run { [weak self] in
                guard let player = self else { return }
                guard AsyncTaskOwnershipPolicy.isCurrent(capturedToken: taskToken, activeToken: player.prebufferTaskTokens[key]) else { return }
                player.prebufferTasks.removeValue(forKey: key)
                player.prebufferTaskTokens.removeValue(forKey: key)
                player.prebufferProgressByKey.removeValue(forKey: key)
                player.preparedPrebuffers.removeValue(forKey: key)
                player.prebufferURLs.removeValue(forKey: key)
                if player.prebufferURL(for: song) == url {
                    try? FileManager.default.removeItem(at: url)
                }
                player.updatePrebufferedTrackCount()
                print("⚠️ Failed to prepare prebuffered file for \(song.title): \(error)")
                player.schedulePrebufferRetry(for: song, key: key)
            }
        }
    }

    private func desiredPrebufferKeys() -> Set<String> {
        guard !queue.isEmpty else { return [] }
        let currentKey = queue.indices.contains(currentIndex) ? prebufferKey(for: queue[currentIndex]) : currentSong.map(prebufferKey)
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queue.map(prebufferKey),
            currentIndex: currentIndex,
            aheadCount: prebufferAheadCount
        )
        return PrebufferSchedulingPolicy.desiredKeys(currentKey: currentKey, upcomingKeys: upcomingKeys)
    }

    private func schedulePrebufferRetry(for song: Song, key: String) {
        guard prebufferRetryTasksByKey[key] == nil else { return }
        guard desiredPrebufferKeys().contains(key) else { return }

        let attempt = prebufferRetryAttemptsByKey[key, default: 0]
        guard PrebufferRetryPolicy.shouldRetry(afterAttempt: attempt) else {
            exhaustedPrebufferRetryKeys.insert(key)
            print("⚠️ Giving up prebuffer for \(song.title) after \(attempt) attempts")
            updatePrebufferedTrackCount()
            Task { @MainActor [weak self] in
                self?.scheduleQueuePrebuffer()
            }
            return
        }

        let delay = PrebufferRetryPolicy.retryDelay(forAttempt: attempt)
        prebufferRetryAttemptsByKey[key] = attempt + 1
        print("⏳ Retrying prebuffer for \(song.title) in \(Int(delay))s (attempt \(attempt + 1))")

        prebufferRetryTasksByKey[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.prebufferRetryTasksByKey.removeValue(forKey: key)
            self.scheduleQueuePrebuffer()
        }
    }

    private func clearPrebufferRetryState(for key: String) {
        prebufferRetryAttemptsByKey.removeValue(forKey: key)
        prebufferRetryTasksByKey.removeValue(forKey: key)?.cancel()
        exhaustedPrebufferRetryKeys.remove(key)
    }

    private func clearPrebufferRetryState() {
        prebufferRetryTasksByKey.values.forEach { $0.cancel() }
        prebufferRetryTasksByKey.removeAll()
        prebufferRetryAttemptsByKey.removeAll()
        exhaustedPrebufferRetryKeys.removeAll()
    }

    private func prunePrebufferRetryState(keeping desiredKeys: Set<String>) {
        for key in Array(prebufferRetryAttemptsByKey.keys) where !desiredKeys.contains(key) {
            prebufferRetryAttemptsByKey.removeValue(forKey: key)
        }
        for key in Array(prebufferRetryTasksByKey.keys) where !desiredKeys.contains(key) {
            prebufferRetryTasksByKey.removeValue(forKey: key)?.cancel()
        }
        exhaustedPrebufferRetryKeys = exhaustedPrebufferRetryKeys.intersection(desiredKeys)
    }

    private func updatePrebufferedTrackCount() {
        let activeCount = prebufferTasks.count
        if prebufferingTrackCount != activeCount {
            prebufferingTrackCount = activeCount
        }
        let activePercent = PrebufferProgressPolicy.aggregatePercent(
            progressByKey: prebufferProgressByKey,
            activeKeys: Set(prebufferTasks.keys)
        )
        if prebufferingProgressPercent != activePercent {
            prebufferingProgressPercent = activePercent
        }

        guard !queue.isEmpty else {
            prebufferedTrackCount = 0
            prebufferedSongs = []
            retainedPrebufferedSongs = []
            availablePrebufferedSongs = []
            prebufferDownloadStatuses = []
            return
        }

        let start = currentIndex + 1
        let end = min(queue.count, start + prebufferAheadCount)
        for (key, prebuffer) in preparedPrebuffers where !FileManager.default.fileExists(atPath: prebuffer.url.path) {
            preparedPrebuffers.removeValue(forKey: key)
            prebufferURLs.removeValue(forKey: key)
        }
        let upcomingSlice = start < end ? queue[start..<end] : queue[start..<start]
        let upcomingKeys = upcomingSlice.map(prebufferKey)
        let readySongs = upcomingSlice.filter { song in
            preparedPrebuffers[prebufferKey(for: song)] != nil
        }
        let currentSlice = queue.indices.contains(currentIndex) ? [queue[currentIndex]] : []
        let previousEnd = min(max(currentIndex, 0), queue.count)
        let previousStart = max(0, previousEnd - retainPreviousPrebufferCount)
        let previousSlice = previousStart < previousEnd ? queue[previousStart..<previousEnd] : queue[previousEnd..<previousEnd]
        let readyPreviousSongs = previousSlice.filter { song in
            preparedPrebuffers[prebufferKey(for: song)] != nil
        }
        let count = PrebufferSchedulingPolicy.readyCount(
            upcomingKeys: upcomingKeys,
            preparedKeys: Set(preparedPrebuffers.keys)
        )
        if prebufferedTrackCount != count {
            prebufferedTrackCount = count
        }
        if prebufferedSongs.map(\.id) != readySongs.map(\.id) {
            prebufferedSongs = readySongs
        }
        if retainedPrebufferedSongs.map(\.id) != readyPreviousSongs.map(\.id) {
            retainedPrebufferedSongs = readyPreviousSongs
        }
        let availableSongs = readyPreviousSongs + readySongs
        if availablePrebufferedSongs.map(\.id) != availableSongs.map(\.id) {
            availablePrebufferedSongs = availableSongs
        }
        let downloadStatuses = PrebufferProgressPolicy.downloadStatuses(
            for: Array(previousSlice) + currentSlice + Array(upcomingSlice),
            activeKeys: Set(prebufferTasks.keys),
            progressByKey: prebufferProgressByKey,
            keyForSong: { prebufferKey(for: $0) }
        )
        if prebufferDownloadStatuses != downloadStatuses {
            prebufferDownloadStatuses = downloadStatuses
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

        for url in files where PrebufferCachePruningPolicy.shouldRemove(
            filename: url.lastPathComponent,
            keepFilenames: keepFilenames
        ) {
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
        playbackError = nil
        currentBufferPercent = nil

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
        beginScrobbleTracking(for: song, startTime: startTime)
        scheduleQueuePrebuffer()

        // Check if song is downloaded first
        let playURL: URL
        let preparedAsset: AVURLAsset?

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
                    publishPlaybackError(
                        title: "Unable to build stream URL",
                        song: song,
                        url: nil,
                        error: nil,
                        technicalDetails: "WRhythm could not build a Navidrome stream URL for a transcoded request.",
                        recoverySuggestion: "Check the saved server URL and credentials, then try playing the track again."
                    )
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
                    publishPlaybackError(
                        title: "Unable to build stream URL",
                        song: song,
                        url: nil,
                        error: nil,
                        technicalDetails: "WRhythm could not build a Navidrome stream URL for the original stream.",
                        recoverySuggestion: "Check the saved server URL and credentials, then try playing the track again."
                    )
                    return
                }
            }
        }

        print("🎵 Playback URL: \(playURL.absoluteString)")
        self.isPlaying = PlaybackStartupStatePolicy.isPlayingDuringStartup(autoplay: autoplay)
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
        recordPlaybackIntentChange()
        prepareAudioSessionForPlayback()
        if queueFinished, queue.indices.contains(currentIndex) {
            startPlayback(queue[currentIndex])
            DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
            return
        }
        if player.currentItem == nil, let currentSong {
            startPlayback(currentSong, startTime: currentTime)
            DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
            return
        }
        player.play()
        isPlaying = true
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate || player.currentItem?.isPlaybackBufferEmpty == true
        updateNowPlayingInfo()
    }

    func pause() {
        recordPlaybackIntentChange()
        player.pause()
        isBuffering = false
        isPlaying = false
        updateNowPlayingInfo()
    }

    func stop() {
        recordPlaybackIntentChange()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isBuffering = false
        isPlaying = false
        currentSong = nil
        scrobbleTracker.reset()
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
        DeviceSyncManager.shared.setPlaying(!isPlaying, targetDeviceID: DeviceSyncManager.shared.localPlaybackTargetID)
    }

    func next() {
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.sendNext()
            return
        }
        guard currentIndex < queue.count - 1 else { return }
        recordQueueIntentChange()
        currentIndex += 1
        startPlayback(queue[currentIndex])
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
    }

    func previous() {
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.sendPrevious()
            return
        }
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            recordQueueIntentChange()
            currentIndex -= 1
            startPlayback(queue[currentIndex])
            DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: TimeInterval) {
        if !DeviceSyncManager.shared.isLocalPlaybackOutput {
            DeviceSyncManager.shared.sendSeek(to: time)
            return
        }
        recordPlaybackIntentChange()
        // If we are playing a local file, standard seek works
        if let currentSong = currentSong, 
           (DownloadManager.shared.getLocalURL(currentSong.id) != nil || currentPlaybackIsLocalFile) {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            let seekItemIdentifier = player.currentItem.map(ObjectIdentifier.init)
            let seekIntentRevision = playbackIntentRevision
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, seekItemIdentifier] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.playbackIntentRevision == seekIntentRevision,
                          let seekItemIdentifier,
                          let currentItem = self.player.currentItem,
                          ObjectIdentifier(currentItem) == seekItemIdentifier else { return }
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
                self.updateScrobbleTracking()

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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self,
                      PlayerItemEventPolicy.shouldHandle(currentItemMatches: self.player.currentItem === item) else {
                    return
                }
                print("🎵 Player item status changed: \(status.rawValue) (0=unknown, 1=ready, 2=failed)")

                if status == .readyToPlay {
                    self.playbackError = nil
                    let dur = item.duration
                    print("✅ Player ready to play")
                    print("📊 Duration details - seconds: \(dur.seconds), isNumeric: \(dur.isNumeric), isIndefinite: \(dur.isIndefinite), isValid: \(dur.isValid)")

                    // Always prefer actual stream duration over metadata (metadata can be wrong)
                    if dur.isNumeric && dur.seconds > 0 {
                        self.duration = dur.seconds
                        print("✅ Duration set from stream: \(dur.seconds)s")
                    } else {
                        print("⚠️ Stream duration not available (isIndefinite: \(dur.isIndefinite))")
                        if self.duration > 0 {
                            print("ℹ️ Using song metadata duration: \(self.duration)s")
                        }
                    }

                    self.finishStartingPlayback(item, requestedStartTime: requestedStartTime, autoplay: autoplay)
                } else if status == .failed {
                    print("❌ Player item failed!")
                    let failureURL = self.currentPlaybackURL
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
                        self.publishPlaybackError(
                            title: "Stream failed",
                            song: self.currentSong,
                            url: failureURL,
                            error: error,
                            technicalDetails: self.playbackFailureDetails(from: item, error: error),
                            recoverySuggestion: self.playbackRecoverySuggestion(for: nsError)
                        )
                    } else {
                        print("❌ Player failed but no error object available")
                        self.publishPlaybackError(
                            title: "Stream failed",
                            song: self.currentSong,
                            url: failureURL,
                            error: nil,
                            technicalDetails: self.playbackFailureDetails(from: item, error: nil),
                            recoverySuggestion: "The player did not provide an error. Try again, or switch streaming quality to a lower bitrate."
                        )
                    }
                    self.schedulePlaybackRetry(reason: "player item failure")
                }
            }
            .store(in: &playerItemCancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self,
                      PlayerItemEventPolicy.shouldHandle(currentItemMatches: self.player.currentItem === item) else {
                    return
                }
                self.handlePlaybackEnded()
            }
            .store(in: &playerItemCancellables)

        item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                guard let self, self.player.currentItem === item else { return }
                if self.isPlaying {
                    self.isBuffering = isEmpty
                }
            }
            .store(in: &playerItemCancellables)

        item.publisher(for: \.loadedTimeRanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.player.currentItem === item else { return }
                self.currentBufferPercent = self.bufferPercent(for: item)
            }
            .store(in: &playerItemCancellables)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] likelyToKeepUp in
                guard let self, self.player.currentItem === item else { return }
                if likelyToKeepUp {
                    self.isBuffering = false
                }
            }
            .store(in: &playerItemCancellables)
    }

    private func bufferPercent(for item: AVPlayerItem) -> Int? {
        let durationSeconds = duration.isFinite && duration > 0 ? duration : item.duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else { return nil }

        let currentSeconds = max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : currentTime)
        let bufferedEnd = item.loadedTimeRanges
            .map(\.timeRangeValue)
            .map { $0.start.seconds + $0.duration.seconds }
            .filter(\.isFinite)
            .max() ?? currentSeconds
        let percent = Int((min(max(bufferedEnd, currentSeconds), durationSeconds) / durationSeconds * 100).rounded())
        return min(max(percent, 0), 100)
    }

    private func publishPlaybackError(
        title: String,
        song: Song?,
        url: URL?,
        error: Error?,
        technicalDetails: String,
        recoverySuggestion: String
    ) {
        let songTitle = song.map { "\"\($0.title)\"" } ?? "the current track"
        let errorText = error.map { "\nError: \($0.localizedDescription)" } ?? ""
        let urlText = url.map { "\nURL: \($0.absoluteString)" } ?? ""
        playbackError = PlaybackErrorInfo(
            title: title,
            message: "Could not play \(songTitle).",
            technicalDetails: technicalDetails + errorText + urlText,
            recoverySuggestion: recoverySuggestion
        )
    }

    private func playbackFailureDetails(from item: AVPlayerItem, error: Error?) -> String {
        var lines: [String] = []
        if let error {
            let nsError = error as NSError
            lines.append("AVFoundation domain: \(nsError.domain)")
            lines.append("AVFoundation code: \(nsError.code)")
            if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                lines.append("Failure reason: \(reason)")
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                lines.append("Underlying domain: \(underlying.domain)")
                lines.append("Underlying code: \(underlying.code)")
            }
        } else {
            lines.append("AVFoundation did not attach an error object to the failed player item.")
        }

        if let accessEvent = item.accessLog()?.events.last {
            lines.append("Server: \(accessEvent.serverAddress ?? "unknown")")
            lines.append("URI: \(accessEvent.uri ?? "unknown")")
            lines.append("Server address changes: \(accessEvent.numberOfServerAddressChanges)")
        }

        if let errorEvent = item.errorLog()?.events.last {
            lines.append("Stream error domain: \(errorEvent.errorDomain)")
            lines.append("Stream status code: \(errorEvent.errorStatusCode)")
            if let comment = errorEvent.errorComment {
                lines.append("Stream comment: \(comment)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func playbackRecoverySuggestion(for error: NSError) -> String {
        switch error.code {
        case -11850:
            return "The stream stopped unexpectedly. Check network reachability to Navidrome, then try again."
        case -11800:
            return "AVFoundation reported an unknown playback failure. Try a lower streaming quality or transcoding to MP3."
        case -1009:
            return "The device appears offline. Reconnect to the network or Tailscale and retry."
        default:
            return "Try again. If this repeats, switch streaming quality to a lower bitrate or verify the server can stream this file."
        }
    }

    private func finishStartingPlayback(_ item: AVPlayerItem, requestedStartTime: TimeInterval, autoplay: Bool) {
        guard player.currentItem === item else { return }
        currentBufferPercent = bufferPercent(for: item)

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
                    DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
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
            publishPlaybackError(
                title: "Playback retry limit reached",
                song: song,
                url: currentPlaybackURL,
                error: nil,
                technicalDetails: "WRhythm retried playback \(attempt) times after \(reason) and stopped retrying.",
                recoverySuggestion: "Try playing the track again. If this repeats, lower streaming quality or verify the source file can be streamed by Navidrome."
            )
            player.pause()
            isBuffering = false
            isPlaying = false
            updateNowPlayingInfo()
            DeviceSyncManager.shared.publishLocalPlaybackStateNow()
            return
        }

        let delay = min(pow(2.0, Double(attempt)), maxPlaybackRetryBackoff)
        let retryStartTime = liveCurrentTime
        let shouldAutoplay = isPlaying
        let intentRevision = playbackIntentRevision
        let retryQueueIDs = queue.map(\.id)
        let retryIndex = currentIndex
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
            guard PlaybackRetryPolicy.shouldRunRetry(
                capturedSongID: song.id,
                currentSongID: self.currentSong?.id,
                capturedIntentRevision: intentRevision,
                currentIntentRevision: self.playbackIntentRevision,
                capturedShouldAutoplay: shouldAutoplay,
                isCurrentlyPlaying: self.isPlaying,
                capturedQueueIDs: retryQueueIDs,
                currentQueueIDs: self.queue.map(\.id),
                capturedIndex: retryIndex,
                currentIndex: self.currentIndex
            ) else {
                self.isBuffering = false
                return
            }
            self.startPlayback(song, startTime: retryStartTime, autoplay: shouldAutoplay)
        }
    }

    private func updateNowPlayingInfo() {
#if os(iOS) || os(watchOS) || os(macOS)
        guard let song = currentSong else {
            nowPlayingArtworkTask?.cancel()
            nowPlayingArtworkTask = nil
            nowPlayingArtworkSongID = nil
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

        if let artwork = nowPlayingArtworkCache[song.id] {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        if let coverArtId = song.coverArt,
           let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
            let artworkSongID = song.id
            guard NowPlayingArtworkLoadPolicy.shouldStartLoad(
                songID: artworkSongID,
                inFlightSongID: nowPlayingArtworkSongID,
                cachedSongIDs: Set(nowPlayingArtworkCache.keys)
            ) else { return }

            nowPlayingArtworkTask?.cancel()
            nowPlayingArtworkSongID = artworkSongID
            nowPlayingArtworkTask = Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: coverURL)
                    try Task.checkCancellation()
                    if let image = PlatformImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        await MainActor.run {
                            guard self.currentSong?.id == artworkSongID else { return }
                            self.nowPlayingArtworkCache[artworkSongID] = artwork
                            if self.nowPlayingArtworkCache.count > self.maxNowPlayingArtworkCacheEntries,
                               let firstKey = self.nowPlayingArtworkCache.keys.first {
                                self.nowPlayingArtworkCache.removeValue(forKey: firstKey)
                            }
                            self.nowPlayingArtworkTask = nil
                            self.nowPlayingArtworkSongID = nil
                            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            if self.nowPlayingArtworkSongID == artworkSongID {
                                self.nowPlayingArtworkTask = nil
                                self.nowPlayingArtworkSongID = nil
                            }
                        }
                        print("Failed to load cover art: \(error)")
                    }
                }
            }
        } else {
            nowPlayingArtworkTask?.cancel()
            nowPlayingArtworkTask = nil
            nowPlayingArtworkSongID = nil
        }
#endif
    }

    @MainActor
    deinit {
        pendingPersistenceTask?.cancel()
        playbackRetryTask?.cancel()
#if os(iOS) || os(watchOS) || os(macOS)
        nowPlayingArtworkTask?.cancel()
#endif
        prebufferTasks.values.forEach { $0.cancel() }
        prebufferTaskTokens.removeAll()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }
}
