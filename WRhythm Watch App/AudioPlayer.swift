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

struct PlaylistGenerationPolicy: Sendable {
    struct Warning: Sendable, Equatable {
        let message: String
        let details: String
    }

    nonisolated static func queue(
        sourceSong: Song,
        primarySongs: [Song],
        fallbackSongs: [Song],
        requestedCount: Int
    ) -> [Song] {
        let targetCount = max(requestedCount, 1)
        var seen = Set<String>()
        var queue: [Song] = []

        func append(_ song: Song) {
            guard queue.count < targetCount, !seen.contains(song.id) else { return }
            seen.insert(song.id)
            queue.append(song)
        }

        append(sourceSong)
        for song in primarySongs where song.id != sourceSong.id {
            append(song)
        }
        for song in fallbackSongs where song.id != sourceSong.id {
            append(song)
        }

        return queue
    }

    nonisolated static func needsFallback(currentCount: Int, requestedCount: Int) -> Bool {
        currentCount < max(requestedCount, 1)
    }

    nonisolated static func shortResultWarning(
        similarCount: Int,
        requestedCount: Int,
        finalCount: Int,
        fallbackCount: Int,
        similarDescription: String = "similar songs"
    ) -> Warning? {
        let targetCount = max(requestedCount, 1)
        guard similarCount < targetCount else { return nil }

        var details = "Requested \(targetCount). The server returned \(similarCount) \(similarDescription)."
        if fallbackCount > 0 {
            details += " Added \(fallbackCount) fallback songs."
        }
        if finalCount < targetCount {
            details += " Generated \(finalCount) total."
        }

        return Warning(
            message: "Only \(similarCount) \(similarDescription) found",
            details: details
        )
    }
}

struct PrebufferSchedulingPolicy: Sendable {
    static func upcomingRange(queueCount: Int, currentIndex: Int, aheadCount: Int) -> Range<Int> {
        guard aheadCount > 0, queueCount > 0 else { return 0..<0 }
        let start = min(max(currentIndex + 1, 0), queueCount)
        let end = min(queueCount, start + aheadCount)
        return start..<end
    }

    static func previousRange(queueCount: Int, currentIndex: Int, keepCount: Int) -> Range<Int> {
        guard keepCount > 0, currentIndex > 0, queueCount > 0 else { return 0..<0 }
        let end = min(currentIndex, queueCount)
        let start = max(0, end - keepCount)
        return start..<end
    }

    static func upcomingKeys(queueKeys: [String], currentIndex: Int, aheadCount: Int) -> [String] {
        let range = upcomingRange(queueCount: queueKeys.count, currentIndex: currentIndex, aheadCount: aheadCount)
        guard !range.isEmpty else { return [] }
        return Array(queueKeys[range])
    }

    static func previousKeys(queueKeys: [String], currentIndex: Int, keepCount: Int) -> [String] {
        let range = previousRange(queueCount: queueKeys.count, currentIndex: currentIndex, keepCount: keepCount)
        guard !range.isEmpty else { return [] }
        return Array(queueKeys[range])
    }

    static func desiredKeys(
        currentKey: String?,
        upcomingKeys: [String],
        previousKeys: [String] = []
    ) -> Set<String> {
        var keys = Set(upcomingKeys)
        keys.formUnion(previousKeys)
        if let currentKey {
            keys.insert(currentKey)
        }
        return keys
    }

    static func orderedCandidateKeys(
        currentKey: String?,
        upcomingKeys: [String],
        previousKeys: [String] = []
    ) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for key in ([currentKey].compactMap { $0 } + upcomingKeys + previousKeys) where !seen.contains(key) {
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

struct PrebufferOwnershipPolicy: Sendable {
    static func shouldSchedule(isLocalPlaybackOutput: Bool) -> Bool {
        isLocalPlaybackOutput
    }
}

struct PrebufferCachePruningPolicy: Sendable {
    static func shouldRemove(filename: String, keepFilenames: Set<String>) -> Bool {
        guard !filename.hasSuffix(".download") else { return false }
        guard !filename.hasSuffix(".json") else { return false }
        return !keepFilenames.contains(filename)
    }
}

struct PersistedPrebufferRecord: Codable, Sendable {
    let key: String
    let filename: String
    let song: Song
    let qualityLabel: String
    let updatedAt: Date
}

struct PrebufferManifestPolicy: Sendable {
    static func restorableRecords(
        records: [PersistedPrebufferRecord],
        existingFilenames: Set<String>
    ) -> [PersistedPrebufferRecord] {
        var recordsByKey: [String: PersistedPrebufferRecord] = [:]
        for record in records where existingFilenames.contains(record.filename) {
            if let existing = recordsByKey[record.key], existing.updatedAt >= record.updatedAt {
                continue
            }
            recordsByKey[record.key] = record
        }

        return recordsByKey.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.song.title.localizedCaseInsensitiveCompare(rhs.song.title) == .orderedAscending
        }
    }
}

struct PrebufferRetryPolicy: Sendable {
    static let maxRetryDelay: TimeInterval = 30
    static let maxRetryAttempts = 6
    static let jitterRange: ClosedRange<Double> = 0.8...1.2
    static let cooldownFailureThreshold = 4
    static let cooldownWindow: TimeInterval = 45
    static let cooldownDuration: TimeInterval = 20

    static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attempt))), maxRetryDelay)
    }

    static func retryDelay(forAttempt attempt: Int, key: String) -> TimeInterval {
        let baseDelay = retryDelay(forAttempt: attempt)
        guard baseDelay < maxRetryDelay else { return maxRetryDelay }
        return min(baseDelay * jitterMultiplier(for: key, attempt: attempt), maxRetryDelay)
    }

    static func shouldRetry(afterAttempt attempt: Int) -> Bool {
        attempt < maxRetryAttempts
    }

    static func recentFailures(
        from failureDates: [Date],
        now: Date
    ) -> [Date] {
        failureDates.filter { now.timeIntervalSince($0) <= cooldownWindow }
    }

    static func shouldEnterCooldown(
        recentFailureDates: [Date],
        now: Date
    ) -> Bool {
        recentFailures(from: recentFailureDates, now: now).count >= cooldownFailureThreshold
    }

    private static func jitterMultiplier(for key: String, attempt: Int) -> Double {
        let seed = key.unicodeScalars.reduce(UInt64(attempt + 1)) { partial, scalar in
            ((partial &* 1_099_511_628_211) &+ UInt64(scalar.value)) & 0xFFFF_FFFF
        }
        let normalized = Double(seed % 10_000) / 10_000
        return jitterRange.lowerBound + ((jitterRange.upperBound - jitterRange.lowerBound) * normalized)
    }
}

enum WRhythmLogRedactor {
    private static let sensitiveQueryNames: Set<String> = [
        "u",
        "p",
        "s",
        "t",
        "token",
        "password",
    ]

    static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return redactSensitiveURLData(in: url.absoluteString)
        }
        components.queryItems = components.queryItems?.map { item in
            guard sensitiveQueryNames.contains(item.name.lowercased()) else { return item }
            return URLQueryItem(name: item.name, value: "<redacted>")
        }
        return components.string ?? redactSensitiveURLData(in: url.absoluteString)
    }

    static func redactedURLString(_ string: String) -> String {
        if let url = URL(string: string), url.scheme != nil {
            return redacted(url)
        }
        return redactSensitiveURLData(in: string)
    }

    static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["\(nsError.domain) \(nsError.code): \(error.localizedDescription)"]
        if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            parts.append("URL: \(redacted(failingURL))")
        } else if let failingURLString = nsError.userInfo["NSErrorFailingURLStringKey"] as? String {
            parts.append("URL: \(redactedURLString(failingURLString))")
        }
        return parts.joined(separator: " ")
    }

    static func redactSensitiveURLData(in text: String) -> String {
        var redacted = text
        for name in sensitiveQueryNames {
            let pattern = "([?&]\(NSRegularExpression.escapedPattern(for: name))=)[^&\\s]+"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                options: [],
                range: range,
                withTemplate: "$1<redacted>"
            )
        }
        return redacted
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
        previousReadyCount: Int,
        previousTargetCount: Int,
        nextReadyCount: Int,
        nextTargetCount: Int,
        activeCount: Int,
        activePercent: Int?,
        playerIsBuffering: Bool,
        playerBufferPercent: Int?
    ) -> String? {
        var parts: [String] = []
        if previousReadyCount > 0 || nextReadyCount > 0 || previousTargetCount > 0 || nextTargetCount > 0 {
            parts.append(availabilityLabel(readyCount: previousReadyCount, targetCount: previousTargetCount, suffix: "prev available"))
            parts.append(availabilityLabel(readyCount: nextReadyCount, targetCount: nextTargetCount, suffix: "next available"))
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

    private static func availabilityLabel(readyCount: Int, targetCount: Int, suffix: String) -> String {
        guard targetCount > 0, readyCount != targetCount else {
            return "\(readyCount) \(suffix)"
        }
        return "\(readyCount)/\(targetCount) \(suffix)"
    }
}

struct PrebufferQualityPresentationPolicy: Sendable {
    static func downloadedQualityLabel(downloadedBitRate: Int) -> String {
        downloadedBitRate == AudioQuality.original.downloadedBitRate ? "Original" : "\(downloadedBitRate) kbps"
    }

    static func streamingQualityLabel(
        streamingQuality: StreamingQuality,
        transcodesToMP3: Bool,
        contentType: String? = nil,
        suffix: String? = nil
    ) -> String {
        if transcodesToMP3 {
            let bitRate = streamingQuality.maxBitRate ?? StreamingQuality.max.rawValue
            if streamingQuality == .original {
                return "MP3 fallback \(bitRate) kbps"
            }
            return "\(bitRate) kbps"
        }
        guard let codec = codecLabel(contentType: contentType, suffix: suffix) else {
            return "Original"
        }
        return "\(codec) original"
    }

    private static func codecLabel(contentType: String?, suffix: String?) -> String? {
        let normalizedContentType = contentType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSuffix = suffix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedContentType?.contains("flac") == true || normalizedSuffix == "flac" {
            return "FLAC"
        }
        if normalizedContentType?.contains("mpeg") == true ||
            normalizedContentType?.contains("mp3") == true ||
            normalizedSuffix == "mp3" {
            return "MP3"
        }
        if normalizedContentType?.contains("ogg") == true ||
            normalizedSuffix == "ogg" ||
            normalizedSuffix == "oga" {
            return "Ogg"
        }
        if normalizedContentType?.contains("aac") == true || normalizedSuffix == "aac" {
            return "AAC"
        }
        if normalizedContentType?.contains("mp4") == true ||
            normalizedSuffix == "m4a" ||
            normalizedSuffix == "mp4" {
            return "AAC"
        }
        if normalizedContentType?.contains("wav") == true || normalizedSuffix == "wav" {
            return "WAV"
        }
        if normalizedContentType?.contains("aiff") == true ||
            normalizedSuffix == "aiff" ||
            normalizedSuffix == "aif" {
            return "AIFF"
        }
        if normalizedContentType?.contains("alac") == true || normalizedSuffix == "alac" {
            return "ALAC"
        }
        return normalizedSuffix?.uppercased()
    }
}

struct PlaybackFormatPolicy: Sendable {
    nonisolated static func effectiveSuffix(suffix: String?, path: String?) -> String? {
        if let suffix = normalized(suffix), !suffix.isEmpty {
            return suffix
        }
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        let extensionName = (path as NSString).pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return extensionName.isEmpty ? nil : extensionName
    }

    nonisolated static func isMP3(contentType: String?, suffix: String?, path: String?) -> Bool {
        let normalizedContentType = normalized(contentType)
        let effectiveSuffix = effectiveSuffix(suffix: suffix, path: path)
        return normalizedContentType?.contains("mpeg") == true ||
            normalizedContentType?.contains("mp3") == true ||
            effectiveSuffix == "mp3"
    }

    nonisolated static func isFormatSupportedNatively(contentType: String?, suffix: String?, path: String?) -> Bool {
#if os(watchOS)
        let supportedTypes = ["audio/mpeg", "audio/mp3", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/wav", "audio/x-wav", "audio/aiff", "audio/x-aiff"]
        let supportedSuffixes = ["mp3", "aac", "m4a", "mp4", "wav", "aiff", "aif"]
#else
        let supportedTypes = ["audio/mpeg", "audio/mp3", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/wav", "audio/x-wav", "audio/aiff", "audio/x-aiff", "audio/flac", "audio/x-flac", "audio/alac", "audio/x-alac"]
        let supportedSuffixes = ["mp3", "aac", "m4a", "mp4", "wav", "aiff", "aif", "flac", "alac"]
#endif

        if let contentType = normalized(contentType),
           supportedTypes.contains(where: { contentType.contains($0) }) {
            return true
        }

        guard let suffix = effectiveSuffix(suffix: suffix, path: path) else { return false }
        return supportedSuffixes.contains(suffix)
    }

    nonisolated static func playbackMimeType(contentType: String?, suffix: String?, url: URL) -> String? {
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
            break
        }

        if let contentType = normalized(contentType) {
            return contentType
        }

        switch effectiveSuffix(suffix: suffix, path: nil) {
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
            return nil
        }
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct PrebufferPlaybackSelectionPolicy: Sendable {
    static func shouldUseCachedPrebuffer(
        songContentType: String?,
        songSuffix: String?,
        songPath: String?,
        streamingQuality: StreamingQuality,
        cachedFileExtension: String,
        qualityLabel: String?
    ) -> Bool {
        let freshPlaybackTranscodes = streamingQuality != .original ||
            !PlaybackFormatPolicy.isFormatSupportedNatively(
                contentType: songContentType,
                suffix: songSuffix,
                path: songPath
            )
        guard streamingQuality == .original, !freshPlaybackTranscodes else {
            return true
        }

        if qualityLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("mp3 fallback") == true {
            return false
        }

        let cachedExtension = cachedFileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if cachedExtension == "mp3",
           !PlaybackFormatPolicy.isMP3(contentType: songContentType, suffix: songSuffix, path: songPath) {
            return false
        }

        return true
    }
}

struct PlaybackQualityPresentationPolicy: Sendable {
    enum Source: Sendable {
        case local
        case streaming

        var label: String {
            switch self {
            case .local:
                return "Local"
            case .streaming:
                return "Streaming"
            }
        }
    }

    static func statusText(source: Source, qualityLabel: String?) -> String {
        let trimmed = qualityLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let quality = if let trimmed, !trimmed.isEmpty {
            trimmed
        } else {
            "Unknown"
        }
        return "\(source.label): \(quality)"
    }
}

struct PrebufferAvailabilityPresentationPolicy: Sendable {
    static func orderedAvailableSongs(queuedSongs: [Song], preparedSongs: [Song]) -> [Song] {
        var seen = Set<String>()
        var songs: [Song] = []
        for song in queuedSongs {
            guard preparedSongs.contains(where: { $0.id == song.id }), !seen.contains(song.id) else { continue }
            seen.insert(song.id)
            songs.append(song)
        }
        let lingeringSongs = preparedSongs
            .filter { !seen.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        for song in lingeringSongs where !seen.contains(song.id) {
            seen.insert(song.id)
            songs.append(song)
        }
        return songs
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
        desiredKeys _: Set<String>,
        activeTaskKeys: Set<String>,
        capturedToken: String,
        activeToken: String?
    ) -> Bool {
        activeTaskKeys.contains(key) && activeToken == capturedToken
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
    @Published private(set) var lastPauseReason: String?
    @Published private(set) var currentBufferPercent: Int?
    @Published private(set) var playbackError: PlaybackErrorInfo?
    @Published private(set) var currentPlaybackQualitySummary: String?
    @Published private(set) var prebufferedTrackCount = 0
    @Published private(set) var prebufferedSongs: [Song] = []
    @Published private(set) var retainedPrebufferedSongs: [Song] = []
    @Published private(set) var availablePrebufferedSongs: [Song] = []
    @Published private(set) var availablePrebufferedTrackQualityLabels: [String: String] = [:]
    @Published private(set) var prebufferDownloadStatuses: [PrebufferDownloadStatus] = []
    @Published private(set) var isKeepingAvailableTracks = false
    @Published private(set) var prebufferingTrackCount = 0
    @Published private(set) var prebufferingProgressPercent: Int?
    @Published private(set) var availableTracksQueueRestoreAvailable = false
    @Published var queue: [Song] = []
    @Published var currentIndex: Int = 0
    @Published var playlistGenQueue: [Song] = []
    @Published var playlistGenSourceTitle: String?
    @Published var playlistGenSourceArtist: String?
    @Published private(set) var playlistGenIsGenerating = false
    @Published private(set) var playlistGenGeneratingTitle: String?
    @Published private(set) var playlistGenErrorMessage: String?
    @Published private(set) var playlistGenErrorDetails: String?
    @Published private(set) var playlistGenWarningMessage: String?
    @Published private(set) var playlistGenWarningDetails: String?
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
        let song: Song
        let url: URL
        let asset: AVURLAsset
        let qualityLabel: String
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

    private struct AvailableTracksQueueRestoreState {
        let queue: [Song]
        let currentIndex: Int
        let currentSong: Song?
        let currentTime: TimeInterval
        let duration: TimeInterval
        let wasPlaying: Bool
        let isShuffled: Bool
        let originalQueue: [Song]
        let originalIndex: Int
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

    private struct PlaylistGenerationResult: Sendable {
        let songs: [Song]
        let warning: PlaylistGenerationPolicy.Warning?

        nonisolated static func songs(
            _ songs: [Song],
            warning: PlaylistGenerationPolicy.Warning? = nil
        ) -> PlaylistGenerationResult {
            PlaylistGenerationResult(songs: songs, warning: warning)
        }
    }

    private static let persistedPlaybackStateKey = "audioPlayerPersistedPlaybackState.v1"
    private static let persistedPlaybackVersion = 1
    private static let prebufferManifestFilename = "prebufferManifest.v1.json"

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
    private var lastObservedPrebufferAheadCount: Int?
    private var lastObservedPreviousPrebufferCount: Int?
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
    private var keepAvailableTracksTask: Task<Void, Never>?
    private var playbackIntentRevision = 0
    private var playlistGenTask: Task<Void, Never>?
    private var playlistGenRestoreState: PlaylistGenRestoreState?
    private var availableTracksQueueRestoreState: AvailableTracksQueueRestoreState? {
        didSet {
            availableTracksQueueRestoreAvailable = availableTracksQueueRestoreState != nil
        }
    }
    private var scrobbleTracker = ScrobbleProgressTracker()
    private var recentlyPlayedTracker = ScrobbleProgressTracker()
    private let maxPlaybackRetryAttempts = 4
    private let maxPlaybackRetryBackoff: TimeInterval = 30
    private var prebufferRetryAttemptsByKey: [String: Int] = [:]
    private var prebufferRetryTasksByKey: [String: Task<Void, Never>] = [:]
    private var exhaustedPrebufferRetryKeys: Set<String> = []
    private var recentPrebufferFailureDates: [Date] = []
    private var prebufferRetryCooldownUntil: Date?
    private var prebufferCooldownWakeTask: Task<Void, Never>?
    private var allowsQueuePrebuffering = true
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
        restorePersistedPrebufferManifest()
        setupPlaybackPersistence()
        observePrebufferSettingsChanges()
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
            previousReadyCount: retainedPrebufferedSongs.count,
            previousTargetCount: previousPrebufferTargetCount,
            nextReadyCount: prebufferedSongs.count,
            nextTargetCount: nextPrebufferTargetCount,
            activeCount: prebufferingTrackCount,
            activePercent: prebufferingProgressPercent,
            playerIsBuffering: isBuffering,
            playerBufferPercent: currentBufferPercent
        )
    }

    private var previousPrebufferTargetCount: Int {
        guard !queue.isEmpty else { return 0 }
        return PrebufferSchedulingPolicy.previousRange(
            queueCount: queue.count,
            currentIndex: currentIndex,
            keepCount: retainPreviousPrebufferCount
        ).count
    }

    private var nextPrebufferTargetCount: Int {
        guard !queue.isEmpty else { return 0 }
        return PrebufferSchedulingPolicy.upcomingRange(
            queueCount: queue.count,
            currentIndex: currentIndex,
            aheadCount: prebufferAheadCount
        ).count
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

    private func beginRecentlyPlayedTracking(for song: Song, startTime: TimeInterval) {
        _ = recentlyPlayedTracker.start(songID: song.id, currentTime: startTime, now: Date())
    }

    private func updateRecentlyPlayedTracking() {
        guard let song = currentSong else {
            recentlyPlayedTracker.reset()
            return
        }

        let effectiveDuration = duration > 0 ? duration : TimeInterval(song.duration ?? 0)
        guard let event = recentlyPlayedTracker.update(
            songID: song.id,
            currentTime: liveCurrentTime,
            duration: effectiveDuration,
            isPlaying: isPlaying,
            now: Date()
        ) else { return }

        if case .submission(let songID) = event,
           let song = songForRecentlyPlayedHistory(songID: songID) {
            RecentlyPlayedStore.shared.record(song: song)
        }
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

    private func songForRecentlyPlayedHistory(songID: String) -> Song? {
        if currentSong?.id == songID {
            return currentSong
        }
        if let queueSong = queue.first(where: { $0.id == songID }) {
            return queueSong
        }
        if let playlistGenSong = playlistGenQueue.first(where: { $0.id == songID }) {
            return playlistGenSong
        }
        return nil
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

    private func observePrebufferSettingsChanges() {
        lastObservedPrebufferAheadCount = prebufferAheadCount
        lastObservedPreviousPrebufferCount = retainPreviousPrebufferCount

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                let aheadCount = self.prebufferAheadCount
                let previousCount = self.retainPreviousPrebufferCount
                guard aheadCount != self.lastObservedPrebufferAheadCount ||
                    previousCount != self.lastObservedPreviousPrebufferCount else {
                    return
                }

                self.lastObservedPrebufferAheadCount = aheadCount
                self.lastObservedPreviousPrebufferCount = previousCount
                self.scheduleQueuePrebuffer()
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
        availableTracksQueueRestoreState = nil
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
        availableTracksQueueRestoreState = nil
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

    func playAvailableTracksQueue(_ songs: [Song], startingAt index: Int = 0) {
        guard !songs.isEmpty, songs.indices.contains(index) else { return }
        if availableTracksQueueRestoreState == nil {
            availableTracksQueueRestoreState = AvailableTracksQueueRestoreState(
                queue: queue,
                currentIndex: currentIndex,
                currentSong: currentSong,
                currentTime: liveCurrentTime,
                duration: duration,
                wasPlaying: isPlaying,
                isShuffled: isShuffled,
                originalQueue: originalQueue,
                originalIndex: originalIndex,
                playlistGenQueue: playlistGenQueue,
                playlistGenSourceTitle: playlistGenSourceTitle,
                playlistGenSourceArtist: playlistGenSourceArtist
            )
        }

        recordQueueIntentChange()
        isShuffled = false
        originalQueue = []
        originalIndex = 0
        queue = songs
        currentIndex = index
        queueFinished = false
        startPlayback(songs[index])
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: true)
    }

    func restoreQueueBeforeAvailableTracks() {
        guard let state = availableTracksQueueRestoreState else { return }
        availableTracksQueueRestoreState = nil

        recordQueueIntentChange()
        queue = state.queue
        currentIndex = min(max(state.currentIndex, 0), max(state.queue.count - 1, 0))
        currentSong = state.currentSong
        currentTime = state.currentTime
        duration = state.duration
        isShuffled = state.isShuffled
        originalQueue = state.originalQueue
        originalIndex = state.originalIndex
        playlistGenQueue = state.playlistGenQueue
        playlistGenSourceTitle = state.playlistGenSourceTitle
        playlistGenSourceArtist = state.playlistGenSourceArtist
        queueFinished = false

        guard let song = state.currentSong else {
            pause()
            DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: false)
            return
        }

        startPlayback(song, startTime: state.currentTime, autoplay: state.wasPlaying)
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: state.wasPlaying)
    }

    func playGeneratedPlaylist(sourceSong: Song, songs: [Song], startingAt index: Int = 0) {
        playGeneratedPlaylist(
            sourceTitle: sourceSong.title,
            sourceArtist: sourceSong.artist,
            songs: songs,
            startingAt: index
        )
    }

    func playGeneratedPlaylist(
        sourceTitle: String,
        sourceArtist: String?,
        songs: [Song],
        startingAt index: Int = 0,
        warning: PlaylistGenerationPolicy.Warning? = nil
    ) {
        guard !songs.isEmpty else { return }
        playlistGenTask?.cancel()
        playlistGenTask = nil
        playlistGenRestoreState = nil
        playlistGenIsGenerating = false
        playlistGenGeneratingTitle = nil
        playlistGenErrorMessage = nil
        playlistGenErrorDetails = nil
        playlistGenWarningMessage = warning?.message
        playlistGenWarningDetails = warning?.details
        playlistGenSourceTitle = sourceTitle
        playlistGenSourceArtist = sourceArtist
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
        playlistGenWarningMessage = nil
        playlistGenWarningDetails = nil
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
        startPlaylistGeneration(title: sourceSong.title, artist: sourceSong.artist) {
            let requestedCount = max(count, 1)
            let api = await NavidromeAPI.shared
            let cachedSonicSupport = await api.sonicSimilaritySupported
            let sonicSupported: Bool
            if let cachedSonicSupport {
                sonicSupported = cachedSonicSupport
            } else {
                sonicSupported = await api.checkSonicSimilaritySupport()
            }
            var sonicFailure: Error?

            if sonicSupported {
                do {
                    let sonicSongs = try await api.getSonicSimilarTracks(songId: sourceSong.id, count: requestedCount)
                    let primaryQueue = PlaylistGenerationPolicy.queue(
                        sourceSong: sourceSong,
                        primarySongs: sonicSongs,
                        fallbackSongs: [],
                        requestedCount: requestedCount
                    )

                    var fallbackSongs: [Song] = []
                    if fallbackToRandom, PlaylistGenerationPolicy.needsFallback(currentCount: primaryQueue.count, requestedCount: requestedCount) {
                        fallbackSongs = try await api.getRandomSongs(size: requestedCount)
                    }

                    let queue = PlaylistGenerationPolicy.queue(
                        sourceSong: sourceSong,
                        primarySongs: sonicSongs,
                        fallbackSongs: fallbackSongs,
                        requestedCount: requestedCount
                    )
                    guard queue.count > 1 else {
                        throw PlaylistGenerationError.noSongs
                    }

                    let warning = PlaylistGenerationPolicy.shortResultWarning(
                        similarCount: primaryQueue.count,
                        requestedCount: requestedCount,
                        finalCount: queue.count,
                        fallbackCount: max(queue.count - primaryQueue.count, 0),
                        similarDescription: "sonic-similar tracks"
                    )
                    return .songs(queue, warning: warning)
                } catch {
                    sonicFailure = error
                    print("⚠️ Sonic similarity playlist gen failed, falling back to artist similarity: \(error.localizedDescription)")
                }
            }

            let privateSonicSupported: Bool
            if UserDefaults.standard.bool(forKey: "experimentalAudioMuseFeaturesEnabled") {
                if let cachedPrivateSonicSupport = await api.audioMusePrivateSonicSupported {
                    privateSonicSupported = cachedPrivateSonicSupport
                } else {
                    privateSonicSupported = await api.checkAudioMuseFeatureSupport(.privateSonic)
                }
            } else {
                privateSonicSupported = false
            }

            if privateSonicSupported {
                do {
                    let privateSonicSongs = try await api.getAudioMusePrivateSimilarSongs(songId: sourceSong.id, count: requestedCount)
                    let primaryQueue = PlaylistGenerationPolicy.queue(
                        sourceSong: sourceSong,
                        primarySongs: privateSonicSongs,
                        fallbackSongs: [],
                        requestedCount: requestedCount
                    )

                    var fallbackSongs: [Song] = []
                    if fallbackToRandom, PlaylistGenerationPolicy.needsFallback(currentCount: primaryQueue.count, requestedCount: requestedCount) {
                        fallbackSongs = try await api.getRandomSongs(size: requestedCount)
                    }

                    let queue = PlaylistGenerationPolicy.queue(
                        sourceSong: sourceSong,
                        primarySongs: privateSonicSongs,
                        fallbackSongs: fallbackSongs,
                        requestedCount: requestedCount
                    )
                    guard queue.count > 1 else {
                        throw PlaylistGenerationError.noSongs
                    }

                    let warning = PlaylistGenerationPolicy.shortResultWarning(
                        similarCount: primaryQueue.count,
                        requestedCount: requestedCount,
                        finalCount: queue.count,
                        fallbackCount: max(queue.count - primaryQueue.count, 0),
                        similarDescription: "AudioMuse sonic tracks"
                    )
                    return .songs(queue, warning: warning)
                } catch {
                    sonicFailure = error
                    print("⚠️ AudioMuse private sonic playlist gen failed, falling back to artist similarity: \(error.localizedDescription)")
                }
            }

            let similarSongs = try await api.getSimilarSongsForSong(sourceSong, count: requestedCount)
            var fallbackSongs: [Song] = []
            let primaryQueue = PlaylistGenerationPolicy.queue(
                sourceSong: sourceSong,
                primarySongs: similarSongs,
                fallbackSongs: [],
                requestedCount: requestedCount
            )
            if fallbackToRandom, PlaylistGenerationPolicy.needsFallback(currentCount: primaryQueue.count, requestedCount: requestedCount) {
                fallbackSongs = try await NavidromeAPI.shared.getRandomSongs(size: requestedCount)
            }

            let queue = PlaylistGenerationPolicy.queue(
                sourceSong: sourceSong,
                primarySongs: similarSongs,
                fallbackSongs: fallbackSongs,
                requestedCount: requestedCount
            )
            guard queue.count > 1 else {
                throw PlaylistGenerationError.noSongs
            }

            let warning = PlaylistGenerationPolicy.shortResultWarning(
                similarCount: primaryQueue.count,
                requestedCount: requestedCount,
                finalCount: queue.count,
                fallbackCount: max(queue.count - primaryQueue.count, 0),
                similarDescription: "artist-similar songs"
            )
            if let warning {
                if let sonicFailure {
                    return .songs(
                        queue,
                        warning: PlaylistGenerationPolicy.Warning(
                            message: warning.message,
                            details: "Sonic similarity failed: \(sonicFailure.localizedDescription). \(warning.details)"
                        )
                    )
                }
                return .songs(queue, warning: warning)
            }
            if let sonicFailure {
                return .songs(
                    queue,
                    warning: PlaylistGenerationPolicy.Warning(
                        message: "Used artist similarity fallback",
                        details: "Sonic similarity failed: \(sonicFailure.localizedDescription)"
                    )
                )
            }
            return .songs(queue)
        }
    }

    func startSonicSimilarityPlaylistGeneration(for sourceSong: Song, count: Int = 100) {
        startPlaylistGeneration(title: sourceSong.title, artist: sourceSong.artist) {
            let requestedCount = max(count, 1)
            let api = await NavidromeAPI.shared
            let songs: [Song]
            if await api.sonicSimilaritySupported == true {
                songs = try await api.getSonicSimilarTracks(songId: sourceSong.id, count: requestedCount)
            } else if UserDefaults.standard.bool(forKey: "experimentalAudioMuseFeaturesEnabled"),
                      await api.audioMusePrivateSonicSupported == true {
                songs = try await api.getAudioMusePrivateSimilarSongs(songId: sourceSong.id, count: requestedCount)
            } else {
                songs = try await api.getSonicSimilarTracks(songId: sourceSong.id, count: requestedCount)
            }
            let queue = PlaylistGenerationPolicy.queue(
                sourceSong: sourceSong,
                primarySongs: songs,
                fallbackSongs: [],
                requestedCount: requestedCount
            )
            guard queue.count > 1 else {
                throw PlaylistGenerationError.noSongs
            }
            return .songs(queue)
        }
    }

    func startSonicPathPlaylistGeneration(from startSong: Song, to endSong: Song, count: Int = 100) {
        let title = "Sonic Path"
        let artist = "\(startSong.title) -> \(endSong.title)"
        startPlaylistGeneration(title: title, artist: artist) {
            let api = await NavidromeAPI.shared
            let songs: [Song]
            if await api.sonicSimilaritySupported == true {
                songs = try await api.findSonicPath(
                    startSongId: startSong.id,
                    endSongId: endSong.id,
                    count: max(count, 2)
                )
            } else if UserDefaults.standard.bool(forKey: "experimentalAudioMuseFeaturesEnabled"),
                      await api.audioMusePrivateSonicSupported == true {
                songs = try await api.findAudioMusePrivateSongPath(
                    startSongId: startSong.id,
                    endSongId: endSong.id
                )
            } else {
                songs = try await api.findSonicPath(
                    startSongId: startSong.id,
                    endSongId: endSong.id,
                    count: max(count, 2)
                )
            }
            guard !songs.isEmpty else {
                throw PlaylistGenerationError.noSongs
            }
            return .songs(songs)
        }
    }

    func startAudioMuseAlchemyPlaylistGeneration(for sourceSong: Song, count: Int = 100) {
        startAudioMuseAlchemyPlaylistGeneration(
            seeds: [.song(sourceSong)],
            count: count
        )
    }

    func startAudioMuseAlchemyPlaylistGeneration(seeds: [AudioMuseAlchemySeed], count: Int = 100) {
        let sourceTitle = seeds.first?.title ?? "AudioMuse Alchemy"
        let sourceDetail: String
        if seeds.count <= 1 {
            sourceDetail = seeds.first?.subtitle ?? "1 seed"
        } else {
            sourceDetail = "\(seeds.count) seeds"
        }

        startPlaylistGeneration(title: sourceTitle, artist: sourceDetail) {
            let requestedCount = max(count, 1)
            let songs = try await NavidromeAPI.shared.getAudioMuseAlchemySongs(
                seeds: seeds,
                count: requestedCount
            )
            let queue = Array(songs.prefix(requestedCount))
            guard !queue.isEmpty else {
                throw PlaylistGenerationError.noSongs
            }
            return .songs(queue)
        }
    }

    func startAudioMuseRadioPlaylistGeneration(radio: AudioMuseRadioStation, count: Int = 200) {
        startPlaylistGeneration(title: radio.name, artist: "AudioMuse Radio") {
            let requestedCount = max(count, 1)
            let songs = try await NavidromeAPI.shared.getAudioMuseRadioSongs(
                id: radio.id,
                count: requestedCount
            )
            let queue = Array(songs.prefix(requestedCount))
            guard !queue.isEmpty else {
                throw PlaylistGenerationError.noSongs
            }
            return .songs(queue)
        }
    }

    private func startPlaylistGeneration(
        title: String,
        artist: String?,
        generateSongs: @escaping @Sendable () async throws -> PlaylistGenerationResult
    ) {
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
        playlistGenGeneratingTitle = title
        playlistGenErrorMessage = nil
        playlistGenErrorDetails = nil
        playlistGenWarningMessage = nil
        playlistGenWarningDetails = nil
        playlistGenQueue = []
        playlistGenSourceTitle = title
        playlistGenSourceArtist = artist

        pause()
        DeviceSyncManager.shared.broadcastLocalQueueAsShared(intendedIsPlaying: false)
#if os(macOS)
        NotificationCenter.default.post(name: .wrhythmShowPlaylistGen, object: nil)
#endif

        playlistGenTask = Task { [weak self] in
            do {
                let generationResult = try await generateSongs()
                try Task.checkCancellation()

                await MainActor.run {
                    guard let self, self.playlistGenIsGenerating else { return }
                    self.playlistGenTask = nil
                    self.playGeneratedPlaylist(
                        sourceTitle: title,
                        sourceArtist: artist,
                        songs: generationResult.songs,
                        warning: generationResult.warning
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.playlistGenTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.handlePlaylistGenerationFailure(error, sourceTitle: title)
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
        availableTracksQueueRestoreState = nil
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

    @discardableResult
    func clearQueue() -> Bool {
        guard !queue.isEmpty else { return false }
        recordQueueIntentChange()
        queue = []
        currentIndex = 0
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
        PlaybackFormatPolicy.isFormatSupportedNatively(contentType: contentType, suffix: suffix, path: nil)
    }

    private func isFormatSupportedNatively(_ song: Song) -> Bool {
        PlaybackFormatPolicy.isFormatSupportedNatively(
            contentType: song.contentType,
            suffix: song.suffix,
            path: song.path
        )
    }

    private func effectiveSuffix(for song: Song) -> String? {
        PlaybackFormatPolicy.effectiveSuffix(suffix: song.suffix, path: song.path)
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

    private var prebufferManifestURL: URL {
        prebufferDirectory.appendingPathComponent(Self.prebufferManifestFilename, isDirectory: false)
    }

    private func shouldTranscodeForPlayback(_ song: Song) -> Bool {
        let streamingQuality = StreamingQuality.current
        return streamingQuality != .original || !isFormatSupportedNatively(song)
    }

    private func streamURLForPlayback(_ song: Song) -> URL? {
        if shouldTranscodeForPlayback(song) {
            let bitRate = StreamingQuality.current.maxBitRate ?? StreamingQuality.max.rawValue
            return NavidromeAPI.shared.getStreamURL(id: song.id, format: "mp3", maxBitRate: bitRate)
        }

        return NavidromeAPI.shared.getStreamURL(id: song.id)
    }

    private func prebufferQualityLabel(for song: Song) -> String {
        PrebufferQualityPresentationPolicy.streamingQualityLabel(
            streamingQuality: StreamingQuality.current,
            transcodesToMP3: shouldTranscodeForPlayback(song),
            contentType: song.contentType,
            suffix: effectiveSuffix(for: song)
        )
    }

    private func downloadedQualityLabel(for song: Song) -> String? {
        guard let downloadedSong = DownloadManager.shared.downloadedSongs[song.id] else { return nil }
        return PrebufferQualityPresentationPolicy.downloadedQualityLabel(downloadedBitRate: downloadedSong.downloadedBitRate)
    }

    private func makePlaybackQualitySummary(source: PlaybackQualityPresentationPolicy.Source, qualityLabel: String?) -> String {
        PlaybackQualityPresentationPolicy.statusText(source: source, qualityLabel: qualityLabel)
    }

    private func prebufferKey(for song: Song) -> String {
        "\(song.id)|q\(StreamingQuality.current.rawValue)"
    }

    private func sanitizedPrebufferFilename(for song: Song) -> String {
        let key = prebufferKey(for: song)
        let safeKey = key.map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let extensionName = shouldTranscodeForPlayback(song) ? "mp3" : (effectiveSuffix(for: song) ?? "audio")
        return "\(String(safeKey)).\(extensionName)"
    }

    private func prebufferURL(for song: Song) -> URL {
        prebufferDirectory.appendingPathComponent(sanitizedPrebufferFilename(for: song))
    }

    private func prebufferRecord(for key: String, prebuffer: PreparedPrebuffer) -> PersistedPrebufferRecord? {
        let prebufferDirectory = prebufferDirectory.standardizedFileURL
        let fileDirectory = prebuffer.url.deletingLastPathComponent().standardizedFileURL
        guard fileDirectory == prebufferDirectory else { return nil }
        return PersistedPrebufferRecord(
            key: key,
            filename: prebuffer.url.lastPathComponent,
            song: prebuffer.song,
            qualityLabel: prebuffer.qualityLabel,
            updatedAt: Date()
        )
    }

    private func savePrebufferManifest() {
        let records = preparedPrebuffers.compactMap { key, prebuffer in
            prebufferRecord(for: key, prebuffer: prebuffer)
        }
            .sorted { lhs, rhs in lhs.song.title.localizedCaseInsensitiveCompare(rhs.song.title) == .orderedAscending }
        guard !records.isEmpty else {
            try? FileManager.default.removeItem(at: prebufferManifestURL)
            return
        }

        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: prebufferManifestURL, options: .atomic)
        } catch {
            print("⚠️ Failed to save prebuffer manifest: \(WRhythmLogRedactor.errorSummary(error))")
        }
    }

    private func loadPrebufferManifestRecords() -> [PersistedPrebufferRecord] {
        do {
            let data = try Data(contentsOf: prebufferManifestURL)
            return try JSONDecoder().decode([PersistedPrebufferRecord].self, from: data)
        } catch {
            return []
        }
    }

    private func restorePersistedPrebufferManifest() {
        let records = loadPrebufferManifestRecords()
        guard !records.isEmpty else { return }

        let existingFilenames = Set((try? FileManager.default.contentsOfDirectory(
            at: prebufferDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).map(\.lastPathComponent)) ?? [])
        let restorableRecords = PrebufferManifestPolicy.restorableRecords(
            records: records,
            existingFilenames: existingFilenames
        )
        guard !restorableRecords.isEmpty else {
            savePrebufferManifest()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            var restoredAny = false
            for record in restorableRecords {
                let url = self.prebufferDirectory.appendingPathComponent(record.filename, isDirectory: false)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }

                do {
                    let prebuffer = try await Self.preparePrebufferAsset(
                        for: record.song,
                        url: url,
                        qualityLabel: record.qualityLabel
                    )
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    self.prebufferURLs[record.key] = url
                    self.preparedPrebuffers[record.key] = prebuffer
                    restoredAny = true
                } catch {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            if restoredAny {
                self.updatePrebufferedTrackCount()
            }
            self.savePrebufferManifest()
        }
    }

    private func existingPrebufferURL(for song: Song) -> URL? {
        let key = prebufferKey(for: song)
        if let cachedURL = prebufferURLs[key],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            guard cachedPrebufferIsCompatible(song: song, url: cachedURL, qualityLabel: preparedQualityLabel(for: song)) else {
                discardCachedPrebuffer(key: key, url: cachedURL)
                return nil
            }
            return cachedURL
        }

        let url = prebufferURL(for: song)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard cachedPrebufferIsCompatible(song: song, url: url, qualityLabel: preparedQualityLabel(for: song)) else {
            discardCachedPrebuffer(key: key, url: url)
            return nil
        }
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
        guard cachedPrebufferIsCompatible(song: song, url: prebuffer.url, qualityLabel: prebuffer.qualityLabel) else {
            discardCachedPrebuffer(key: key, url: prebuffer.url)
            return nil
        }
        return prebuffer
    }

    private func cachedPrebufferIsCompatible(song: Song, url: URL, qualityLabel: String?) -> Bool {
        PrebufferPlaybackSelectionPolicy.shouldUseCachedPrebuffer(
            songContentType: song.contentType,
            songSuffix: song.suffix,
            songPath: song.path,
            streamingQuality: StreamingQuality.current,
            cachedFileExtension: url.pathExtension,
            qualityLabel: qualityLabel
        )
    }

    private func discardCachedPrebuffer(key: String, url: URL) {
        preparedPrebuffers.removeValue(forKey: key)
        prebufferURLs.removeValue(forKey: key)
        prebufferProgressByKey.removeValue(forKey: key)
        try? FileManager.default.removeItem(at: url)
        savePrebufferManifest()
    }

    private func isPrebuffered(_ song: Song) -> Bool {
        preparedPrebuffer(for: song) != nil
    }

    private nonisolated static func playbackMimeType(contentType: String?, suffix: String?, url: URL) -> String? {
        PlaybackFormatPolicy.playbackMimeType(contentType: contentType, suffix: suffix, url: url)
    }

    private func playbackMimeType(for song: Song, url: URL) -> String? {
        Self.playbackMimeType(contentType: song.contentType, suffix: effectiveSuffix(for: song), url: url)
    }

    private nonisolated static func playbackAssetOptions(contentType: String?, suffix: String?, url: URL) -> [String: Any] {
        var assetOptions: [String: Any] = [:]
        if let contentType = playbackMimeType(contentType: contentType, suffix: suffix, url: url) {
            let fixedContentType = contentType == "audio/x-flac" ? "audio/flac" : contentType
            assetOptions["AVURLAssetOutOfBandMIMETypeKey"] = fixedContentType

            if fixedContentType.contains("flac") {
                assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = true
            }
        }
        return assetOptions
    }

    private func playbackAssetOptions(for song: Song, url: URL) -> [String: Any] {
        Self.playbackAssetOptions(contentType: song.contentType, suffix: effectiveSuffix(for: song), url: url)
    }

    private func makePlaybackAsset(for song: Song, url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: playbackAssetOptions(for: song, url: url))
    }

    private nonisolated static func preparePrebufferAsset(for song: Song, url: URL, qualityLabel: String) async throws -> PreparedPrebuffer {
        let effectiveSuffix = PlaybackFormatPolicy.effectiveSuffix(suffix: song.suffix, path: song.path)
        let asset = AVURLAsset(url: url, options: playbackAssetOptions(contentType: song.contentType, suffix: effectiveSuffix, url: url))
        let isPlayable = try await asset.load(.isPlayable)
        _ = try? await asset.load(.duration)
        guard isPlayable else { throw PrebufferPreparationError.notPlayable }
        return PreparedPrebuffer(song: song, url: url, asset: asset, qualityLabel: qualityLabel)
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
        guard PrebufferOwnershipPolicy.shouldSchedule(isLocalPlaybackOutput: allowsQueuePrebuffering) else {
            suspendPrebufferingForRemoteOutput()
            return
        }

        guard !queue.isEmpty else {
            cancelPrebufferWork()
            return
        }

        if let cooldownUntil = prebufferRetryCooldownUntil {
            let now = Date()
            if cooldownUntil > now {
                schedulePrebufferCooldownWake(at: cooldownUntil)
                updatePrebufferedTrackCount()
                return
            }
            prebufferRetryCooldownUntil = nil
        }

        let queueKeys = queue.map(prebufferKey)
        let currentKey = queue.indices.contains(currentIndex) ? queueKeys[currentIndex] : nil
        let start = min(max(currentIndex + 1, 0), queue.count)
        let end = min(queue.count, start + prebufferAheadCount)
        let upcomingSongs = start < end ? Array(queue[start..<end]) : []
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: currentIndex,
            aheadCount: prebufferAheadCount
        )
        let previousKeys = PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: currentIndex,
            keepCount: retainPreviousPrebufferCount
        )
        let desiredDownloadKeys = PrebufferSchedulingPolicy.desiredKeys(
            currentKey: currentKey,
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )
        let candidateKeys = PrebufferSchedulingPolicy.orderedCandidateKeys(
            currentKey: nil,
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )
        var songsByKey: [String: Song] = [:]
        for song in upcomingSongs {
            songsByKey[prebufferKey(for: song)] = song
        }
        for song in queue[PrebufferSchedulingPolicy.previousRange(
            queueCount: queue.count,
            currentIndex: currentIndex,
            keepCount: retainPreviousPrebufferCount
        )] {
            songsByKey[prebufferKey(for: song)] = song
        }

        let staleKeys = prebufferTasks.keys.filter { !desiredDownloadKeys.contains($0) }
        for key in staleKeys {
            prebufferTasks[key]?.cancel()
            prebufferTasks.removeValue(forKey: key)
            prebufferTaskTokens.removeValue(forKey: key)
            prebufferProgressByKey.removeValue(forKey: key)
        }

        prunePrebufferRetryState(keeping: desiredDownloadKeys)
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
                preparePrebufferedFile(song, key: key, url: downloadedURL, qualityLabel: downloadedQualityLabel(for: song) ?? "Downloaded")
                continue
            }
            if let existingURL = existingPrebufferURL(for: song) {
                preparePrebufferedFile(song, key: key, url: existingURL, qualityLabel: prebufferQualityLabel(for: song))
                continue
            }
            startPrebuffering(song, key: key)
        }
    }

    func suspendPrebufferingForRemoteOutput() {
        allowsQueuePrebuffering = false
        cancelPrebufferWork()
    }

    func resumePrebufferingForLocalOutput() {
        guard !allowsQueuePrebuffering else { return }
        allowsQueuePrebuffering = true
        scheduleQueuePrebuffer()
    }

    private func cancelPrebufferWork() {
        prebufferTasks.values.forEach { $0.cancel() }
        prebufferTasks.removeAll()
        prebufferTaskTokens.removeAll()
        prebufferProgressByKey.removeAll()
        clearPrebufferRetryState()
        updatePrebufferedTrackCount()
    }

    private func startPrebuffering(_ song: Song, key: String) {
        guard let url = streamURLForPlayback(song) else { return }
        let qualityLabel = prebufferQualityLabel(for: song)
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

                await self?.prepareDownloadedPrebuffer(song, key: key, url: destinationURL, taskToken: taskToken, qualityLabel: qualityLabel)
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
                    print("⚠️ Failed to prebuffer \(song.title): \(WRhythmLogRedactor.errorSummary(error))")
                    player.schedulePrebufferRetry(for: song, key: key)
                }
            }
        }
    }

    private func preparePrebufferedFile(_ song: Song, key: String, url: URL, qualityLabel: String) {
        let taskToken = UUID().uuidString
        prebufferTaskTokens[key] = taskToken
        prebufferTasks[key] = Task { [weak self] in
            await self?.prepareDownloadedPrebuffer(song, key: key, url: url, taskToken: taskToken, qualityLabel: qualityLabel)
        }
    }

    private func prepareDownloadedPrebuffer(_ song: Song, key: String, url: URL, taskToken: String, qualityLabel: String) async {
        do {
            let prebuffer = try await Self.preparePrebufferAsset(for: song, url: url, qualityLabel: qualityLabel)
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
                        player.savePrebufferManifest()
                        if player.prebufferURL(for: song) == url {
                            try? FileManager.default.removeItem(at: url)
                        }
                        player.updatePrebufferedTrackCount()
                    }
                    return
                }
                player.prebufferURLs[key] = prebuffer.url
                player.preparedPrebuffers[key] = prebuffer
                player.savePrebufferManifest()
                player.clearPrebufferRetryState(for: key)
                player.prebufferTasks.removeValue(forKey: key)
                player.prebufferTaskTokens.removeValue(forKey: key)
                player.prebufferProgressByKey.removeValue(forKey: key)
                player.updatePrebufferedTrackCount()
                Task {
                    await StoredAlbumArtworkCache.persistIfEnabled(coverArtId: song.coverArt)
                }
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
                player.savePrebufferManifest()
                if player.prebufferURL(for: song) == url {
                    try? FileManager.default.removeItem(at: url)
                }
                player.updatePrebufferedTrackCount()
                print("⚠️ Failed to prepare prebuffered file for \(song.title): \(WRhythmLogRedactor.errorSummary(error))")
                player.schedulePrebufferRetry(for: song, key: key)
            }
        }
    }

    private func desiredPrebufferKeys() -> Set<String> {
        guard !queue.isEmpty else { return [] }
        let queueKeys = queue.map(prebufferKey)
        let currentKey = queueKeys.indices.contains(currentIndex) ? queueKeys[currentIndex] : nil
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: currentIndex,
            aheadCount: prebufferAheadCount
        )
        let previousKeys = PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: currentIndex,
            keepCount: retainPreviousPrebufferCount
        )
        return PrebufferSchedulingPolicy.desiredKeys(
            currentKey: currentKey,
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )
    }

    private func schedulePrebufferRetry(for song: Song, key: String) {
        guard prebufferRetryTasksByKey[key] == nil else { return }
        guard desiredPrebufferKeys().contains(key) else { return }

        let now = Date()
        recordPrebufferFailure(at: now)
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

        var delay = PrebufferRetryPolicy.retryDelay(forAttempt: attempt, key: key)
        if PrebufferRetryPolicy.shouldEnterCooldown(recentFailureDates: recentPrebufferFailureDates, now: now) {
            let cooldownUntil = now.addingTimeInterval(PrebufferRetryPolicy.cooldownDuration)
            prebufferRetryCooldownUntil = max(prebufferRetryCooldownUntil ?? cooldownUntil, cooldownUntil)
            delay = max(delay, PrebufferRetryPolicy.cooldownDuration)
            print("⏸️ Prebuffer retries cooling down for \(Int(PrebufferRetryPolicy.cooldownDuration))s after repeated timeouts")
        }
        prebufferRetryAttemptsByKey[key] = attempt + 1
        print("⏳ Retrying prebuffer for \(song.title) in \(Int(delay.rounded()))s (attempt \(attempt + 1))")

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

    private func recordPrebufferFailure(at date: Date) {
        recentPrebufferFailureDates.append(date)
        recentPrebufferFailureDates = PrebufferRetryPolicy.recentFailures(
            from: recentPrebufferFailureDates,
            now: date
        )
    }

    private func schedulePrebufferCooldownWake(at date: Date) {
        guard prebufferCooldownWakeTask == nil else { return }
        prebufferCooldownWakeTask = Task { @MainActor [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self else { return }
            self.prebufferCooldownWakeTask = nil
            if let cooldownUntil = self.prebufferRetryCooldownUntil, cooldownUntil <= Date() {
                self.prebufferRetryCooldownUntil = nil
            }
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
        recentPrebufferFailureDates.removeAll()
        prebufferRetryCooldownUntil = nil
        prebufferCooldownWakeTask?.cancel()
        prebufferCooldownWakeTask = nil
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

        var removedMissingPrebuffer = false
        for (key, prebuffer) in preparedPrebuffers where !FileManager.default.fileExists(atPath: prebuffer.url.path) {
            preparedPrebuffers.removeValue(forKey: key)
            prebufferURLs.removeValue(forKey: key)
            removedMissingPrebuffer = true
        }
        if removedMissingPrebuffer {
            savePrebufferManifest()
        }
        guard !queue.isEmpty else {
            prebufferedTrackCount = 0
            prebufferedSongs = []
            retainedPrebufferedSongs = []
            publishAvailablePreparedPrebuffers(queuedSongs: [])
            prebufferDownloadStatuses = []
            return
        }
        let upcomingRange = PrebufferSchedulingPolicy.upcomingRange(
            queueCount: queue.count,
            currentIndex: currentIndex,
            aheadCount: prebufferAheadCount
        )
        let upcomingSlice = queue[upcomingRange]
        let upcomingKeys = upcomingSlice.map(prebufferKey)
        let readySongs = upcomingSlice.filter { song in
            preparedPrebuffers[prebufferKey(for: song)] != nil
        }
        let previousRange = PrebufferSchedulingPolicy.previousRange(
            queueCount: queue.count,
            currentIndex: currentIndex,
            keepCount: retainPreviousPrebufferCount
        )
        let previousSlice = queue[previousRange]
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
        let availableSongs = availablePreparedSongs(queuedSongs: queue)
        var qualityLabels: [String: String] = [:]
        for song in availableSongs {
            if let qualityLabel = preparedQualityLabel(for: song) {
                qualityLabels[song.id] = qualityLabel
            }
        }
        if availablePrebufferedSongs.map(\.id) != availableSongs.map(\.id) {
            availablePrebufferedSongs = availableSongs
        }
        if availablePrebufferedTrackQualityLabels != qualityLabels {
            availablePrebufferedTrackQualityLabels = qualityLabels
        }
        let currentSlice = queue.indices.contains(currentIndex) ? [queue[currentIndex]] : []
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

    private func publishAvailablePreparedPrebuffers(queuedSongs: [Song]) {
        let availableSongs = availablePreparedSongs(queuedSongs: queuedSongs)
        var qualityLabels: [String: String] = [:]
        for song in availableSongs {
            if let qualityLabel = preparedQualityLabel(for: song) {
                qualityLabels[song.id] = qualityLabel
            }
        }
        if availablePrebufferedSongs.map(\.id) != availableSongs.map(\.id) {
            availablePrebufferedSongs = availableSongs
        }
        if availablePrebufferedTrackQualityLabels != qualityLabels {
            availablePrebufferedTrackQualityLabels = qualityLabels
        }
    }

    private func availablePreparedSongs(queuedSongs: [Song]) -> [Song] {
        PrebufferAvailabilityPresentationPolicy.orderedAvailableSongs(
            queuedSongs: queuedSongs,
            preparedSongs: preparedPrebuffers.values.map(\.song)
        )
    }

    private func preparedQualityLabel(for song: Song) -> String? {
        if let qualityLabel = preparedPrebuffers[prebufferKey(for: song)]?.qualityLabel {
            return qualityLabel
        }
        return preparedPrebuffers.first { $0.value.song.id == song.id }?.value.qualityLabel
    }

    private func preparedPrebufferMatchingAvailableSong(_ song: Song) -> PreparedPrebuffer? {
        if let prebuffer = preparedPrebuffers[prebufferKey(for: song)] {
            return prebuffer
        }
        return preparedPrebuffers.first { $0.value.song.id == song.id }?.value
    }

    func keepAvailableTrack(_ song: Song) async {
        guard let prebuffer = preparedPrebufferMatchingAvailableSong(song) else { return }
        do {
            try await DownloadManager.shared.keepAvailableTrack(
                song: prebuffer.song,
                sourceURL: prebuffer.url,
                qualityLabel: prebuffer.qualityLabel
            )
            updatePrebufferedTrackCount()
        } catch {
            print("❌ Failed to keep available track \(song.title): \(WRhythmLogRedactor.errorSummary(error))")
        }
    }

    func keepAllAvailableTracks() {
        guard !isKeepingAvailableTracks else { return }
        let songs = AvailableTrackKeepBatchPolicy.songsToKeep(
            availableSongs: availablePrebufferedSongs,
            downloadedSongIds: Set(DownloadManager.shared.downloadedSongs.keys)
        )
        guard !songs.isEmpty else { return }

        keepAvailableTracksTask?.cancel()
        isKeepingAvailableTracks = true
        keepAvailableTracksTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isKeepingAvailableTracks = false
                self.keepAvailableTracksTask = nil
            }

            for chunk in AvailableTrackKeepBatchPolicy.chunks(songs, chunkSize: 20) {
                guard !Task.isCancelled else { return }
                for song in chunk {
                    await self.keepAvailableTrack(song)
                }
                await Task.yield()
            }
        }
    }

    @MainActor
    func cacheArtworkForAvailableTracks() async {
        let coverArtIds = Set(
            Array(availablePrebufferedSongs.compactMap(\.coverArt)) +
            Array(prebufferedSongs.compactMap(\.coverArt)) +
            Array(retainedPrebufferedSongs.compactMap(\.coverArt)) +
            Array(queue.compactMap(\.coverArt)) +
            Array(playlistGenQueue.compactMap(\.coverArt)) +
            (currentSong?.coverArt.map { [$0] } ?? [])
        )
        for coverArtId in coverArtIds {
            await StoredAlbumArtworkCache.persistIfEnabled(coverArtId: coverArtId)
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

        var removedPreparedPrebuffer = false
        for key in Array(preparedPrebuffers.keys) where !keepKeys.contains(key) {
            preparedPrebuffers.removeValue(forKey: key)
            prebufferURLs.removeValue(forKey: key)
            removedPreparedPrebuffer = true
        }

        for url in files where PrebufferCachePruningPolicy.shouldRemove(
            filename: url.lastPathComponent,
            keepFilenames: keepFilenames
        ) {
            try? FileManager.default.removeItem(at: url)
        }
        if removedPreparedPrebuffer {
            savePrebufferManifest()
        }
        updatePrebufferedTrackCount()
    }

    private func startPlayback(_ song: Song, startTime: TimeInterval = 0, autoplay: Bool = true) {
        print("🎵 AudioPlayer: startPlayback called with startTime: \(startTime)")
        print("🎵 Song: \(song.title) by \(song.artist ?? "Unknown")")
        print("🎵 Song ID: \(song.id)")
        print("🎵 Content type: \(song.contentType ?? "unknown")")
        print("🎵 Suffix: \(effectiveSuffix(for: song) ?? "unknown")")
        playbackError = nil
        lastPauseReason = nil
        currentBufferPercent = nil
        currentPlaybackQualitySummary = nil

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
        beginRecentlyPlayedTracking(for: song, startTime: startTime)
        beginScrobbleTracking(for: song, startTime: startTime)
        scheduleQueuePrebuffer()

        // Check if song is downloaded first
        let playURL: URL
        let preparedAsset: AVURLAsset?
        let playbackQualitySummary: String

        if let prebuffer = preparedPrebuffer(for: song) {
            playURL = prebuffer.url
            preparedAsset = prebuffer.asset
            playbackQualitySummary = makePlaybackQualitySummary(source: .local, qualityLabel: prebuffer.qualityLabel)
            print("🎵 Playing from prepared local queue file: \(prebuffer.url.lastPathComponent)")
        } else if let localURL = DownloadManager.shared.getLocalURL(song.id) {
            playURL = localURL
            preparedAsset = nil
            playbackQualitySummary = makePlaybackQualitySummary(source: .local, qualityLabel: downloadedQualityLabel(for: song))
            print("🎵 Playing from local file before preparation completed: \(localURL.lastPathComponent)")
        } else if let prebufferURL = existingPrebufferURL(for: song) {
            playURL = prebufferURL
            preparedAsset = nil
            playbackQualitySummary = makePlaybackQualitySummary(source: .local, qualityLabel: preparedQualityLabel(for: song) ?? prebufferQualityLabel(for: song))
            print("🎵 Playing from cached queue file before preparation completed: \(prebufferURL.lastPathComponent)")
        } else {
            if shouldTranscodeForPlayback(song) {
                let bitRate = StreamingQuality.current.maxBitRate ?? StreamingQuality.max.rawValue
                let isNativelySupported = isFormatSupportedNatively(song)
                let reason = isNativelySupported ? StreamingQuality.current.description : "Unsupported format"
                print("⚠️ \(reason) - requesting MP3 transcode at \(bitRate) kbps")
                if let streamURL = streamURLForPlayback(song) {
                    playURL = streamURL
                    preparedAsset = nil
                    playbackQualitySummary = makePlaybackQualitySummary(source: .streaming, qualityLabel: prebufferQualityLabel(for: song))
                    print("🎵 Streaming transcoded: \(WRhythmLogRedactor.redacted(streamURL))")
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
                print("✅ Streaming original format '\(song.contentType ?? effectiveSuffix(for: song) ?? "unknown")'")
                if let streamURL = streamURLForPlayback(song) {
                    playURL = streamURL
                    preparedAsset = nil
                    playbackQualitySummary = makePlaybackQualitySummary(source: .streaming, qualityLabel: prebufferQualityLabel(for: song))
                    print("🎵 Streaming from: \(WRhythmLogRedactor.redacted(streamURL))")
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

        print("🎵 Playback URL: \(playURL.isFileURL ? playURL.absoluteString : WRhythmLogRedactor.redacted(playURL))")
        self.isPlaying = PlaybackStartupStatePolicy.isPlayingDuringStartup(autoplay: autoplay)
        currentPlaybackURL = playURL
        currentPlaybackIsLocalFile = playURL.isFileURL
        currentPlaybackQualitySummary = playbackQualitySummary

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
        lastPauseReason = nil
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

    func pause(reason: String = "unspecified") {
        recordPlaybackIntentChange()
        lastPauseReason = reason
        print("⏸️ AudioPlayer.pause reason: \(reason)")
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
        recentlyPlayedTracker.reset()
        currentPlaybackURL = nil
        currentPlaybackIsLocalFile = false
        currentPlaybackQualitySummary = nil
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

    func clearAccountBoundPlaybackState() {
        playbackRetryTask?.cancel()
        playbackRetryTask = nil
        playbackRetryAttemptsBySongID.removeAll()
        playlistGenTask?.cancel()
        playlistGenTask = nil
        keepAvailableTracksTask?.cancel()
        keepAvailableTracksTask = nil
        isKeepingAvailableTracks = false
        playbackError = nil
        currentBufferPercent = nil

        stop()
        cancelPrebufferWork()
        preparedPrebuffers.removeAll()
        prebufferURLs.removeAll()
        prebufferDownloadStatuses = []
        prebufferedSongs = []
        retainedPrebufferedSongs = []
        availablePrebufferedSongs = []
        availablePrebufferedTrackQualityLabels = [:]
        prebufferedTrackCount = 0
        prebufferingTrackCount = 0
        prebufferingProgressPercent = nil
        availableTracksQueueRestoreState = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedPlaybackStateKey)
        try? FileManager.default.removeItem(at: prebufferDirectory)
#if os(iOS) || os(watchOS) || os(macOS)
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        nowPlayingArtworkSongID = nil
        nowPlayingArtworkCache.removeAll()
#endif
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
                self.updateRecentlyPlayedTracking()
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
                        print("❌ Error userInfo: \(WRhythmLogRedactor.redactSensitiveURLData(in: String(describing: nsError.userInfo)))")

                        // Provide specific guidance for common errors
                        if nsError.code == -11850 {
                            print("💡 Error -11850 (AVErrorOperationStopped): Stream was stopped")
                            print("💡 Possible causes: Network issue, invalid URL, unsupported format, or ATS restriction")
                        }

                        // Try to get more details from the access log
                        if let accessLog = item.accessLog() {
                            print("📊 Access log events: \(accessLog.events.count)")
                            for event in accessLog.events {
                                print("📊 URI: \(event.uri.map(WRhythmLogRedactor.redactedURLString) ?? "nil")")
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
        let urlText = url.map { "\nURL: \(WRhythmLogRedactor.redacted($0))" } ?? ""
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
            lines.append("URI: \(accessEvent.uri.map(WRhythmLogRedactor.redactedURLString) ?? "unknown")")
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
                recoverySuggestion: "Try playing the track again. If this repeats, lower streaming quality or verify the server implements the Subsonic API and can stream this source file."
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

#if DEBUG
    func playHarnessLocalAudioFixture(duration: TimeInterval = 90) throws {
        let safeDuration = max(10, min(duration, 300))
        let song = Song(
            id: "harness-local-audio-fixture",
            title: "Harness Background Audio",
            album: "Harness",
            albumId: "harness-background-audio",
            artist: "WRhythm Harness",
            artistId: "wrhythm-harness",
            track: 1,
            year: nil,
            genre: nil,
            coverArt: nil,
            size: nil,
            contentType: "audio/wav",
            suffix: "wav",
            duration: Int(safeDuration),
            bitRate: 128,
            path: nil
        )

        let url = prebufferURL(for: song)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Self.writeHarnessToneWAV(to: url, duration: safeDuration)
        }
        prebufferURLs[prebufferKey(for: song)] = url
        lastPauseReason = nil
        playQueue([song], startingAt: 0, startTime: 0)
    }

    private static func writeHarnessToneWAV(to url: URL, duration: TimeInterval) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let sampleRate = 8_000
        let channelCount = 1
        let bitsPerSample = 16
        let sampleCount = max(sampleRate, Int(duration * Double(sampleRate)))
        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        let dataByteCount = sampleCount * blockAlign

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)

        func appendASCII(_ value: String) {
            data.append(contentsOf: value.utf8)
        }

        func appendUInt16LE(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        func appendUInt32LE(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32LE(UInt32(36 + dataByteCount))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32LE(16)
        appendUInt16LE(1)
        appendUInt16LE(UInt16(channelCount))
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(UInt32(byteRate))
        appendUInt16LE(UInt16(blockAlign))
        appendUInt16LE(UInt16(bitsPerSample))
        appendASCII("data")
        appendUInt32LE(UInt32(dataByteCount))

        for index in 0..<sampleCount {
            let phase = 2 * Double.pi * 440 * Double(index) / Double(sampleRate)
            let sample = Int16((sin(phase) * 1_800).rounded())
            appendUInt16LE(UInt16(bitPattern: sample))
        }

        try data.write(to: url, options: [.atomic])
    }
#endif

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
           let coverURL = StoredAlbumArtworkCache.displayURL(for: coverArtId, size: 300) {
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
                    let data: Data
                    let response: URLResponse?
                    if coverURL.isFileURL {
                        data = try Data(contentsOf: coverURL)
                        response = nil
                    } else {
                        let loaded = try await URLSession.shared.data(from: coverURL)
                        data = loaded.0
                        response = loaded.1
                        try await StoredAlbumArtworkCache.persistIfEnabled(
                            coverArtId: coverArtId,
                            data: data,
                            responseStatusCode: (response as? HTTPURLResponse)?.statusCode,
                            remoteURL: coverURL
                        )
                    }
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
