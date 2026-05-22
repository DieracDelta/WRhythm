//
//  DeviceSyncManager.swift
//  WRhythm
//
//  Coordinates optional playback and credential sync across nearby WRhythm devices.
//

import Combine
import Foundation

#if os(iOS) || os(watchOS)
@preconcurrency import WatchConnectivity
#endif

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

#if os(iOS) || os(macOS)
@preconcurrency import MultipeerConnectivity
#endif

#if os(iOS) || os(macOS)
private struct SyncInvitationHandler: @unchecked Sendable {
    let handler: (Bool, MCSession?) -> Void

    func callAsFunction(_ shouldAccept: Bool, _ session: MCSession?) {
        handler(shouldAccept, session)
    }
}

private struct SyncPeerHandle: @unchecked Sendable {
    let peerID: MCPeerID
}
#endif

actor SyncDelegateEventQueue {
    private var previousTask: Task<Void, Never>?
    private var previousTaskID = 0

    func enqueue(_ operation: @escaping @MainActor @Sendable () -> Void) {
        let previousTask = previousTask
        let taskID = previousTaskID + 1
        previousTaskID = taskID
        let task = Task {
            await previousTask?.value
            await MainActor.run(body: operation)
            self.finish(taskID)
        }
        self.previousTask = task
    }

    func waitForIdle() async {
        while true {
            if let task = previousTask {
                await task.value
                continue
            }
            await Task.yield()
            if previousTask == nil {
                return
            }
        }
    }

    private func finish(_ taskID: Int) {
        if previousTaskID == taskID {
            previousTask = nil
        }
    }
}

final class SyncDelegateEventSubmitter: @unchecked Sendable {
    private let submissionQueue: DispatchQueue
    private let eventQueue: SyncDelegateEventQueue

    nonisolated init(label: String, eventQueue: SyncDelegateEventQueue = SyncDelegateEventQueue()) {
        self.submissionQueue = DispatchQueue(label: label)
        self.eventQueue = eventQueue
    }

    nonisolated func enqueue(_ operation: @escaping @MainActor @Sendable () -> Void) {
        submissionQueue.async { [eventQueue] in
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await eventQueue.enqueue(operation)
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    nonisolated func waitForIdle() async {
        await withCheckedContinuation { continuation in
            submissionQueue.async {
                continuation.resume()
            }
        }
        await eventQueue.waitForIdle()
    }
}

struct PlaybackSnapshotFingerprintPolicy: Sendable {
    static let maxTrackedFingerprints = 500

    static func fingerprint(for playback: PlaybackSnapshot) -> String {
        let normalizedCurrentTime = Int((playback.currentTime.isFinite ? playback.currentTime : 0).rounded(.down))
        let normalizedDuration = Int((playback.duration.isFinite ? playback.duration : 0).rounded())
        let normalizedVolume = Int(((playback.volume ?? -1) * 100).rounded())

        return [
            playback.id,
            playback.song?.id ?? "",
            playback.isPlaying ? "1" : "0",
            playback.isBuffering == true ? "1" : "0",
            "\(playback.prebufferedTrackCount ?? -1)",
            "\(normalizedVolume)",
            "\(normalizedCurrentTime)",
            "\(normalizedDuration)",
            "\(playback.currentIndex)",
            playback.queue.map(\.id).joined(separator: ",")
        ].joined(separator: "|")
    }

    static func shouldProcess(fingerprint: String, processedFingerprints: Set<String>) -> Bool {
        !processedFingerprints.contains(fingerprint)
    }

    static func trimmedFingerprintOrder(_ ids: [String]) -> [String] {
        guard ids.count > maxTrackedFingerprints else { return ids }
        return Array(ids.suffix(maxTrackedFingerprints))
    }
}

struct SyncedCredentials: Codable, Sendable {
    let baseURL: String
    let username: String
    let password: String
    let issuedAt: Date?

    init(baseURL: String, username: String, password: String, issuedAt: Date? = nil) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.issuedAt = issuedAt
    }
}

struct PlaybackSnapshot: Codable, Identifiable, Sendable {
    let id: String
    let deviceName: String
    let platform: String
    let song: Song?
    let isPlaying: Bool
    let isBuffering: Bool?
    let prebufferedTrackCount: Int?
    let volume: Double?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let queue: [Song]
    let currentIndex: Int
    let updatedAt: Date
}

struct PlaybackSession: Codable, Identifiable, Sendable {
    let id: String
    let revision: Int
    let queue: [Song]
    let currentIndex: Int
    let position: TimeInterval
    let isPlaying: Bool
    let volume: Double?
    let outputDeviceID: String
    let updatedAt: Date
    let updatedByDeviceID: String

    var currentSong: Song? {
        guard !queue.isEmpty, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var estimatedPosition: TimeInterval {
        estimatedPosition(at: Date())
    }

    func estimatedPosition(at now: Date) -> TimeInterval {
        let basePosition = position.isFinite ? position : 0
        let advancedPosition = isPlaying ? basePosition + max(0, now.timeIntervalSince(updatedAt)) : basePosition
        let clampedPosition = max(0, advancedPosition)

        guard let duration = currentSong?.duration, duration > 0 else {
            return clampedPosition
        }
        return min(clampedPosition, TimeInterval(duration))
    }

    var isFinishedAtQueueEnd: Bool {
        guard !isPlaying, !queue.isEmpty, currentIndex >= queue.count - 1 else { return false }
        guard let duration = currentSong?.duration, duration > 0 else { return false }
        return position >= TimeInterval(duration) * 0.95
    }
}

extension PlaybackSnapshot {
    func estimatedCurrentTime(at now: Date = Date()) -> TimeInterval {
        let baseTime = currentTime.isFinite ? currentTime : 0
        let advancedTime = isPlaying ? baseTime + max(0, now.timeIntervalSince(updatedAt)) : baseTime
        let clampedTime = max(0, advancedTime)

        guard duration.isFinite, duration > 0 else {
            return clampedTime
        }
        return min(clampedTime, duration)
    }

    var estimatedCurrentTime: TimeInterval {
        estimatedCurrentTime()
    }

    var isFinishedAtQueueEnd: Bool {
        guard !isPlaying else { return false }
        let queueIsAtEnd = queue.isEmpty || currentIndex >= queue.count - 1
        guard queueIsAtEnd, duration.isFinite, duration > 0 else { return false }
        return currentTime >= duration * 0.95
    }
}

struct PlaybackSyncPolicy: Sendable {
    static let defaultMaxRemotePlaybackSnapshotAge: TimeInterval = 30
    static let defaultAllowedFutureClockSkew: TimeInterval = 10

    static func isStalePlaybackSnapshot(
        _ playback: PlaybackSnapshot,
        current: PlaybackSnapshot?,
        now: Date = Date(),
        maxAge: TimeInterval = defaultMaxRemotePlaybackSnapshotAge,
        allowedFutureClockSkew: TimeInterval = defaultAllowedFutureClockSkew
    ) -> Bool {
        if playback.updatedAt.timeIntervalSince(now) > allowedFutureClockSkew {
            return true
        }

        if now.timeIntervalSince(playback.updatedAt) > maxAge {
            return true
        }

        guard let current, current.id == playback.id else {
            return false
        }

        return playback.updatedAt < current.updatedAt
    }

    static func shouldPublishRemotePlayback(_ playback: PlaybackSnapshot, current: PlaybackSnapshot?) -> Bool {
        guard let current, current.id == playback.id else { return true }
        guard playback.updatedAt >= current.updatedAt else { return false }
        if current.deviceName != playback.deviceName || current.platform != playback.platform { return true }
        if current.song?.id != playback.song?.id { return true }
        if current.isPlaying != playback.isPlaying { return true }
        if (current.isBuffering ?? false) != (playback.isBuffering ?? false) { return true }
        if (current.prebufferedTrackCount ?? 0) != (playback.prebufferedTrackCount ?? 0) { return true }
        if abs(current.duration - playback.duration) > 1 { return true }
        if abs((current.volume ?? -1) - (playback.volume ?? -1)) > 0.01 { return true }
        if current.currentIndex != playback.currentIndex { return true }
        if current.queue.map(\.id) != playback.queue.map(\.id) { return true }
        return abs(current.estimatedCurrentTime - playback.currentTime) > 4
    }
}

struct PlaybackSnapshotReceivePolicy: Sendable {
    static func shouldAccept(
        _ playback: PlaybackSnapshot,
        current: PlaybackSnapshot?,
        isAcknowledgingPendingCommand: Bool,
        now: Date = Date()
    ) -> Bool {
        !PlaybackSyncPolicy.isStalePlaybackSnapshot(playback, current: current, now: now) || isAcknowledgingPendingCommand
    }
}

enum WatchConnectivitySyncPayloadKind: Sendable {
    case hello
    case syncRequest
    case playbackState
    case playbackSession
    case playbackCommand
    case credentials(hasPayload: Bool)
}

struct WatchConnectivitySyncPolicy: Sendable {
    nonisolated static func shouldQueue(_ kind: WatchConnectivitySyncPayloadKind) -> Bool {
        switch kind {
        case .credentials(let hasPayload):
            return hasPayload
        case .hello, .syncRequest:
            return true
        case .playbackState, .playbackSession, .playbackCommand:
            return false
        }
    }
}

struct WatchConnectivitySendFailurePolicy: Sendable {
    nonisolated static func shouldFallbackToUserInfo(kind: WatchConnectivitySyncPayloadKind, canQueuePayload: Bool) -> Bool {
        canQueuePayload && WatchConnectivitySyncPolicy.shouldQueue(kind)
    }
}

enum SyncTransportKind: Sendable {
    case watchConnectivity
    case multipeer
}

struct SyncTransportFailurePolicy: Sendable {
    static func shouldInvalidatePlaybackBroadcastAttempt(kind: WatchConnectivitySyncPayloadKind) -> Bool {
        switch kind {
        case .playbackState, .playbackSession, .playbackCommand:
            return true
        case .hello, .syncRequest, .credentials:
            return false
        }
    }

    static func shouldRequestPlaybackRefresh(kind: WatchConnectivitySyncPayloadKind) -> Bool {
        switch kind {
        case .playbackState, .playbackSession, .playbackCommand:
            return true
        case .hello, .syncRequest, .credentials:
            return false
        }
    }

    static func shouldRestartMultipeerDiscoveryAfterSendFailure(hasConnectedPeers: Bool) -> Bool {
        hasConnectedPeers
    }
}

struct WatchConnectivityActivationPolicy: Sendable {
    nonisolated static func shouldBootstrapSync(activationSucceeded: Bool, hasError: Bool) -> Bool {
        activationSucceeded && !hasError
    }
}

struct WatchConnectivityActivationRetryPolicy: Sendable {
    nonisolated static let maxRetryDelay: TimeInterval = 120

    nonisolated static func shouldRetry(activationSucceeded: Bool, hasError: Bool, canActivate: Bool) -> Bool {
        canActivate && !shouldBootstrapSync(activationSucceeded: activationSucceeded, hasError: hasError)
    }

    nonisolated static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attempt))), maxRetryDelay)
    }

    private nonisolated static func shouldBootstrapSync(activationSucceeded: Bool, hasError: Bool) -> Bool {
        WatchConnectivityActivationPolicy.shouldBootstrapSync(activationSucceeded: activationSucceeded, hasError: hasError)
    }
}

struct MultipeerInviteRetryPolicy: Sendable {
    nonisolated static func shouldInvite(scheduledPeerDisplayName: String, discoveredPeerDisplayName: String?, isAlreadyConnected: Bool) -> Bool {
        discoveredPeerDisplayName == scheduledPeerDisplayName && !isAlreadyConnected
    }
}

struct CredentialSyncPolicy: Sendable {
    static func shouldImport(incomingIssuedAt: Date?, localClearedAt: Date) -> Bool {
        if let incomingIssuedAt {
            return incomingIssuedAt > localClearedAt
        }
        return localClearedAt <= .distantPast
    }
}

enum PlaybackSyncCommandAction: String, Codable, Sendable {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek
    case setVolume
    case playQueue
    case enqueue
    case syncQueue
    case stop
}

enum PlaybackSyncCommandFamily: String, Sendable {
    case transport
    case navigation
    case seek
    case volume
    case queue
    case stop
}

struct PlaybackCommandSyncPolicy: Sendable {
    static let volumeAcknowledgmentTolerance = 0.02
    static let seekAcknowledgmentTolerance: TimeInterval = 5
    static let maxRetryDelay: TimeInterval = 8

    static func needsPlaybackAcknowledgment(_ action: PlaybackSyncCommandAction) -> Bool {
        switch action {
        case .play, .pause, .next, .previous, .seek, .setVolume, .playQueue, .enqueue, .syncQueue, .stop:
            return true
        case .toggle:
            return false
        }
    }

    static func explicitActionForToggledPlayback(isPlaying: Bool) -> PlaybackSyncCommandAction {
        isPlaying ? .pause : .play
    }

    static func commandFamily(for action: PlaybackSyncCommandAction) -> PlaybackSyncCommandFamily {
        switch action {
        case .play, .pause, .toggle:
            return .transport
        case .next, .previous:
            return .navigation
        case .seek:
            return .seek
        case .setVolume:
            return .volume
        case .playQueue, .enqueue, .syncQueue:
            return .queue
        case .stop:
            return .stop
        }
    }

    static func shouldApplyIncomingCommand(_ action: PlaybackSyncCommandAction) -> Bool {
        action != .toggle
    }

    static func isAcknowledged(
        action: PlaybackSyncCommandAction,
        expectedSongs: [Song]? = nil,
        expectedIndex: Int? = nil,
        expectedTime: TimeInterval? = nil,
        expectedVolume: Double? = nil,
        by playback: PlaybackSnapshot,
        now: Date = Date()
    ) -> Bool {
        switch action {
        case .play:
            return playback.isPlaying
        case .pause:
            return !playback.isPlaying
        case .next, .previous:
            guard let expectedIndex else { return false }
            guard playback.currentIndex == expectedIndex else { return false }
            if let expectedSong = playback.queue[safe: expectedIndex] {
                guard playback.song?.id == expectedSong.id else { return false }
            }
            if let expectedTime {
                let currentDelta = abs(playback.currentTime - expectedTime)
                let estimatedDelta = abs(playback.estimatedCurrentTime(at: now) - expectedTime)
                return min(currentDelta, estimatedDelta) <= seekAcknowledgmentTolerance
            }
            return true
        case .seek:
            guard let expectedTime else { return false }
            let currentDelta = abs(playback.currentTime - expectedTime)
            let estimatedDelta = abs(playback.estimatedCurrentTime(at: now) - expectedTime)
            return min(currentDelta, estimatedDelta) <= seekAcknowledgmentTolerance
        case .setVolume:
            guard let expectedVolume, let actualVolume = playback.volume else { return false }
            return abs(expectedVolume - actualVolume) < volumeAcknowledgmentTolerance
        case .playQueue:
            guard let expectedSongs, !expectedSongs.isEmpty else { return false }
            let expectedIndex = min(max(expectedIndex ?? 0, 0), expectedSongs.count - 1)
            guard playback.queue.map(\.id) == expectedSongs.map(\.id) else { return false }
            guard playback.currentIndex == expectedIndex else { return false }
            guard playback.song?.id == expectedSongs[expectedIndex].id else { return false }
            return playback.isPlaying
        case .enqueue:
            guard let expectedSongs, !expectedSongs.isEmpty else { return false }
            return containsContiguousSongIDs(expectedSongs.map(\.id), in: playback.queue.map(\.id))
        case .syncQueue:
            guard let expectedSongs, !expectedSongs.isEmpty else { return false }
            let expectedIndex = min(max(expectedIndex ?? 0, 0), expectedSongs.count - 1)
            return playback.queue.map(\.id) == expectedSongs.map(\.id) && playback.currentIndex == expectedIndex
        case .stop:
            return !playback.isPlaying && playback.song == nil && playback.queue.isEmpty
        case .toggle:
            return false
        }
    }

    static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attempt))), maxRetryDelay)
    }

    private static func containsContiguousSongIDs(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for startIndex in 0...(haystack.count - needle.count) {
            let slice = haystack[startIndex..<(startIndex + needle.count)]
            if Array(slice) == needle {
                return true
            }
        }
        return false
    }
}

struct PlaybackCommandReceivePolicy: Sendable {
    static func shouldApplyNormalCommand(
        action: PlaybackSyncCommandAction,
        targetDeviceID: String?,
        localDeviceID: String
    ) -> Bool {
        guard PlaybackCommandSyncPolicy.shouldApplyIncomingCommand(action) else { return false }
        guard action != .syncQueue else { return false }
        guard let targetDeviceID else { return true }
        return targetDeviceID == localDeviceID
    }

    static func shouldApplySyncQueue(targetDeviceID: String?, localDeviceID: String, hasSongs: Bool) -> Bool {
        guard let targetDeviceID, targetDeviceID != localDeviceID else { return false }
        return hasSongs
    }
}

struct PendingPlaybackCommandPolicy: Sendable {
    static let acknowledgmentDeadline: TimeInterval = 20
    static let opportunisticDeadline: TimeInterval = 6

    static func deadlineInterval(needsAcknowledgment: Bool) -> TimeInterval {
        needsAcknowledgment ? acknowledgmentDeadline : opportunisticDeadline
    }

    static func shouldReplacePendingCommand(
        existingAction: PlaybackSyncCommandAction?,
        incomingAction: PlaybackSyncCommandAction
    ) -> Bool {
        guard let existingAction else { return true }
        return PlaybackCommandSyncPolicy.commandFamily(for: existingAction) == PlaybackCommandSyncPolicy.commandFamily(for: incomingAction)
    }

    static func shouldIncomingCommandSupersedePendingCommand(
        pendingAction: PlaybackSyncCommandAction?,
        incomingAction: PlaybackSyncCommandAction
    ) -> Bool {
        guard let pendingAction else { return false }

        guard PlaybackCommandSyncPolicy.commandFamily(for: pendingAction) == PlaybackCommandSyncPolicy.commandFamily(for: incomingAction) else {
            return false
        }

        switch (pendingAction, incomingAction) {
        case (.play, .pause), (.pause, .play), (.seek, .seek), (.setVolume, .setVolume):
            return true
        case (.toggle, _), (_, .toggle):
            return true
        default:
            return pendingAction == incomingAction
        }
    }

    static func commandFamiliesInvalidated(by incomingAction: PlaybackSyncCommandAction) -> Set<PlaybackSyncCommandFamily> {
        switch PlaybackCommandSyncPolicy.commandFamily(for: incomingAction) {
        case .queue:
            return [.transport, .navigation, .seek, .queue, .stop]
        case .stop:
            return [.transport, .navigation, .seek, .queue, .stop]
        case .navigation:
            return [.navigation, .seek]
        case .transport, .seek, .volume:
            return []
        }
    }
}

struct PendingPlaybackAcknowledgmentPolicy: Sendable {
    static func shouldAcceptAcknowledgingSnapshot(
        _ playback: PlaybackSnapshot,
        current: PlaybackSnapshot?,
        action: PlaybackSyncCommandAction,
        expectedSongs: [Song]? = nil,
        expectedIndex: Int? = nil,
        expectedTime: TimeInterval? = nil,
        expectedVolume: Double? = nil
    ) -> Bool {
        guard PlaybackCommandSyncPolicy.needsPlaybackAcknowledgment(action),
              PlaybackCommandSyncPolicy.isAcknowledged(
                action: action,
                expectedSongs: expectedSongs,
                expectedIndex: expectedIndex,
                expectedTime: expectedTime,
                expectedVolume: expectedVolume,
                by: playback
              ) else {
            return false
        }

        guard let current, current.id == playback.id else {
            return true
        }

        switch action {
        case .playQueue, .enqueue, .syncQueue, .stop:
            return true
        case .play, .pause, .toggle, .next, .previous, .seek, .setVolume:
            break
        }

        if playback.song?.id != current.song?.id { return false }
        if playback.queue.map(\.id) != current.queue.map(\.id) { return false }
        return true
    }
}

struct PendingPlaybackCommandExpiryPolicy: Sendable {
    static func shouldInvalidateOptimisticRemotePlayback(remotePlaybackID: String?, expiredDeviceID: String) -> Bool {
        remotePlaybackID == expiredDeviceID
    }
}

struct PendingPlaybackCommandRetryPolicy: Sendable {
    static func shouldRunRetry(pendingCommandID: String?, scheduledCommandID: String?) -> Bool {
        pendingCommandID == scheduledCommandID
    }
}

struct SyncDuplicatePolicy: Sendable {
    static let maxTrackedEnvelopeIDs = 500

    static func shouldProcess(envelopeID: String?, processedEnvelopeIDs: Set<String>) -> Bool {
        guard let envelopeID else { return true }
        return !processedEnvelopeIDs.contains(envelopeID)
    }

    static func trimmedEnvelopeIDOrder(_ envelopeIDOrder: [String], maxCount: Int = maxTrackedEnvelopeIDs) -> [String] {
        guard envelopeIDOrder.count > maxCount else { return envelopeIDOrder }
        return Array(envelopeIDOrder.suffix(maxCount))
    }
}

struct RemotePlaybackApplicationState: Sendable {
    private var depth = 0

    var isApplying: Bool {
        depth > 0
    }

    mutating func begin() {
        depth += 1
    }

    mutating func end() {
        depth = max(0, depth - 1)
    }
}

struct PlaybackDisplayVisibility: Sendable {
    let showsLocal: Bool
    let showsRemote: Bool
}

struct PlaybackDisplaySourcePolicy: Sendable {
    static func visibility(
        hasLocalSong: Bool,
        localIsPlaying: Bool,
        hasRemotePlayback: Bool,
        hasActiveSharedPlayback: Bool,
        remoteQueueMatchesLocal: Bool
    ) -> PlaybackDisplayVisibility {
        let showsLocal = hasLocalSong && !shouldHideLocal(
            localIsPlaying: localIsPlaying,
            hasActiveSharedPlayback: hasActiveSharedPlayback,
            remoteQueueMatchesLocal: remoteQueueMatchesLocal
        )
        let showsRemote = hasRemotePlayback && !shouldHideRemote(
            localIsPlaying: localIsPlaying,
            hasActiveSharedPlayback: hasActiveSharedPlayback,
            remoteQueueMatchesLocal: remoteQueueMatchesLocal
        )
        return PlaybackDisplayVisibility(showsLocal: showsLocal, showsRemote: showsRemote)
    }

    private static func shouldHideLocal(
        localIsPlaying: Bool,
        hasActiveSharedPlayback: Bool,
        remoteQueueMatchesLocal: Bool
    ) -> Bool {
        hasActiveSharedPlayback || (remoteQueueMatchesLocal && !localIsPlaying)
    }

    private static func shouldHideRemote(
        localIsPlaying: Bool,
        hasActiveSharedPlayback: Bool,
        remoteQueueMatchesLocal: Bool
    ) -> Bool {
        remoteQueueMatchesLocal && localIsPlaying && !hasActiveSharedPlayback
    }
}

struct LocalPlaybackSyncState: Equatable, Sendable {
    let queueIDs: [String]
    let currentSongID: String?
    let currentIndex: Int
    let currentTime: TimeInterval
    let isPlaying: Bool
    let volume: Double
}

struct PlaybackSessionReconciliationPlan: Equatable, Sendable {
    let shouldStop: Bool
    let shouldReplaceQueue: Bool
    let shouldSeek: Bool
    let shouldSetVolume: Bool
    let shouldPlay: Bool
    let shouldPause: Bool
}

struct PlaybackSessionSyncPolicy: Sendable {
    static let seekDriftTolerance: TimeInterval = 3
    static let volumeTolerance = 0.01
    static let defaultMaxSessionAge: TimeInterval = 30
    static let defaultAllowedFutureClockSkew: TimeInterval = 10

    static func isStale(
        _ session: PlaybackSession,
        current: PlaybackSession?,
        now: Date = Date(),
        maxAge: TimeInterval = defaultMaxSessionAge,
        allowedFutureClockSkew: TimeInterval = defaultAllowedFutureClockSkew
    ) -> Bool {
        if session.updatedAt.timeIntervalSince(now) > allowedFutureClockSkew {
            return true
        }

        if now.timeIntervalSince(session.updatedAt) > maxAge {
            return true
        }

        guard let current, current.id == session.id else {
            return false
        }

        if session.revision < current.revision {
            return true
        }

        if session.revision == current.revision, session.updatedAt < current.updatedAt {
            return true
        }

        return false
    }

    static func shouldApply(_ incoming: PlaybackSession, over existing: PlaybackSession?, now: Date = Date()) -> Bool {
        guard !isStale(incoming, current: existing, now: now) else { return false }
        guard let existing else { return true }
        if incoming.id != existing.id {
            return incoming.updatedAt > existing.updatedAt
        }
        if incoming.revision != existing.revision {
            return incoming.revision > existing.revision
        }
        if incoming.updatedAt != existing.updatedAt {
            return incoming.updatedAt > existing.updatedAt
        }
        return incoming.updatedByDeviceID > existing.updatedByDeviceID
    }

    static func reconciliationPlan(
        for session: PlaybackSession,
        localDeviceID: String,
        localState: LocalPlaybackSyncState,
        now: Date = Date()
    ) -> PlaybackSessionReconciliationPlan {
        guard session.outputDeviceID == localDeviceID else {
            return PlaybackSessionReconciliationPlan(
                shouldStop: false,
                shouldReplaceQueue: false,
                shouldSeek: false,
                shouldSetVolume: false,
                shouldPlay: false,
                shouldPause: localState.isPlaying
            )
        }

        guard let sessionSong = session.currentSong else {
            return PlaybackSessionReconciliationPlan(
                shouldStop: localState.currentSongID != nil,
                shouldReplaceQueue: false,
                shouldSeek: false,
                shouldSetVolume: false,
                shouldPlay: false,
                shouldPause: false
            )
        }

        let sessionPosition = session.estimatedPosition(at: now)
        let currentMatches = localState.currentSongID == sessionSong.id && localState.currentIndex == session.currentIndex
        let queueMatches = localState.queueIDs == session.queue.map(\.id)

        return PlaybackSessionReconciliationPlan(
            shouldStop: false,
            shouldReplaceQueue: !currentMatches || !queueMatches,
            shouldSeek: !currentMatches || abs(localState.currentTime - sessionPosition) > seekDriftTolerance,
            shouldSetVolume: session.volume.map { abs(localState.volume - $0) > volumeTolerance } ?? false,
            shouldPlay: session.isPlaying && !localState.isPlaying,
            shouldPause: !session.isPlaying && (localState.isPlaying || !currentMatches)
        )
    }
}

struct PlaybackSessionSnapshotPolicy: Sendable {
    static func snapshot(
        from session: PlaybackSession,
        deviceName: String,
        platform: String,
        remotePlayback: PlaybackSnapshot?,
        now: Date = Date()
    ) -> PlaybackSnapshot? {
        guard let song = session.currentSong else { return nil }
        let isRemotePlaybackFromSessionOutput = remotePlayback?.id == session.outputDeviceID

        return PlaybackSnapshot(
            id: session.outputDeviceID,
            deviceName: deviceName,
            platform: platform,
            song: song,
            isPlaying: session.isPlaying,
            isBuffering: isRemotePlaybackFromSessionOutput ? remotePlayback?.isBuffering : nil,
            prebufferedTrackCount: isRemotePlaybackFromSessionOutput ? remotePlayback?.prebufferedTrackCount : nil,
            volume: session.volume,
            currentTime: session.estimatedPosition(at: now),
            duration: TimeInterval(song.duration ?? 0),
            queue: session.queue,
            currentIndex: session.currentIndex,
            updatedAt: session.updatedAt
        )
    }
}

struct LocalPlaybackOwnershipPolicy: Sendable {
    static func shouldPublishLocalPlayback(
        sharedOutputDeviceID: String?,
        localDeviceID: String,
        isLocalPlaying: Bool
    ) -> Bool {
        guard let sharedOutputDeviceID else { return true }
        return sharedOutputDeviceID == localDeviceID || isLocalPlaying
    }
}

struct PlaybackStateBroadcastPolicy: Sendable {
    static let minimumProgressBroadcastInterval: TimeInterval = 1.5

    static func shouldBroadcast(
        snapshot: PlaybackSnapshot,
        previousSnapshot: PlaybackSnapshot?,
        lastBroadcastAt: Date?,
        now: Date = Date(),
        force: Bool = false,
        syncModeEnabled: Bool = true,
        isApplyingRemoteCommand: Bool = false,
        sharedOutputDeviceID: String? = nil,
        localDeviceID: String
    ) -> Bool {
        guard syncModeEnabled, !isApplyingRemoteCommand else { return false }
        guard LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: sharedOutputDeviceID,
            localDeviceID: localDeviceID,
            isLocalPlaying: snapshot.isPlaying
        ) else { return false }
        if force { return true }
        guard let previousSnapshot else { return true }

        if shouldBypassProgressThrottle(snapshot: snapshot, previousSnapshot: previousSnapshot) {
            return true
        }

        guard let lastBroadcastAt else { return true }
        return now.timeIntervalSince(lastBroadcastAt) > minimumProgressBroadcastInterval
    }

    private static func shouldBypassProgressThrottle(
        snapshot: PlaybackSnapshot,
        previousSnapshot: PlaybackSnapshot
    ) -> Bool {
        if snapshot.song?.id != previousSnapshot.song?.id { return true }
        if snapshot.isPlaying != previousSnapshot.isPlaying { return true }
        if (snapshot.isBuffering ?? false) != (previousSnapshot.isBuffering ?? false) { return true }
        if (snapshot.prebufferedTrackCount ?? 0) != (previousSnapshot.prebufferedTrackCount ?? 0) { return true }
        if snapshot.currentIndex != previousSnapshot.currentIndex { return true }
        if snapshot.queue.map(\.id) != previousSnapshot.queue.map(\.id) { return true }
        if abs((snapshot.volume ?? -1) - (previousSnapshot.volume ?? -1)) > 0.01 { return true }
        if abs(snapshot.duration - previousSnapshot.duration) > 1 { return true }
        return false
    }
}

struct PlaybackStateBroadcastDeliveryPolicy: Sendable {
    static func shouldRecordAttempt(didSend: Bool) -> Bool {
        didSend
    }
}

struct PlaybackTelemetryBroadcastPolicy: Sendable {
    static let minimumTelemetryBroadcastInterval: TimeInterval = 2

    static func shouldBroadcast(lastBroadcastAt: Date?, now: Date = Date()) -> Bool {
        guard let lastBroadcastAt else { return true }
        return now.timeIntervalSince(lastBroadcastAt) >= minimumTelemetryBroadcastInterval
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct PlaybackTargetDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let platform: String
    let isLocal: Bool

    var displayName: String {
        isLocal ? "This \(platform)" : "\(name) (\(platform))"
    }

    var iconName: String {
        switch platform {
        case "Mac": return "desktopcomputer"
        case "iPhone": return "iphone"
        case "Apple Watch": return "applewatch"
        default: return "speaker.wave.2"
        }
    }
}

private struct SyncPeerInfo: Codable, Sendable {
    let id: String
    let name: String
    let platform: String
    let syncModeEnabled: Bool
    let credentialSyncEnabled: Bool
    let hasCredentials: Bool
}

private struct PlaybackCommand: Codable, Sendable {
    let action: PlaybackSyncCommandAction
    let commandID: String?
    let songs: [Song]?
    let startingIndex: Int?
    let time: TimeInterval?
    let volume: Double?

    init(
        action: PlaybackSyncCommandAction,
        commandID: String? = nil,
        songs: [Song]?,
        startingIndex: Int?,
        time: TimeInterval?,
        volume: Double? = nil
    ) {
        self.action = action
        self.commandID = commandID
        self.songs = songs
        self.startingIndex = startingIndex
        self.time = time
        self.volume = volume
    }

    func withCommandID() -> PlaybackCommand {
        PlaybackCommand(
            action: action,
            commandID: commandID ?? UUID().uuidString,
            songs: songs,
            startingIndex: startingIndex,
            time: time,
            volume: volume
        )
    }
}

private struct SyncEnvelope: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case hello
        case syncRequest
        case playbackState
        case playbackSession
        case playbackCommand
        case credentials
    }

    let envelopeID: String?
    let kind: Kind
    let sender: SyncPeerInfo
    let playback: PlaybackSnapshot?
    let playbackSession: PlaybackSession?
    let command: PlaybackCommand?
    let credentials: SyncedCredentials?
    let targetDeviceID: String?

    init(
        envelopeID: String = UUID().uuidString,
        kind: Kind,
        sender: SyncPeerInfo,
        playback: PlaybackSnapshot?,
        playbackSession: PlaybackSession? = nil,
        command: PlaybackCommand?,
        credentials: SyncedCredentials?,
        targetDeviceID: String?
    ) {
        self.envelopeID = envelopeID
        self.kind = kind
        self.sender = sender
        self.playback = playback
        self.playbackSession = playbackSession
        self.command = command
        self.credentials = credentials
        self.targetDeviceID = targetDeviceID
    }
}

private extension SyncEnvelope {
    var watchConnectivityPayloadKind: WatchConnectivitySyncPayloadKind {
        switch kind {
        case .hello:
            return .hello
        case .syncRequest:
            return .syncRequest
        case .playbackState:
            return .playbackState
        case .playbackSession:
            return .playbackSession
        case .playbackCommand:
            return .playbackCommand
        case .credentials:
            return .credentials(hasPayload: credentials != nil)
        }
    }
}

@MainActor
final class DeviceSyncManager: NSObject, ObservableObject {
    static let shared = DeviceSyncManager()
    private nonisolated static let delegateEventSubmitter = SyncDelegateEventSubmitter(label: "WRhythm.DeviceSyncDelegateEvents")

    @Published var syncModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncModeEnabled, forKey: Self.syncModeKey)
            if syncModeEnabled {
                UserDefaults.standard.set(false, forKey: Self.offlineModeKey)
            }
            configureTransports()
            broadcastHello()
            broadcastPlaybackState(force: true)
        }
    }

    @Published var credentialSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(credentialSyncEnabled, forKey: Self.credentialSyncKey)
            configureTransports()
            broadcastHello()
        }
    }

    @Published private(set) var remotePlayback: PlaybackSnapshot?
    @Published private(set) var sharedSession: PlaybackSession?
    @Published private(set) var connectedDeviceNames: [String] = []
    @Published var selectedPlaybackTargetID: String {
        didSet {
            UserDefaults.standard.set(selectedPlaybackTargetID, forKey: Self.playbackTargetKey)
        }
    }

    private static let syncModeKey = "syncMode"
    private static let credentialSyncKey = "credentialSyncMode"
    private static let offlineModeKey = "offlineMode"
    private static let playbackTargetKey = "playbackTargetDeviceID"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let localDeviceID: String
    private let localDeviceName: String
    private let platformName: String
    private var cancellables = Set<AnyCancellable>()
    private var lastPlaybackBroadcast = Date.distantPast
    private var lastPlaybackTelemetryBroadcast = Date.distantPast
    private var lastBroadcastedPlaybackSnapshot: PlaybackSnapshot?
    private var remotePlaybackApplicationState = RemotePlaybackApplicationState()
    private var isApplyingRemoteCommand: Bool {
        remotePlaybackApplicationState.isApplying
    }
    private var peerInfos: [String: SyncPeerInfo] = [:]
    private var pendingTargetedCommands: [String: PlaybackCommand] = [:]
    private var pendingTargetedCommandDeadlines: [String: Date] = [:]
    private var pendingTargetedCommandRetryAttempts: [String: Int] = [:]
    private var pendingTargetedCommandRetryTasks: [String: Task<Void, Never>] = [:]
    private var processedCommandIDs = Set<String>()
    private var processedCommandIDOrder: [String] = []
    private var processedEnvelopeIDs = Set<String>()
    private var processedEnvelopeIDOrder: [String] = []
    private var processedPlaybackSnapshotFingerprints = Set<String>()
    private var processedPlaybackSnapshotFingerprintOrder: [String] = []
    private var isHandlingSyncTransportFailure = false
    private let sharedSessionID: String
#if os(iOS) || os(watchOS)
    private var watchSession: WCSession?
    private var watchConnectivityActivationRetryAttempt = 0
    private var watchConnectivityActivationRetryTask: Task<Void, Never>?
#endif

#if os(iOS) || os(macOS)
    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peerDisplayNames: [MCPeerID: String] = [:]
    private var multipeerDeviceIDs = Set<String>()
    private var deviceIDsByPeerDisplayName: [String: String] = [:]
    private var multipeerRestartAttempt = 0
    private var multipeerRestartTask: Task<Void, Never>?
    private var discoveredMultipeerPeers: [String: MCPeerID] = [:]
    private var inviteAttemptsByPeerDisplayName: [String: Int] = [:]
    private var inviteRetryTasksByPeerDisplayName: [String: Task<Void, Never>] = [:]
    private let multipeerInviteTimeout: TimeInterval = 10
    private let maxMultipeerInviteAttempts = 5
    private let maxMultipeerInviteBackoff: TimeInterval = 60
    private let maxMultipeerDiscoveryBackoff: TimeInterval = 120
#endif

    private override init() {
        if let savedID = UserDefaults.standard.string(forKey: "deviceSyncDeviceID") {
            localDeviceID = savedID
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "deviceSyncDeviceID")
            localDeviceID = newID
        }
        if let savedSessionID = UserDefaults.standard.string(forKey: "deviceSyncSessionID") {
            sharedSessionID = savedSessionID
        } else {
            let newSessionID = UUID().uuidString
            UserDefaults.standard.set(newSessionID, forKey: "deviceSyncSessionID")
            sharedSessionID = newSessionID
        }

#if os(watchOS)
        localDeviceName = WKInterfaceDevice.current().name
        platformName = "Apple Watch"
#elseif os(iOS)
        localDeviceName = UIDevice.current.name
        platformName = "iPhone"
#elseif os(macOS)
        localDeviceName = Host.current().localizedName ?? "WRhythm"
        platformName = "Mac"
#else
        localDeviceName = ProcessInfo.processInfo.processName
        platformName = "Apple Device"
#endif

        if UserDefaults.standard.object(forKey: Self.syncModeKey) == nil {
            syncModeEnabled = true
            UserDefaults.standard.set(true, forKey: Self.syncModeKey)
            UserDefaults.standard.set(false, forKey: Self.offlineModeKey)
        } else {
            syncModeEnabled = UserDefaults.standard.bool(forKey: Self.syncModeKey)
        }
        if UserDefaults.standard.object(forKey: Self.credentialSyncKey) == nil {
            credentialSyncEnabled = true
            UserDefaults.standard.set(true, forKey: Self.credentialSyncKey)
        } else {
            credentialSyncEnabled = UserDefaults.standard.bool(forKey: Self.credentialSyncKey)
        }
        if UserDefaults.standard.bool(forKey: Self.syncModeKey) {
            UserDefaults.standard.set(false, forKey: Self.offlineModeKey)
        }
        // Playback output is a live route, not durable app state. Persisting another
        // device's UUID across launches leaves SwiftUI pickers bound to missing tags.
        selectedPlaybackTargetID = localDeviceID
        UserDefaults.standard.set(localDeviceID, forKey: Self.playbackTargetKey)

#if os(iOS) || os(macOS)
        peerID = MCPeerID(displayName: "\(localDeviceName)-\(localDeviceID.prefix(4))")
#endif

        super.init()

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        observePlayback()
        configureTransports()
    }

    nonisolated private static func enqueueDelegateEvent(_ operation: @escaping @MainActor @Sendable () -> Void) {
        delegateEventSubmitter.enqueue(operation)
    }

    private func withRemotePlaybackApplication(_ body: () -> Void) {
        remotePlaybackApplicationState.begin()
        defer { remotePlaybackApplicationState.end() }
        body()
    }

    var hasActiveRemotePlayback: Bool {
        guard syncModeEnabled, let remotePlayback else { return false }
        return remotePlayback.isPlaying || remotePlayback.song != nil
    }

    var isLocalPlaybackOutput: Bool {
        guard syncModeEnabled, let sharedSession else { return true }
        return sharedSession.outputDeviceID == localDeviceID
    }

    var activeSharedPlayback: PlaybackSnapshot? {
        guard syncModeEnabled,
              let sharedSession,
              sharedSession.currentSong != nil,
              sharedSession.outputDeviceID != localDeviceID else {
            return nil
        }

        let outputPeer = peerInfo(for: sharedSession.outputDeviceID)
        return PlaybackSessionSnapshotPolicy.snapshot(
            from: sharedSession,
            deviceName: outputPeer?.name ?? remotePlayback?.deviceName ?? "Remote Device",
            platform: outputPeer?.platform ?? remotePlayback?.platform ?? "Device",
            remotePlayback: remotePlayback
        )
    }

    var sharedQueue: [Song] {
        sharedSession?.queue ?? []
    }

    var sharedQueueCurrentIndex: Int {
        guard let sharedSession else { return 0 }
        return min(max(sharedSession.currentIndex, 0), max(sharedSession.queue.count - 1, 0))
    }

    var availablePlaybackTargets: [PlaybackTargetDevice] {
        var targets = [
            PlaybackTargetDevice(id: localDeviceID, name: localDeviceName, platform: platformName, isLocal: true)
        ]

        let peers = peerInfos.values
            .filter { $0.syncModeEnabled }
            .filter { isPeerSelectable($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        targets.append(contentsOf: peers.map {
            PlaybackTargetDevice(id: $0.id, name: $0.name, platform: $0.platform, isLocal: false)
        })

        if let remotePlayback,
           remotePlayback.id != localDeviceID,
           Date().timeIntervalSince(remotePlayback.updatedAt) < 20,
           !targets.contains(where: { $0.id == remotePlayback.id }) {
            targets.append(PlaybackTargetDevice(
                id: remotePlayback.id,
                name: remotePlayback.deviceName,
                platform: remotePlayback.platform,
                isLocal: false
            ))
        }

        return targets
    }

    private func isPeerSelectable(_ peer: SyncPeerInfo) -> Bool {
#if os(iOS) || os(macOS)
        if multipeerDeviceIDs.contains(peer.id) {
            return true
        }

        // WatchConnectivity targets do not have Multipeer IDs.
        return peer.platform == "Apple Watch"
#else
        return true
#endif
    }

    private func peerInfo(for deviceID: String) -> SyncPeerInfo? {
        if deviceID == localDeviceID {
            return localPeerInfo()
        }
        return peerInfos[deviceID]
    }

    var selectedPlaybackTargetName: String {
        availablePlaybackTargets.first(where: { $0.id == validSelectedPlaybackTargetID })?.displayName ?? "This \(platformName)"
    }

    var validSelectedPlaybackTargetID: String {
        availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }) ? selectedPlaybackTargetID : localDeviceID
    }

    func validateSelectedPlaybackTarget() {
        if selectedPlaybackTargetID != validSelectedPlaybackTargetID {
            selectedPlaybackTargetID = localDeviceID
        }
    }

    private func nextSessionRevision() -> Int {
        (sharedSession?.revision ?? 0) + 1
    }

    func requestPlaybackSyncRefresh() {
        guard syncModeEnabled || credentialSyncEnabled else { return }
        configureTransports()
        _ = sendEnvelope(.init(kind: .syncRequest, sender: localPeerInfo(), playback: nil, command: nil, credentials: nil, targetDeviceID: nil))
        sendCurrentSyncState(includeHello: true)
    }

    func publishLocalPlaybackStateNow() {
        sendCurrentSyncState()
    }

    private func makeSession(
        queue: [Song],
        currentIndex: Int,
        position: TimeInterval,
        isPlaying: Bool,
        outputDeviceID: String,
        revision: Int? = nil,
        volume: Double? = nil
    ) -> PlaybackSession {
        PlaybackSession(
            id: sharedSession?.id ?? sharedSessionID,
            revision: revision ?? nextSessionRevision(),
            queue: queue,
            currentIndex: min(max(currentIndex, 0), max(queue.count - 1, 0)),
            position: max(0, position.isFinite ? position : 0),
            isPlaying: isPlaying,
            volume: clampedVolume(volume ?? sharedSession?.volume ?? AudioPlayer.shared.volume),
            outputDeviceID: outputDeviceID,
            updatedAt: Date(),
            updatedByDeviceID: localDeviceID
        )
    }

    private func clampedVolume(_ volume: Double) -> Double {
        min(max(volume.isFinite ? volume : 1, 0), 1)
    }

    private func publishSharedSession(_ session: PlaybackSession, applyLocally: Bool = true) {
        guard syncModeEnabled else { return }
        applySharedSession(session, applyLocally: applyLocally)
        _ = sendEnvelope(.init(
            kind: .playbackSession,
            sender: localPeerInfo(),
            playback: nil,
            playbackSession: session,
            command: nil,
            credentials: nil,
            targetDeviceID: nil
        ))
    }

    private func applySharedSession(_ session: PlaybackSession, applyLocally: Bool) {
        guard PlaybackSessionSyncPolicy.shouldApply(session, over: sharedSession) else { return }

        sharedSession = session
        selectedPlaybackTargetID = session.outputDeviceID

        if applyLocally {
            reconcileLocalPlayback(with: session)
        }
    }

    private func reconcileLocalPlayback(with session: PlaybackSession) {
        guard syncModeEnabled else { return }
        let player = AudioPlayer.shared
        let localState = LocalPlaybackSyncState(
            queueIDs: player.queue.map(\.id),
            currentSongID: player.currentSong?.id,
            currentIndex: player.currentIndex,
            currentTime: player.liveCurrentTime,
            isPlaying: player.isPlaying,
            volume: player.volume
        )
        let plan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: localDeviceID,
            localState: localState
        )

        if session.outputDeviceID == localDeviceID {
            withRemotePlaybackApplication {
                guard let song = session.currentSong else {
                    if plan.shouldStop {
                        player.stop()
                    }
                    return
                }

                let currentMatches = localState.currentSongID == song.id && localState.currentIndex == session.currentIndex

                if currentMatches {
                    if plan.shouldReplaceQueue {
                        player.queue = session.queue
                        player.currentIndex = session.currentIndex
                    }
                    if plan.shouldSeek {
                        player.seek(to: session.estimatedPosition)
                    }
                    if let volume = session.volume, plan.shouldSetVolume {
                        player.volume = clampedVolume(volume)
                    }
                    if plan.shouldPlay {
                        player.play()
                    } else if plan.shouldPause {
                        player.pause()
                    }
                } else {
                    player.playQueue(
                        session.queue,
                        startingAt: session.currentIndex,
                        startTime: plan.shouldSeek ? session.estimatedPosition : 0
                    )
                    if let volume = session.volume {
                        player.volume = clampedVolume(volume)
                    }
                    if plan.shouldPause {
                        player.pause()
                    }
                }
            }
        } else if plan.shouldPause {
            withRemotePlaybackApplication {
                player.pause()
            }
        }
    }

    func routePlaybackRequestToConnectedDevice(_ songs: [Song], startingAt index: Int, shuffled: Bool = false) -> Bool {
        validateSelectedPlaybackTarget()
        guard syncModeEnabled,
              selectedPlaybackTargetID != localDeviceID,
              availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }),
              !isApplyingRemoteCommand else {
            return false
        }

        var outgoingSongs = songs
        var outgoingIndex = index
        if shuffled {
            outgoingSongs.shuffle()
            outgoingIndex = 0
        }

        publishSharedSession(makeSession(
            queue: outgoingSongs,
            currentIndex: outgoingIndex,
            position: 0,
            isPlaying: true,
            outputDeviceID: selectedPlaybackTargetID
        ))
        return true
    }

    func routeEnqueueRequestToConnectedDevice(_ songs: [Song]) -> Bool {
        validateSelectedPlaybackTarget()
        guard syncModeEnabled,
              selectedPlaybackTargetID != localDeviceID,
              availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }),
              !isApplyingRemoteCommand,
              !songs.isEmpty else {
            return false
        }

        let player = AudioPlayer.shared
        let baseQueue: [Song]
        let currentIndex: Int

        if let sharedSession, sharedSession.outputDeviceID == selectedPlaybackTargetID {
            baseQueue = sharedSession.queue
            currentIndex = min(sharedSession.currentIndex, max(baseQueue.count - 1, 0))
        } else if let remotePlayback, remotePlayback.id == selectedPlaybackTargetID {
            baseQueue = remotePlayback.queue.isEmpty ? remotePlayback.song.map { [$0] } ?? [] : remotePlayback.queue
            currentIndex = min(remotePlayback.currentIndex, max(baseQueue.count - 1, 0))
        } else {
            baseQueue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
            currentIndex = min(player.currentIndex, max(baseQueue.count - 1, 0))
        }

        let sharedTargetFinished = sharedSession?.outputDeviceID == selectedPlaybackTargetID
            && sharedSession?.isFinishedAtQueueEnd == true
        let remoteTargetFinished = remotePlayback?.id == selectedPlaybackTargetID
            && remotePlayback?.isFinishedAtQueueEnd == true
        let shouldStartAppendedSongs = sharedTargetFinished || remoteTargetFinished
        let sharedQueue = baseQueue + songs
        let appendedStartIndex = baseQueue.count
        publishSharedSession(makeSession(
            queue: sharedQueue,
            currentIndex: shouldStartAppendedSongs ? appendedStartIndex : currentIndex,
            position: shouldStartAppendedSongs ? 0 : (sharedSession?.outputDeviceID == selectedPlaybackTargetID ? sharedSession?.estimatedPosition ?? 0 : player.liveCurrentTime),
            isPlaying: shouldStartAppendedSongs ? true : (sharedSession?.outputDeviceID == selectedPlaybackTargetID ? sharedSession?.isPlaying ?? false : player.isPlaying),
            outputDeviceID: selectedPlaybackTargetID
        ))
        return true
    }

    func enqueueOnConnectedDevices(_ songs: [Song]) {
        guard syncModeEnabled, !songs.isEmpty else { return }
        _ = sendCommand(.init(action: .enqueue, songs: songs, startingIndex: nil, time: nil), targetDeviceID: selectedRemotePlaybackTargetID)
    }

    func sendPlayPause(targetDeviceID: String? = nil) {
        let targetDeviceID = targetDeviceID ?? selectedRemotePlaybackTargetID

        guard let desiredState = desiredPlaybackStateAfterToggle(targetDeviceID: targetDeviceID) else {
            print("⚠️ Ignoring ambiguous remote play/pause toggle; requesting fresh sync state")
            requestPlaybackSyncRefresh()
            return
        }

        setPlaying(desiredState, targetDeviceID: targetDeviceID)
    }

    func toggleSelectedPlaybackTarget() {
        validateSelectedPlaybackTarget()
        let targetDeviceID = validSelectedPlaybackTargetID

        if targetDeviceID == localDeviceID {
            setPlaying(!AudioPlayer.shared.isPlaying, targetDeviceID: localDeviceID)
        } else if let sharedSession, sharedSession.outputDeviceID == targetDeviceID {
            setPlaying(!sharedSession.isPlaying, targetDeviceID: targetDeviceID)
        } else if let remotePlayback, remotePlayback.id == targetDeviceID {
            setPlaying(!remotePlayback.isPlaying, targetDeviceID: targetDeviceID)
        } else {
            sendPlayPause(targetDeviceID: targetDeviceID)
        }
    }

    private func desiredPlaybackStateAfterToggle(targetDeviceID: String?) -> Bool? {
        let targetDeviceID = targetDeviceID ?? selectedRemotePlaybackTargetID

        if targetDeviceID == nil || targetDeviceID == localDeviceID {
            return !AudioPlayer.shared.isPlaying
        }

        if let sharedSession, sharedSession.outputDeviceID == targetDeviceID {
            return !sharedSession.isPlaying
        }

        if let remotePlayback, remotePlayback.id == targetDeviceID {
            return !remotePlayback.isPlaying
        }

        return nil
    }

    func setPlaying(_ isPlaying: Bool, targetDeviceID: String? = nil) {
        let targetDeviceID = targetDeviceID ?? selectedRemotePlaybackTargetID

        if targetDeviceID == nil || targetDeviceID == localDeviceID {
            if isPlaying {
                AudioPlayer.shared.play()
            } else {
                AudioPlayer.shared.pause()
            }
            broadcastLocalQueueAsShared()
            broadcastPlaybackState(force: true)
            return
        }

        if let sharedSession, sharedSession.outputDeviceID == targetDeviceID {
            publishSharedSession(makeSession(
                queue: sharedSession.queue,
                currentIndex: sharedSession.currentIndex,
                position: sharedSession.estimatedPosition,
                isPlaying: isPlaying,
                outputDeviceID: sharedSession.outputDeviceID,
                volume: sharedSession.volume
            ), applyLocally: false)
        } else if let remotePlayback, remotePlayback.id == targetDeviceID {
            self.remotePlayback = PlaybackSnapshot(
                id: remotePlayback.id,
                deviceName: remotePlayback.deviceName,
                platform: remotePlayback.platform,
                song: remotePlayback.song,
                isPlaying: isPlaying,
                isBuffering: isPlaying ? remotePlayback.isBuffering : false,
                prebufferedTrackCount: remotePlayback.prebufferedTrackCount,
                volume: remotePlayback.volume,
                currentTime: remotePlayback.estimatedCurrentTime,
                duration: remotePlayback.duration,
                queue: remotePlayback.queue,
                currentIndex: remotePlayback.currentIndex,
                updatedAt: Date()
            )
        }

        let action = PlaybackCommandSyncPolicy.explicitActionForToggledPlayback(isPlaying: !isPlaying)
        _ = sendCommand(.init(action: action, songs: nil, startingIndex: nil, time: nil), targetDeviceID: targetDeviceID)
    }

    func sendNext(targetDeviceID: String? = nil) {
        let targetDeviceID = targetDeviceID ?? selectedRemotePlaybackTargetID
        let expectedPosition = playbackPositionForTarget(targetDeviceID).map { position in
            min(position.index + 1, max(position.queue.count - 1, 0))
        }
        _ = sendCommand(.init(action: .next, songs: nil, startingIndex: expectedPosition, time: nil), targetDeviceID: targetDeviceID)
    }

    func sendPrevious(targetDeviceID: String? = nil) {
        let targetDeviceID = targetDeviceID ?? selectedRemotePlaybackTargetID
        let position = playbackPositionForTarget(targetDeviceID)
        let shouldResetCurrentTrack = (position?.time ?? 0) > 3
        let expectedPosition = position.map { current in
            shouldResetCurrentTrack ? current.index : max(current.index - 1, 0)
        }
        let expectedTime: TimeInterval? = shouldResetCurrentTrack ? 0 : nil
        _ = sendCommand(.init(action: .previous, songs: nil, startingIndex: expectedPosition, time: expectedTime), targetDeviceID: targetDeviceID)
    }

    func sendSeek(to time: TimeInterval, targetDeviceID: String? = nil) {
        _ = sendCommand(.init(action: .seek, songs: nil, startingIndex: nil, time: time), targetDeviceID: targetDeviceID ?? selectedRemotePlaybackTargetID)
    }

    func setVolume(_ volume: Double, targetDeviceID: String? = nil) {
        let volume = clampedVolume(volume)
        let targetDeviceID = targetDeviceID ?? selectedRemotePlaybackTargetID

        if targetDeviceID == nil || targetDeviceID == localDeviceID {
            AudioPlayer.shared.volume = volume
            broadcastLocalQueueAsShared()
            broadcastPlaybackState(force: true)
            return
        }

        if let sharedSession, sharedSession.outputDeviceID == targetDeviceID {
            publishSharedSession(makeSession(
                queue: sharedSession.queue,
                currentIndex: sharedSession.currentIndex,
                position: sharedSession.estimatedPosition,
                isPlaying: sharedSession.isPlaying,
                outputDeviceID: sharedSession.outputDeviceID,
                volume: volume
            ), applyLocally: false)
        }

        _ = sendCommand(.init(action: .setVolume, songs: nil, startingIndex: nil, time: nil, volume: volume), targetDeviceID: targetDeviceID)
    }

    func playRemoteQueueItem(_ playback: PlaybackSnapshot, at index: Int) {
        guard syncModeEnabled, playback.id != localDeviceID else { return }
        let queue = playback.queue.isEmpty ? playback.song.map { [$0] } ?? [] : playback.queue
        guard !queue.isEmpty else { return }
        let safeIndex = min(max(index, 0), queue.count - 1)
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: safeIndex,
            position: 0,
            isPlaying: true,
            outputDeviceID: playback.id
        ))
    }

    func playSharedQueueItem(at index: Int) {
        guard syncModeEnabled, let sharedSession, !sharedSession.queue.isEmpty else { return }
        let safeIndex = min(max(index, 0), sharedSession.queue.count - 1)
        publishSharedSession(makeSession(
            queue: sharedSession.queue,
            currentIndex: safeIndex,
            position: 0,
            isPlaying: true,
            outputDeviceID: sharedSession.outputDeviceID
        ))

    }

    func takeOverRemotePlayback() {
        guard syncModeEnabled, let remotePlayback, let song = remotePlayback.song else { return }
        selectedPlaybackTargetID = localDeviceID
        let queue = remotePlayback.queue.isEmpty ? [song] : remotePlayback.queue
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: remotePlayback.currentIndex,
            position: remotePlayback.estimatedCurrentTime,
            isPlaying: remotePlayback.isPlaying,
            outputDeviceID: localDeviceID
        ))
    }

    func selectPlaybackTarget(_ targetID: String) {
        guard syncModeEnabled else {
            selectedPlaybackTargetID = localDeviceID
            return
        }

        selectedPlaybackTargetID = targetID

        if targetID == localDeviceID {
            if let sharedPlayback = activeSharedPlayback, sharedPlayback.song != nil {
                let queue = sharedPlayback.queue.isEmpty ? sharedPlayback.song.map { [$0] } ?? [] : sharedPlayback.queue
                guard !queue.isEmpty else { return }
                publishSharedSession(makeSession(
                    queue: queue,
                    currentIndex: sharedPlayback.currentIndex,
                    position: sharedPlayback.estimatedCurrentTime,
                    isPlaying: sharedPlayback.isPlaying,
                    outputDeviceID: localDeviceID
                ))
            } else if let remotePlayback, remotePlayback.song != nil, AudioPlayer.shared.currentSong == nil {
                takeOverRemotePlayback()
            }
            return
        }

        guard availablePlaybackTargets.contains(where: { $0.id == targetID }) else {
            selectedPlaybackTargetID = localDeviceID
            return
        }

        if let sharedSession, !sharedSession.queue.isEmpty {
            publishSharedSession(makeSession(
                queue: sharedSession.queue,
                currentIndex: sharedSession.currentIndex,
                position: sharedSession.estimatedPosition,
                isPlaying: sharedSession.isPlaying,
                outputDeviceID: targetID
            ))
            return
        }

        let player = AudioPlayer.shared
        guard let currentSong = player.currentSong else { return }
        let queue = player.queue.isEmpty ? [currentSong] : player.queue
        let index = min(player.currentIndex, queue.count - 1)
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: index,
            position: player.liveCurrentTime,
            isPlaying: player.isPlaying,
            outputDeviceID: targetID
        ))
    }

    func broadcastLocalQueueAsShared() {
        guard syncModeEnabled, !isApplyingRemoteCommand else { return }
        let player = AudioPlayer.shared
        guard LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: sharedSession?.outputDeviceID,
            localDeviceID: localDeviceID,
            isLocalPlaying: player.isPlaying
        ) else { return }
        let queue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
        guard !queue.isEmpty else { return }
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: min(player.currentIndex, queue.count - 1),
            position: player.liveCurrentTime,
            isPlaying: player.isPlaying,
            outputDeviceID: localDeviceID,
            volume: player.volume
        ), applyLocally: false)
    }

    func credentialsDidChange() {
        broadcastHello()
        maybeSendCredentialsToInterestedPeers()
    }

    func requestCredentialSyncNow() {
        guard credentialSyncEnabled else { return }
        configureTransports()
        broadcastHello()
        maybeSendCredentialsToInterestedPeers()
    }

    private func observePlayback() {
        let player = AudioPlayer.shared

        Publishers.CombineLatest4(player.$currentSong, player.$isPlaying, player.$queue, player.$currentIndex)
            .sink { [weak self] _, _, _, _ in
                guard let self else { return }
                self.broadcastLocalQueueAsShared()
                self.broadcastPlaybackState()
            }
            .store(in: &cancellables)

        player.$currentTime
            .removeDuplicates { abs($0 - $1) < 5 }
            .sink { [weak self] _ in
                self?.broadcastPlaybackState()
            }
            .store(in: &cancellables)

        player.$volume
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { [weak self] _ in
                guard let self, !self.isApplyingRemoteCommand else { return }
                self.broadcastLocalQueueAsShared()
                self.broadcastPlaybackState(force: true)
            }
            .store(in: &cancellables)

        player.$isBuffering
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.broadcastPlaybackTelemetryState()
            }
            .store(in: &cancellables)

        player.$prebufferedTrackCount
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.broadcastPlaybackTelemetryState()
            }
            .store(in: &cancellables)
    }

    private func configureTransports() {
        let shouldConnect = syncModeEnabled || credentialSyncEnabled

#if os(iOS)
        if shouldConnect, WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            if session.activationState == .notActivated {
                session.activate()
            }
            watchSession = session
        } else {
            watchConnectivityActivationRetryTask?.cancel()
            watchConnectivityActivationRetryTask = nil
            watchSession = nil
        }
#elseif os(watchOS)
        if shouldConnect, WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            watchSession = session
        } else {
            watchConnectivityActivationRetryTask?.cancel()
            watchConnectivityActivationRetryTask = nil
            watchSession = nil
        }
#endif

#if os(iOS) || os(macOS)
        if shouldConnect {
            if session == nil {
                let newSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
                newSession.delegate = self
                session = newSession
            }
            startMultipeerDiscovery()
        } else {
            stopMultipeerDiscovery()
            session?.disconnect()
            session = nil
            peerDisplayNames.removeAll()
            multipeerDeviceIDs.removeAll()
            deviceIDsByPeerDisplayName.removeAll()
            connectedDeviceNames = []
            remotePlayback = nil
            sharedSession = nil
        }
#endif
    }

    private func localPeerInfo() -> SyncPeerInfo {
        SyncPeerInfo(
            id: localDeviceID,
            name: localDeviceName,
            platform: platformName,
            syncModeEnabled: syncModeEnabled,
            credentialSyncEnabled: credentialSyncEnabled,
            hasCredentials: NavidromeAPI.shared.hasCredentials
        )
    }

    private func localPlaybackSnapshot() -> PlaybackSnapshot {
        let player = AudioPlayer.shared
        return PlaybackSnapshot(
            id: localDeviceID,
            deviceName: localDeviceName,
            platform: platformName,
            song: player.currentSong,
            isPlaying: player.isPlaying,
            isBuffering: player.isBuffering,
            prebufferedTrackCount: player.prebufferedTrackCount,
            volume: player.volume,
            currentTime: player.liveCurrentTime,
            duration: player.duration,
            queue: player.queue,
            currentIndex: player.currentIndex,
            updatedAt: Date()
        )
    }

    private func refreshLocalSharedSessionIfNeeded() {
        guard syncModeEnabled, !isApplyingRemoteCommand else { return }
        guard sharedSession?.outputDeviceID == localDeviceID else { return }

        let player = AudioPlayer.shared
        let queue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
        guard !queue.isEmpty else { return }

        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: min(player.currentIndex, queue.count - 1),
            position: player.liveCurrentTime,
            isPlaying: player.isPlaying,
            outputDeviceID: localDeviceID,
            volume: player.volume
        ), applyLocally: false)
    }

    private func sendCurrentSyncState(includeHello: Bool = false) {
        refreshLocalSharedSessionIfNeeded()
        if includeHello {
            broadcastHello()
        }
        broadcastPlaybackState(force: true)
    }

    private func broadcastHello() {
        _ = sendEnvelope(.init(kind: .hello, sender: localPeerInfo(), playback: nil, command: nil, credentials: nil, targetDeviceID: nil))
        if let sharedSession {
            _ = sendEnvelope(.init(
                kind: .playbackSession,
                sender: localPeerInfo(),
                playback: nil,
                playbackSession: sharedSession,
                command: nil,
                credentials: nil,
                targetDeviceID: nil
            ))
        }
    }

    private func broadcastPlaybackState(force: Bool = false) {
        let now = Date()
        let snapshot = localPlaybackSnapshot()
        guard PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: snapshot,
            previousSnapshot: lastBroadcastedPlaybackSnapshot,
            lastBroadcastAt: lastPlaybackBroadcast,
            now: now,
            force: force,
            syncModeEnabled: syncModeEnabled,
            isApplyingRemoteCommand: isApplyingRemoteCommand,
            sharedOutputDeviceID: sharedSession?.outputDeviceID,
            localDeviceID: localDeviceID
        ) else { return }

        let didSend = sendEnvelope(.init(kind: .playbackState, sender: localPeerInfo(), playback: snapshot, command: nil, credentials: nil, targetDeviceID: nil))
        guard PlaybackStateBroadcastDeliveryPolicy.shouldRecordAttempt(didSend: didSend) else { return }
        lastPlaybackBroadcast = now
        lastBroadcastedPlaybackSnapshot = snapshot
    }

    private func broadcastPlaybackTelemetryState() {
        let now = Date()
        guard PlaybackTelemetryBroadcastPolicy.shouldBroadcast(lastBroadcastAt: lastPlaybackTelemetryBroadcast, now: now) else { return }
        lastPlaybackTelemetryBroadcast = now
        broadcastPlaybackState(force: true)
    }

    private func shouldPublishRemotePlayback(_ playback: PlaybackSnapshot) -> Bool {
        PlaybackSyncPolicy.shouldPublishRemotePlayback(playback, current: remotePlayback)
    }

    private func isStalePlaybackSnapshot(_ playback: PlaybackSnapshot) -> Bool {
        PlaybackSyncPolicy.isStalePlaybackSnapshot(playback, current: remotePlayback)
    }

    private func maybeSendCredentialsToInterestedPeers() {
        guard credentialSyncEnabled, let credentials = NavidromeAPI.shared.exportCredentialsForSync() else { return }
        _ = sendEnvelope(.init(kind: .credentials, sender: localPeerInfo(), playback: nil, command: nil, credentials: credentials, targetDeviceID: nil))
    }

    private var selectedRemotePlaybackTargetID: String? {
        validateSelectedPlaybackTarget()
        guard selectedPlaybackTargetID != localDeviceID,
              availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }) else {
            return nil
        }
        return selectedPlaybackTargetID
    }

    private func playbackPositionForTarget(_ targetDeviceID: String?) -> (queue: [Song], index: Int, time: TimeInterval)? {
        if targetDeviceID == nil || targetDeviceID == localDeviceID {
            let player = AudioPlayer.shared
            let queue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
            guard !queue.isEmpty else { return nil }
            return (queue, min(max(player.currentIndex, 0), queue.count - 1), player.liveCurrentTime)
        }

        if let sharedSession, sharedSession.outputDeviceID == targetDeviceID {
            guard !sharedSession.queue.isEmpty else { return nil }
            return (
                sharedSession.queue,
                min(max(sharedSession.currentIndex, 0), sharedSession.queue.count - 1),
                sharedSession.estimatedPosition
            )
        }

        if let remotePlayback, remotePlayback.id == targetDeviceID {
            let queue = remotePlayback.queue.isEmpty ? remotePlayback.song.map { [$0] } ?? [] : remotePlayback.queue
            guard !queue.isEmpty else { return nil }
            return (
                queue,
                min(max(remotePlayback.currentIndex, 0), queue.count - 1),
                remotePlayback.estimatedCurrentTime
            )
        }

        return nil
    }

    private func shouldProcessCommand(_ command: PlaybackCommand) -> Bool {
        guard let commandID = command.commandID else { return true }
        guard !processedCommandIDs.contains(commandID) else { return false }

        processedCommandIDs.insert(commandID)
        processedCommandIDOrder.append(commandID)
        if processedCommandIDOrder.count > 200 {
            let expiredCount = processedCommandIDOrder.count - 200
            let expired = Array(processedCommandIDOrder.prefix(expiredCount))
            processedCommandIDOrder.removeFirst(expiredCount)
            expired.forEach { processedCommandIDs.remove($0) }
        }
        return true
    }

    private func shouldProcessEnvelope(_ envelope: SyncEnvelope) -> Bool {
        guard SyncDuplicatePolicy.shouldProcess(
            envelopeID: envelope.envelopeID,
            processedEnvelopeIDs: processedEnvelopeIDs
        ) else {
            return false
        }

        guard let envelopeID = envelope.envelopeID else { return true }
        processedEnvelopeIDs.insert(envelopeID)
        processedEnvelopeIDOrder.append(envelopeID)

        let trimmedOrder = SyncDuplicatePolicy.trimmedEnvelopeIDOrder(processedEnvelopeIDOrder)
        if trimmedOrder.count != processedEnvelopeIDOrder.count {
            processedEnvelopeIDOrder = trimmedOrder
            processedEnvelopeIDs = Set(trimmedOrder)
        }

        return true
    }

    private func shouldProcessPlaybackState(_ playback: PlaybackSnapshot) -> Bool {
        let fingerprint = PlaybackSnapshotFingerprintPolicy.fingerprint(for: playback)
        guard PlaybackSnapshotFingerprintPolicy.shouldProcess(
            fingerprint: fingerprint,
            processedFingerprints: processedPlaybackSnapshotFingerprints
        ) else {
            return false
        }

        processedPlaybackSnapshotFingerprints.insert(fingerprint)
        processedPlaybackSnapshotFingerprintOrder.append(fingerprint)

        let trimmedOrder = PlaybackSnapshotFingerprintPolicy.trimmedFingerprintOrder(processedPlaybackSnapshotFingerprintOrder)
        if trimmedOrder.count != processedPlaybackSnapshotFingerprintOrder.count {
            processedPlaybackSnapshotFingerprintOrder = trimmedOrder
            processedPlaybackSnapshotFingerprints = Set(trimmedOrder)
        }

        return true
    }

    private func pendingCommandKey(for deviceID: String, action: PlaybackSyncCommandAction) -> String {
        "\(deviceID)|\(PlaybackCommandSyncPolicy.commandFamily(for: action).rawValue)"
    }

    private func pendingCommandDeviceID(for key: String) -> String {
        key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? key
    }

    private func pendingCommandKeys(for deviceID: String) -> [String] {
        pendingTargetedCommands.keys.filter { pendingCommandDeviceID(for: $0) == deviceID }
    }

    @discardableResult
    private func sendCommand(_ command: PlaybackCommand, targetDeviceID: String? = nil) -> Bool {
        guard syncModeEnabled else { return false }
        let command = command.withCommandID()
        let needsAcknowledgment = commandNeedsPlaybackAcknowledgment(command)

        if let targetDeviceID {
            let key = pendingCommandKey(for: targetDeviceID, action: command.action)
            clearPendingCommands(for: targetDeviceID, invalidatedBy: command.action, preservingKey: key)
            if PendingPlaybackCommandPolicy.shouldReplacePendingCommand(
                existingAction: pendingTargetedCommands[key]?.action,
                incomingAction: command.action
            ) {
                pendingTargetedCommandRetryTasks.removeValue(forKey: key)?.cancel()
                pendingTargetedCommandRetryAttempts[key] = 0
            }
            pendingTargetedCommands[key] = command
            pendingTargetedCommandDeadlines[key] = Date().addingTimeInterval(
                PendingPlaybackCommandPolicy.deadlineInterval(needsAcknowledgment: needsAcknowledgment)
            )
        }

        let sent = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), playback: nil, command: command, credentials: nil, targetDeviceID: targetDeviceID))

        if let targetDeviceID {
            schedulePendingCommandRetry(for: targetDeviceID, action: command.action)
        }
        return sent
    }

    @discardableResult
    private func sendEnvelope(_ envelope: SyncEnvelope) -> Bool {
        guard let data = try? encoder.encode(envelope) else { return false }
        var didSend = false

#if os(iOS) || os(watchOS)
        if let watchSession {
            if watchSession.activationState == .activated, watchSession.isReachable {
                let payloadKind = envelope.watchConnectivityPayloadKind
                watchSession.sendMessageData(data, replyHandler: nil) { error in
                    let errorDescription = String(describing: error)
                    Self.enqueueDelegateEvent {
                        DeviceSyncManager.shared.handleEnvelopeSendFailure(
                            kind: payloadKind,
                            transport: .watchConnectivity,
                            errorDescription: errorDescription,
                            fallbackUserInfoPayload: data
                        )
                    }
                }
                didSend = true
            } else if shouldQueueWatchConnectivityEnvelope(envelope, for: watchSession) {
                watchSession.transferUserInfo(["payload": data])
                didSend = true
            }
        }
#endif

#if os(iOS) || os(macOS)
        if let session, !session.connectedPeers.isEmpty {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                didSend = true
            } catch {
                handleEnvelopeSendFailure(
                    kind: envelope.watchConnectivityPayloadKind,
                    transport: .multipeer,
                    errorDescription: String(describing: error)
                )
            }
        }
#endif
        return didSend
    }

    private func handleEnvelopeSendFailure(
        kind: WatchConnectivitySyncPayloadKind,
        transport: SyncTransportKind,
        errorDescription: String,
        fallbackUserInfoPayload: Data? = nil
    ) {
        print("❌ Failed to send \(transport) sync envelope: \(errorDescription)")

#if os(iOS) || os(watchOS)
        if transport == .watchConnectivity,
           let fallbackUserInfoPayload,
           let watchSession,
           WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(
            kind: kind,
            canQueuePayload: canQueueWatchConnectivityPayload(watchSession)
           ) {
            watchSession.transferUserInfo(["payload": fallbackUserInfoPayload])
            print("📦 Queued durable WatchConnectivity payload after send failure")
        }
#endif

        if SyncTransportFailurePolicy.shouldInvalidatePlaybackBroadcastAttempt(kind: kind) {
            lastPlaybackBroadcast = .distantPast
            lastBroadcastedPlaybackSnapshot = nil
        }

#if os(iOS) || os(macOS)
        if transport == .multipeer,
           SyncTransportFailurePolicy.shouldRestartMultipeerDiscoveryAfterSendFailure(hasConnectedPeers: session?.connectedPeers.isEmpty == false) {
            scheduleMultipeerDiscoveryRestart(reason: "send failure")
        }
#endif

        if SyncTransportFailurePolicy.shouldRequestPlaybackRefresh(kind: kind), !isHandlingSyncTransportFailure {
            isHandlingSyncTransportFailure = true
            defer { isHandlingSyncTransportFailure = false }
            requestPlaybackSyncRefresh()
        }
    }

    private func handleEnvelopeData(_ data: Data, fromPeerDisplayName peerDisplayName: String? = nil) {
        guard let envelope = try? decoder.decode(SyncEnvelope.self, from: data) else { return }
        guard envelope.sender.id != localDeviceID else { return }
        guard shouldProcessEnvelope(envelope) else { return }

        peerInfos[envelope.sender.id] = envelope.sender
#if os(iOS) || os(macOS)
        if let peerDisplayName {
            multipeerDeviceIDs.insert(envelope.sender.id)
            deviceIDsByPeerDisplayName[peerDisplayName] = envelope.sender.id
        }
#endif
        connectedDeviceNames = Array(Set(peerInfos.values.map(\.name))).sorted()

        switch envelope.kind {
        case .hello:
            flushPendingCommands(for: envelope.sender.id)
            if credentialSyncEnabled,
               envelope.sender.credentialSyncEnabled,
               !envelope.sender.hasCredentials,
               let credentials = NavidromeAPI.shared.exportCredentialsForSync() {
                _ = sendEnvelope(.init(kind: .credentials, sender: localPeerInfo(), playback: nil, command: nil, credentials: credentials, targetDeviceID: nil))
            }
            sendCurrentSyncState()

        case .syncRequest:
            flushPendingCommands(for: envelope.sender.id)
            sendCurrentSyncState(includeHello: true)

        case .playbackState:
            guard syncModeEnabled, envelope.sender.syncModeEnabled, let playback = envelope.playback else { return }
            let acknowledgingPendingCommandKey = acknowledgingPendingCommandKey(for: playback)
            let isAcknowledgingSnapshot = acknowledgingPendingCommandKey != nil
            guard PlaybackSnapshotReceivePolicy.shouldAccept(
                playback,
                current: remotePlayback,
                isAcknowledgingPendingCommand: isAcknowledgingSnapshot
            ) else { return }
            guard shouldProcessPlaybackState(playback) || isAcknowledgingSnapshot else { return }
            if let acknowledgingPendingCommandKey {
                clearPendingCommand(forKey: acknowledgingPendingCommandKey)
            }
            if shouldPublishRemotePlayback(playback) || isAcknowledgingSnapshot {
                remotePlayback = playback
            }
            flushPendingCommands(for: envelope.sender.id)
            if sharedSession == nil,
               playback.isPlaying,
               !AudioPlayer.shared.isPlaying {
                selectedPlaybackTargetID = playback.id
            }

        case .playbackSession:
            guard syncModeEnabled,
                  envelope.sender.syncModeEnabled,
                  let session = envelope.playbackSession else { return }
            flushPendingCommands(for: envelope.sender.id)
            applySharedSession(session, applyLocally: true)

        case .playbackCommand:
            guard syncModeEnabled, envelope.sender.syncModeEnabled, let command = envelope.command else { return }
            guard PlaybackCommandSyncPolicy.shouldApplyIncomingCommand(command.action) else {
                print("⚠️ Ignoring ambiguous remote playback toggle from \(envelope.sender.name); requesting fresh sync state")
                requestPlaybackSyncRefresh()
                return
            }
            if command.action == .syncQueue {
                guard PlaybackCommandReceivePolicy.shouldApplySyncQueue(
                    targetDeviceID: envelope.targetDeviceID,
                    localDeviceID: localDeviceID,
                    hasSongs: command.songs?.isEmpty == false
                ) else { return }
                guard shouldProcessCommand(command) else { return }
                guard let ownerDeviceID = envelope.targetDeviceID,
                      let songs = command.songs else { return }
                applySharedSession(makeSession(
                    queue: songs,
                    currentIndex: min(command.startingIndex ?? 0, songs.count - 1),
                    position: command.time ?? 0,
                    isPlaying: sharedSession?.isPlaying ?? false,
                    outputDeviceID: ownerDeviceID,
                    revision: nextSessionRevision()
                ), applyLocally: true)
                return
            }

            guard PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
                action: command.action,
                targetDeviceID: envelope.targetDeviceID,
                localDeviceID: localDeviceID
            ) else { return }
            guard shouldProcessCommand(command) else { return }
            clearConflictingPendingCommandIfNeeded(from: envelope.sender.id, incomingAction: command.action)
            apply(command)

        case .credentials:
            flushPendingCommands(for: envelope.sender.id)
            guard credentialSyncEnabled, envelope.sender.credentialSyncEnabled, let credentials = envelope.credentials else { return }
            if NavidromeAPI.shared.importCredentialsIfMissing(credentials) {
                broadcastHello()
            }
        }
    }

    private func clearConflictingPendingCommandIfNeeded(from deviceID: String, incomingAction: PlaybackSyncCommandAction) {
        let key = pendingCommandKey(for: deviceID, action: incomingAction)
        guard PendingPlaybackCommandPolicy.shouldIncomingCommandSupersedePendingCommand(
            pendingAction: pendingTargetedCommands[key]?.action,
            incomingAction: incomingAction
        ) else {
            return
        }

        clearPendingCommand(forKey: key)
    }

    private func apply(_ command: PlaybackCommand) {
        let player = AudioPlayer.shared
        withRemotePlaybackApplication {
            switch command.action {
            case .play:
                player.play()
            case .pause:
                player.pause()
            case .toggle:
                player.togglePlayPause()
            case .next:
                player.next()
            case .previous:
                player.previous()
            case .seek:
                player.seek(to: command.time ?? 0)
            case .setVolume:
                player.volume = clampedVolume(command.volume ?? player.volume)
            case .playQueue:
                guard let songs = command.songs, !songs.isEmpty else { return }
                selectedPlaybackTargetID = localDeviceID
                player.playQueue(
                    songs,
                    startingAt: min(command.startingIndex ?? 0, songs.count - 1),
                    startTime: command.time ?? 0
                )
            case .enqueue:
                guard let songs = command.songs, !songs.isEmpty else { return }
                player.enqueue(songs)
            case .syncQueue:
                guard let songs = command.songs, !songs.isEmpty else { return }
                let ownerDeviceID = sharedSession?.outputDeviceID ?? selectedPlaybackTargetID
                publishSharedSession(makeSession(
                    queue: songs,
                    currentIndex: min(command.startingIndex ?? 0, songs.count - 1),
                    position: command.time ?? 0,
                    isPlaying: sharedSession?.isPlaying ?? false,
                    outputDeviceID: ownerDeviceID
                ))
            case .stop:
                player.stop()
            }
        }

        if command.action != .syncQueue {
            broadcastLocalQueueAsShared()
            broadcastPlaybackState(force: true)
        }
    }

    private func broadcastSharedQueue(ownerDeviceID: String, songs: [Song], currentIndex: Int, currentTime: TimeInterval) {
        guard syncModeEnabled, !songs.isEmpty else { return }
        publishSharedSession(makeSession(
            queue: songs,
            currentIndex: currentIndex,
            position: currentTime,
            isPlaying: sharedSession?.isPlaying ?? false,
            outputDeviceID: ownerDeviceID
        ))
        let command = PlaybackCommand(
            action: .syncQueue,
            songs: songs,
            startingIndex: min(currentIndex, songs.count - 1),
            time: currentTime
        ).withCommandID()
        _ = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), playback: nil, command: command, credentials: nil, targetDeviceID: ownerDeviceID))
    }

    private func mirrorSharedQueue(songs: [Song], currentIndex: Int, currentTime: TimeInterval) {
        guard !songs.isEmpty else { return }
        withRemotePlaybackApplication {
            AudioPlayer.shared.mirrorQueueWithoutPlayback(songs, currentIndex: currentIndex, currentTime: currentTime)
        }
    }

    private func commandNeedsPlaybackAcknowledgment(_ command: PlaybackCommand) -> Bool {
        PlaybackCommandSyncPolicy.needsPlaybackAcknowledgment(command.action)
    }

    private func pendingCommand(_ command: PlaybackCommand, isAcknowledgedBy playback: PlaybackSnapshot) -> Bool {
        PlaybackCommandSyncPolicy.isAcknowledged(
            action: command.action,
            expectedSongs: command.songs,
            expectedIndex: command.startingIndex,
            expectedTime: command.time,
            expectedVolume: command.volume,
            by: playback
        )
    }

    private func isPlaybackSnapshotAcknowledgingPendingCommand(_ playback: PlaybackSnapshot) -> Bool {
        acknowledgingPendingCommandKey(for: playback) != nil
    }

    @discardableResult
    private func acknowledgePendingCommandIfSatisfied(by playback: PlaybackSnapshot) -> Bool {
        guard let key = acknowledgingPendingCommandKey(for: playback) else { return false }
        clearPendingCommand(forKey: key)
        return true
    }

    private func acknowledgingPendingCommandKey(for playback: PlaybackSnapshot) -> String? {
        for key in pendingCommandKeys(for: playback.id) {
            guard let command = pendingTargetedCommands[key],
                  commandNeedsPlaybackAcknowledgment(command),
                  PendingPlaybackAcknowledgmentPolicy.shouldAcceptAcknowledgingSnapshot(
                    playback,
                    current: remotePlayback,
                    action: command.action,
                    expectedSongs: command.songs,
                    expectedIndex: command.startingIndex,
                    expectedTime: command.time,
                    expectedVolume: command.volume
                  ) else {
                continue
            }
            return key
        }
        return nil
    }

    private func clearPendingCommand(for deviceID: String, action: PlaybackSyncCommandAction) {
        clearPendingCommand(forKey: pendingCommandKey(for: deviceID, action: action))
    }

    private func clearPendingCommands(
        for deviceID: String,
        invalidatedBy action: PlaybackSyncCommandAction,
        preservingKey preservedKey: String? = nil
    ) {
        let invalidatedFamilies = PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: action)
        guard !invalidatedFamilies.isEmpty else { return }

        for key in pendingCommandKeys(for: deviceID) where key != preservedKey {
            guard let pendingAction = pendingTargetedCommands[key]?.action else { continue }
            let pendingFamily = PlaybackCommandSyncPolicy.commandFamily(for: pendingAction)
            if invalidatedFamilies.contains(pendingFamily) {
                clearPendingCommand(forKey: key)
            }
        }
    }

    private func clearPendingCommand(forKey key: String) {
        pendingTargetedCommands.removeValue(forKey: key)
        pendingTargetedCommandDeadlines.removeValue(forKey: key)
        pendingTargetedCommandRetryAttempts.removeValue(forKey: key)
        pendingTargetedCommandRetryTasks.removeValue(forKey: key)?.cancel()
    }

    private func flushPendingCommands(for deviceID: String) {
        for key in pendingCommandKeys(for: deviceID) {
            flushPendingCommand(forKey: key)
        }
    }

    private func flushPendingCommand(forKey key: String) {
        guard let command = pendingTargetedCommands[key] else { return }
        let deviceID = pendingCommandDeviceID(for: key)

        if let deadline = pendingTargetedCommandDeadlines[key], Date() > deadline {
            handleExpiredPendingCommand(command, deviceID: deviceID, key: key)
            return
        }

        _ = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), playback: nil, command: command, credentials: nil, targetDeviceID: deviceID))
        schedulePendingCommandRetry(for: deviceID, action: command.action)
    }

    private func handleExpiredPendingCommand(_ command: PlaybackCommand, deviceID: String, key: String) {
        print("⚠️ Dropping unacknowledged sync command \(command.action.rawValue) for \(deviceID)")
        clearPendingCommand(forKey: key)
        if PendingPlaybackCommandExpiryPolicy.shouldInvalidateOptimisticRemotePlayback(
            remotePlaybackID: remotePlayback?.id,
            expiredDeviceID: deviceID
        ) {
            remotePlayback = nil
        }
        requestPlaybackSyncRefresh()
    }

    private func schedulePendingCommandRetry(for deviceID: String, action: PlaybackSyncCommandAction) {
        let key = pendingCommandKey(for: deviceID, action: action)
        guard pendingTargetedCommandRetryTasks[key] == nil else { return }
        let scheduledCommandID = pendingTargetedCommands[key]?.commandID

        let attempt = pendingTargetedCommandRetryAttempts[key, default: 0]
        let delay = PlaybackCommandSyncPolicy.retryDelay(forAttempt: attempt)
        pendingTargetedCommandRetryAttempts[key] = attempt + 1

        pendingTargetedCommandRetryTasks[key] = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.pendingTargetedCommandRetryTasks[key] = nil
            guard PendingPlaybackCommandRetryPolicy.shouldRunRetry(
                pendingCommandID: self.pendingTargetedCommands[key]?.commandID,
                scheduledCommandID: scheduledCommandID
            ) else { return }
            self.flushPendingCommand(forKey: key)
        }
    }

#if os(iOS) || os(watchOS)
    private func shouldQueueWatchConnectivityEnvelope(_ envelope: SyncEnvelope, for session: WCSession) -> Bool {
        guard canQueueWatchConnectivityPayload(session) else { return false }

        switch envelope.kind {
        case .credentials:
            return WatchConnectivitySyncPolicy.shouldQueue(.credentials(hasPayload: envelope.credentials != nil))
        case .hello, .syncRequest:
            return WatchConnectivitySyncPolicy.shouldQueue(envelope.watchConnectivityPayloadKind)
        case .playbackState, .playbackSession, .playbackCommand:
            return WatchConnectivitySyncPolicy.shouldQueue(envelope.watchConnectivityPayloadKind)
        }
    }

    private func canQueueWatchConnectivityPayload(_ session: WCSession) -> Bool {
#if os(iOS)
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
#else
        return session.activationState == .activated
#endif
    }

    private func scheduleWatchConnectivityActivationRetry(reason: String) {
        guard syncModeEnabled || credentialSyncEnabled else { return }
        guard watchConnectivityActivationRetryTask == nil else { return }
        guard WCSession.isSupported() else { return }

        let delay = WatchConnectivityActivationRetryPolicy.retryDelay(forAttempt: watchConnectivityActivationRetryAttempt)
        watchConnectivityActivationRetryAttempt += 1
        print("⏳ Retrying WatchConnectivity activation in \(Int(delay))s after \(reason)")

        watchConnectivityActivationRetryTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.watchConnectivityActivationRetryTask = nil

            let session = self.watchSession ?? WCSession.default
            session.delegate = self
            self.watchSession = session
            if session.activationState != .activated {
                session.activate()
            }
        }
    }
#endif

#if os(iOS) || os(macOS)
    private func startMultipeerDiscovery() {
        guard syncModeEnabled || credentialSyncEnabled else { return }

        if advertiser == nil {
            advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["deviceID": localDeviceID], serviceType: "wrhythm-sync")
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
            print("📡 Sync advertiser started as \(peerID.displayName)")
        }

        if browser == nil {
            browser = MCNearbyServiceBrowser(peer: peerID, serviceType: "wrhythm-sync")
            browser?.delegate = self
            browser?.startBrowsingForPeers()
            print("🔎 Sync browser started as \(peerID.displayName)")
        }
    }

    private func stopMultipeerDiscovery() {
        multipeerRestartTask?.cancel()
        multipeerRestartTask = nil
        inviteRetryTasksByPeerDisplayName.values.forEach { $0.cancel() }
        inviteRetryTasksByPeerDisplayName.removeAll()
        pendingTargetedCommandRetryTasks.values.forEach { $0.cancel() }
        pendingTargetedCommandRetryTasks.removeAll()
        inviteAttemptsByPeerDisplayName.removeAll()
        discoveredMultipeerPeers.removeAll()
        multipeerRestartAttempt = 0

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
    }

    private func scheduleMultipeerDiscoveryRestart(reason: String) {
        guard syncModeEnabled || credentialSyncEnabled else { return }
        guard multipeerRestartTask == nil else { return }

        let delay = min(pow(2.0, Double(multipeerRestartAttempt)), maxMultipeerDiscoveryBackoff)
        multipeerRestartAttempt += 1
        print("⏳ Pausing sync discovery for \(Int(delay))s after \(reason)")

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        inviteRetryTasksByPeerDisplayName.values.forEach { $0.cancel() }
        inviteRetryTasksByPeerDisplayName.removeAll()
        discoveredMultipeerPeers.removeAll()

        multipeerRestartTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.multipeerRestartTask = nil
            self.startMultipeerDiscovery()
        }
    }

    private func resetMultipeerBackoff(for peerID: MCPeerID? = nil) {
        multipeerRestartAttempt = 0

        guard let peerID else { return }
        inviteAttemptsByPeerDisplayName.removeValue(forKey: peerID.displayName)
        inviteRetryTasksByPeerDisplayName.removeValue(forKey: peerID.displayName)?.cancel()
        discoveredMultipeerPeers.removeValue(forKey: peerID.displayName)
    }

    private func scheduleInvite(to peerID: MCPeerID) {
        let key = peerID.displayName
        discoveredMultipeerPeers[key] = peerID
        guard inviteRetryTasksByPeerDisplayName[key] == nil else { return }

        let attempt = inviteAttemptsByPeerDisplayName[key, default: 0]
        guard attempt < maxMultipeerInviteAttempts else {
            inviteAttemptsByPeerDisplayName[key] = 0
            scheduleMultipeerDiscoveryRestart(reason: "repeated failed invites to \(key)")
            return
        }

        let delay = attempt == 0 ? 0 : multipeerInviteTimeout + min(pow(2.0, Double(attempt)), maxMultipeerInviteBackoff)

        inviteRetryTasksByPeerDisplayName[key] = Task { @MainActor in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            self.inviteRetryTasksByPeerDisplayName[key] = nil
            guard self.syncModeEnabled || self.credentialSyncEnabled else { return }
            guard let browser = self.browser, let session = self.session else { return }
            let currentPeerID = self.discoveredMultipeerPeers[key]
            let isAlreadyConnected = session.connectedPeers.contains(where: { $0.displayName == key })
            guard MultipeerInviteRetryPolicy.shouldInvite(
                scheduledPeerDisplayName: key,
                discoveredPeerDisplayName: currentPeerID?.displayName,
                isAlreadyConnected: isAlreadyConnected
            ) else {
                if isAlreadyConnected {
                    self.resetMultipeerBackoff(for: currentPeerID ?? peerID)
                }
                return
            }
            guard let currentPeerID else { return }

            print("📨 Sync peer found, inviting: \(key) (attempt \(attempt + 1))")
            browser.invitePeer(currentPeerID, to: session, withContext: nil, timeout: self.multipeerInviteTimeout)
            self.inviteAttemptsByPeerDisplayName[key] = attempt + 1
            self.scheduleInvite(to: currentPeerID)
        }
    }

    private func removeMultipeerPeer(_ peerID: MCPeerID) {
        peerDisplayNames.removeValue(forKey: peerID)
        discoveredMultipeerPeers.removeValue(forKey: peerID.displayName)
        inviteRetryTasksByPeerDisplayName.removeValue(forKey: peerID.displayName)?.cancel()

        if let deviceID = deviceIDsByPeerDisplayName.removeValue(forKey: peerID.displayName) {
            multipeerDeviceIDs.remove(deviceID)
            peerInfos.removeValue(forKey: deviceID)
            if remotePlayback?.id == deviceID {
                remotePlayback = nil
            }

            if selectedPlaybackTargetID == deviceID {
                selectedPlaybackTargetID = localDeviceID
            }
        }

        connectedDeviceNames = Array(Set(peerInfos.values.map(\.name))).sorted()
    }
#endif
}

#if os(iOS) || os(watchOS)
extension DeviceSyncManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let shouldBootstrap = WatchConnectivityActivationPolicy.shouldBootstrapSync(
            activationSucceeded: activationState == .activated,
            hasError: error != nil
        )
        let activationStateRawValue = activationState.rawValue
        let errorDescription = error.map { String(describing: $0) }
        let shouldRetry = WatchConnectivityActivationRetryPolicy.shouldRetry(
            activationSucceeded: activationState == .activated,
            hasError: error != nil,
            canActivate: WCSession.isSupported()
        )
        Self.enqueueDelegateEvent {
            if shouldBootstrap {
                DeviceSyncManager.shared.watchConnectivityActivationRetryAttempt = 0
                DeviceSyncManager.shared.watchConnectivityActivationRetryTask?.cancel()
                DeviceSyncManager.shared.watchConnectivityActivationRetryTask = nil
                DeviceSyncManager.shared.sendCurrentSyncState(includeHello: true)
            } else {
                print("⚠️ WatchConnectivity activation did not complete; state=\(activationStateRawValue), error=\(errorDescription ?? "none")")
                if shouldRetry {
                    DeviceSyncManager.shared.scheduleWatchConnectivityActivationRetry(reason: "activation failure")
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Self.enqueueDelegateEvent {
            DeviceSyncManager.shared.handleEnvelopeData(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        Self.enqueueDelegateEvent {
            DeviceSyncManager.shared.handleEnvelopeData(data)
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
#endif

#if os(iOS) || os(macOS)
extension DeviceSyncManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peer = SyncPeerHandle(peerID: peerID)
        Self.enqueueDelegateEvent {
            let manager = DeviceSyncManager.shared
            let peerID = peer.peerID
            switch state {
            case .connected:
                manager.resetMultipeerBackoff(for: peerID)
                manager.peerDisplayNames[peerID] = peerID.displayName
                manager.connectedDeviceNames = Array(Set(manager.peerDisplayNames.values)).sorted()
                print("✅ Sync peer connected: \(peerID.displayName)")
                manager.sendCurrentSyncState(includeHello: true)
                manager.maybeSendCredentialsToInterestedPeers()
            case .notConnected:
                print("⚠️ Sync peer disconnected: \(peerID.displayName)")
                manager.removeMultipeerPeer(peerID)
                if (manager.syncModeEnabled || manager.credentialSyncEnabled),
                   manager.peerID.displayName < peerID.displayName {
                    manager.scheduleInvite(to: peerID)
                }
            case .connecting:
                print("🔄 Sync peer connecting: \(peerID.displayName)")
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peerDisplayName = peerID.displayName
        Self.enqueueDelegateEvent {
            DeviceSyncManager.shared.handleEnvelopeData(data, fromPeerDisplayName: peerDisplayName)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension DeviceSyncManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let handler = SyncInvitationHandler(handler: invitationHandler)
        let peerDisplayName = peerID.displayName
        Self.enqueueDelegateEvent {
            let manager = DeviceSyncManager.shared
            let shouldAccept = (manager.syncModeEnabled || manager.credentialSyncEnabled) && manager.session != nil
            print("\(shouldAccept ? "📨" : "🚫") Sync invitation from \(peerDisplayName)")
            handler(shouldAccept, manager.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let errorDescription = String(describing: error)
        Self.enqueueDelegateEvent {
            print("❌ Sync advertiser failed: \(errorDescription)")
            DeviceSyncManager.shared.scheduleMultipeerDiscoveryRestart(reason: "advertiser failure")
        }
    }
}

extension DeviceSyncManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let peer = SyncPeerHandle(peerID: peerID)
        Self.enqueueDelegateEvent {
            let manager = DeviceSyncManager.shared
            let peerID = peer.peerID
            guard manager.syncModeEnabled || manager.credentialSyncEnabled else { return }
            guard manager.session != nil else { return }

            // Avoid dueling invitations. The lexically smaller peer initiates.
            guard manager.peerID.displayName < peerID.displayName else {
                print("👀 Sync peer found, waiting for invite: \(peerID.displayName)")
                return
            }

            manager.scheduleInvite(to: peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peer = SyncPeerHandle(peerID: peerID)
        Self.enqueueDelegateEvent {
            let manager = DeviceSyncManager.shared
            let peerID = peer.peerID
            print("⚠️ Sync peer lost: \(peerID.displayName)")
            manager.discoveredMultipeerPeers.removeValue(forKey: peerID.displayName)
            manager.inviteRetryTasksByPeerDisplayName.removeValue(forKey: peerID.displayName)?.cancel()
            manager.removeMultipeerPeer(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let errorDescription = String(describing: error)
        Self.enqueueDelegateEvent {
            print("❌ Sync browser failed: \(errorDescription)")
            DeviceSyncManager.shared.scheduleMultipeerDiscoveryRestart(reason: "browser failure")
        }
    }
}
#endif
