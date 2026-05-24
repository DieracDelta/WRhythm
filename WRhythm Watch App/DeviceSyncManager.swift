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

struct SyncedCredentials: Codable, Sendable {
    let baseURL: String
    let username: String
    let password: String
    let issuedAt: Date

    init(baseURL: String, username: String, password: String, issuedAt: Date) {
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

enum WatchConnectivitySyncPayloadKind: Sendable {
    case hello
    case syncRequest
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
        case .playbackSession, .playbackCommand:
            return false
        }
    }
}

struct WatchConnectivitySendFailurePolicy: Sendable {
    nonisolated static func shouldFallbackToUserInfo(kind: WatchConnectivitySyncPayloadKind, canQueuePayload: Bool) -> Bool {
        canQueuePayload && WatchConnectivitySyncPolicy.shouldQueue(kind)
    }
}

struct CredentialSyncBootstrapPolicy: Sendable {
    static func shouldAuthorizeImportOnBootstrap(localCredentialSyncEnabled: Bool, localHasCredentials: Bool) -> Bool {
        localCredentialSyncEnabled && !localHasCredentials
    }

    static func shouldOfferCredentials(localCredentialSyncEnabled: Bool, localHasCredentials: Bool) -> Bool {
        localCredentialSyncEnabled && localHasCredentials
    }

    static func shouldRequestCredentialsFromHello(
        localCredentialSyncEnabled: Bool,
        localHasCredentials: Bool,
        senderCredentialSyncEnabled: Bool,
        senderHasCredentials: Bool
    ) -> Bool {
        localCredentialSyncEnabled
            && !localHasCredentials
            && senderCredentialSyncEnabled
            && senderHasCredentials
    }

    static func shouldOfferCredentialsToRequester(
        localCredentialSyncEnabled: Bool,
        localHasCredentials: Bool,
        requesterCredentialSyncEnabled: Bool,
        requesterHasCredentials: Bool
    ) -> Bool {
        shouldOfferCredentials(
            localCredentialSyncEnabled: localCredentialSyncEnabled,
            localHasCredentials: localHasCredentials
        ) && requesterCredentialSyncEnabled && !requesterHasCredentials
    }
}

struct SyncRequestTargetPolicy: Sendable {
    static func shouldHandle(targetDeviceID: String?, localDeviceID: String) -> Bool {
        guard let targetDeviceID else { return true }
        return targetDeviceID == localDeviceID
    }
}

enum SyncTransportKind: Sendable {
    case watchConnectivity
    case multipeer
}

enum SyncPlatformKind: String, Sendable {
    case iPhone
    case mac
    case appleWatch
    case other

    init(platformName: String) {
        switch platformName {
        case "iPhone":
            self = .iPhone
        case "Mac":
            self = .mac
        case "Apple Watch":
            self = .appleWatch
        default:
            self = .other
        }
    }
}

struct SyncTransportAvailabilityPolicy: Sendable {
    static func canUseWatchConnectivity(local: SyncPlatformKind, remote: SyncPlatformKind) -> Bool {
        (local == .iPhone && remote == .appleWatch) || (local == .appleWatch && remote == .iPhone)
    }

    static func canUseMultipeer(_ platform: SyncPlatformKind) -> Bool {
        platform == .iPhone || platform == .mac
    }

    static func canDirectlyDiscover(local: SyncPlatformKind, remote: SyncPlatformKind) -> Bool {
        canUseWatchConnectivity(local: local, remote: remote) || (canUseMultipeer(local) && canUseMultipeer(remote))
    }
}

struct SyncBridgeRelayPolicy: Sendable {
    static func shouldRelay(
        kind: WatchConnectivitySyncPayloadKind,
        receivedVia: SyncTransportKind,
        localPlatform: SyncPlatformKind,
        hasDestinationTransport: Bool
    ) -> Bool {
        guard localPlatform == .iPhone, hasDestinationTransport else { return false }

        switch kind {
        case .hello, .syncRequest, .playbackSession, .playbackCommand:
            return true
        case .credentials(let hasPayload):
            return hasPayload
        }
    }
}

struct PlaybackTargetSelectionPolicy: Sendable {
    static func isSelectable(
        localPlatform: SyncPlatformKind,
        remotePlatform: SyncPlatformKind,
        hasDirectMultipeer: Bool
    ) -> Bool {
        if hasDirectMultipeer {
            return true
        }

        return SyncTransportAvailabilityPolicy.canUseWatchConnectivity(local: localPlatform, remote: remotePlatform)
    }
}

struct SyncTransportFailurePolicy: Sendable {
    static func shouldInvalidatePlaybackBroadcastAttempt(kind: WatchConnectivitySyncPayloadKind) -> Bool {
        switch kind {
        case .playbackSession, .playbackCommand:
            return true
        case .hello, .syncRequest, .credentials:
            return false
        }
    }

    static func shouldRequestPlaybackRefresh(kind: WatchConnectivitySyncPayloadKind) -> Bool {
        switch kind {
        case .playbackSession, .playbackCommand:
            return true
        case .hello, .syncRequest, .credentials:
            return false
        }
    }

    static func shouldRestartMultipeerDiscoveryAfterSendFailure(hasConnectedPeers: Bool) -> Bool {
        hasConnectedPeers
    }
}

struct SyncManualSearchPolicy: Sendable {
    static func shouldSearch(syncModeEnabled: Bool, credentialSyncEnabled: Bool) -> Bool {
        syncModeEnabled || credentialSyncEnabled
    }
}

struct WatchConnectivityActivationPolicy: Sendable {
    nonisolated static func shouldBootstrapSync(activationSucceeded: Bool, hasError: Bool) -> Bool {
        activationSucceeded && !hasError
    }

    nonisolated static func shouldBootstrapConfiguredSession(
        isActivated: Bool,
        activationInProgress: Bool,
        hasBootstrapped: Bool
    ) -> Bool {
        isActivated && !activationInProgress && !hasBootstrapped
    }

    nonisolated static func shouldStartActivation(
        isSupported: Bool,
        isNotActivated: Bool,
        activationInProgress: Bool
    ) -> Bool {
        isSupported && isNotActivated && !activationInProgress
    }
}

struct WatchConnectivityPayloadQueuePolicy: Sendable {
    nonisolated static func canQueueDurablePayload(activationSucceeded: Bool) -> Bool {
        activationSucceeded
    }
}

struct WatchConnectivityCredentialBootstrapPolicy: Sendable {
    nonisolated static func shouldRequestCredentialsOnBootstrap(
        credentialSyncEnabled: Bool,
        localHasCredentials: Bool
    ) -> Bool {
        credentialSyncEnabled && !localHasCredentials
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
    static func shouldImport(
        incomingIssuedAt: Date,
        localClearedAt: Date,
        credentialSyncAuthorizedAt: Date
    ) -> Bool {
        incomingIssuedAt > localClearedAt || credentialSyncAuthorizedAt > localClearedAt
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

    static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attempt))), maxRetryDelay)
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

struct PlaybackControlTargetPolicy: Sendable {
    static func resolvedDefaultRemoteTargetID(
        selectedTargetID: String,
        localDeviceID: String,
        availableTargetIDs: Set<String>
    ) -> String? {
        guard selectedTargetID != localDeviceID,
              availableTargetIDs.contains(selectedTargetID) else {
            return nil
        }

        return selectedTargetID
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

struct PendingPlaybackCommandRetryPolicy: Sendable {
    static func shouldRunRetry(pendingCommandID: String?, scheduledCommandID: String?) -> Bool {
        pendingCommandID == scheduledCommandID
    }
}

struct PendingPlaybackUpdatePolicy: Sendable {
    static func shouldApplyUpdate(hasPendingCommandForDevice: Bool, isAcknowledgingPendingCommand: Bool) -> Bool {
        !hasPendingCommandForDevice || isAcknowledgingPendingCommand
    }
}

struct PendingPlaybackSessionAcknowledgmentPolicy: Sendable {
    static func shouldAcceptAcknowledgingSession(
        _ session: PlaybackSession,
        action: PlaybackSyncCommandAction,
        expectedSongs: [Song]? = nil,
        expectedIndex: Int? = nil,
        expectedTime: TimeInterval? = nil,
        expectedVolume: Double? = nil,
        now: Date = Date()
    ) -> Bool {
        switch action {
        case .play:
            return session.isPlaying
        case .pause:
            return !session.isPlaying
        case .seek:
            guard let expectedTime else { return false }
            return abs(session.estimatedPosition(at: now) - expectedTime) <= PlaybackCommandSyncPolicy.seekAcknowledgmentTolerance
        case .setVolume:
            guard let expectedVolume, let actualVolume = session.volume else { return false }
            return abs(expectedVolume - actualVolume) < PlaybackCommandSyncPolicy.volumeAcknowledgmentTolerance
        case .next, .previous:
            guard let expectedIndex else { return false }
            return session.currentIndex == expectedIndex
        case .playQueue, .syncQueue:
            guard let expectedSongs, !expectedSongs.isEmpty else { return false }
            let expectedIndex = min(max(expectedIndex ?? 0, 0), expectedSongs.count - 1)
            return session.queue.map(\.id) == expectedSongs.map(\.id)
                && session.currentIndex == expectedIndex
                && session.currentSong?.id == expectedSongs[expectedIndex].id
        case .enqueue:
            guard let expectedSongs, !expectedSongs.isEmpty else { return false }
            return containsContiguousSongIDs(expectedSongs.map(\.id), in: session.queue.map(\.id))
        case .stop:
            return !session.isPlaying && session.queue.isEmpty
        case .toggle:
            return false
        }
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

struct RemoteCommandApplicationState: Sendable {
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
        remoteQueueMatchesLocal: Bool,
        localIsPlaybackOutput: Bool = false
    ) -> PlaybackDisplayVisibility {
        let showsLocal = hasLocalSong && !shouldHideLocal(
            localIsPlaying: localIsPlaying,
            hasActiveSharedPlayback: hasActiveSharedPlayback,
            remoteQueueMatchesLocal: remoteQueueMatchesLocal,
            localIsPlaybackOutput: localIsPlaybackOutput
        )
        let showsRemote = hasRemotePlayback && !shouldHideRemote(
            localIsPlaying: localIsPlaying,
            hasActiveSharedPlayback: hasActiveSharedPlayback,
            remoteQueueMatchesLocal: remoteQueueMatchesLocal,
            localIsPlaybackOutput: localIsPlaybackOutput
        )
        return PlaybackDisplayVisibility(showsLocal: showsLocal, showsRemote: showsRemote)
    }

    private static func shouldHideLocal(
        localIsPlaying: Bool,
        hasActiveSharedPlayback: Bool,
        remoteQueueMatchesLocal: Bool,
        localIsPlaybackOutput: Bool
    ) -> Bool {
        if localIsPlaybackOutput {
            return hasActiveSharedPlayback
        }
        return hasActiveSharedPlayback || (remoteQueueMatchesLocal && !localIsPlaying)
    }

    private static func shouldHideRemote(
        localIsPlaying: Bool,
        hasActiveSharedPlayback: Bool,
        remoteQueueMatchesLocal: Bool,
        localIsPlaybackOutput: Bool
    ) -> Bool {
        if localIsPlaybackOutput, remoteQueueMatchesLocal {
            return true
        }
        return remoteQueueMatchesLocal && localIsPlaying && !hasActiveSharedPlayback
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
        let currentSongMatches = localState.currentSongID == sessionSong.id
        let currentIndexMatches = localState.currentIndex == session.currentIndex
        let queueMatches = localState.queueIDs == session.queue.map(\.id)

        return PlaybackSessionReconciliationPlan(
            shouldStop: false,
            shouldReplaceQueue: !currentSongMatches || !currentIndexMatches || !queueMatches,
            shouldSeek: !currentSongMatches || abs(localState.currentTime - sessionPosition) > seekDriftTolerance,
            shouldSetVolume: session.volume.map { abs(localState.volume - $0) > volumeTolerance } ?? false,
            shouldPlay: session.isPlaying && !localState.isPlaying,
            shouldPause: !session.isPlaying && (localState.isPlaying || !currentSongMatches)
        )
    }
}

struct PlaybackSessionSnapshotPolicy: Sendable {
    static func snapshot(
        from session: PlaybackSession,
        deviceName: String,
        platform: String,
        now: Date = Date()
    ) -> PlaybackSnapshot? {
        guard let song = session.currentSong else { return nil }

        return PlaybackSnapshot(
            id: session.outputDeviceID,
            deviceName: deviceName,
            platform: platform,
            song: song,
            isPlaying: session.isPlaying,
            isBuffering: nil,
            prebufferedTrackCount: nil,
            volume: session.volume,
            currentTime: session.estimatedPosition(at: now),
            duration: TimeInterval(song.duration ?? 0),
            queue: session.queue,
            currentIndex: session.currentIndex,
            updatedAt: now
        )
    }
}

struct LocalPlaybackOwnershipPolicy: Sendable {
    static func shouldPublishLocalPlayback(
        sharedOutputDeviceID: String?,
        localDeviceID: String,
        selectedPlaybackTargetID: String,
        hasLocalPlayback: Bool,
        isLocalPlaying: Bool,
        isExplicitLocalPlaybackIntent: Bool = false
    ) -> Bool {
        guard let sharedOutputDeviceID else { return true }
        return sharedOutputDeviceID == localDeviceID
            || isLocalPlaying
            || isExplicitLocalPlaybackIntent
            || (selectedPlaybackTargetID == localDeviceID && hasLocalPlayback)
    }
}

struct LocalPlaybackPublicationPolicy: Sendable {
    static func publishedIsPlaying(playerIsPlaying: Bool, intendedIsPlaying: Bool?) -> Bool {
        intendedIsPlaying ?? playerIsPlaying
    }
}

struct SyncStateRefreshPublicationPolicy: Sendable {
    static func shouldPublishLocalPlayback(
        sharedOutputDeviceID: String?,
        localDeviceID: String,
        hasLocalPlayback: Bool
    ) -> Bool {
        guard hasLocalPlayback else { return false }
        guard let sharedOutputDeviceID else { return true }
        return sharedOutputDeviceID == localDeviceID
    }

    static func shouldRebroadcastSharedPlayback(
        sharedOutputDeviceID: String?,
        localDeviceID: String
    ) -> Bool {
        sharedOutputDeviceID == localDeviceID
    }
}

struct ConnectivityLossPlaybackPolicy: Sendable {
    static func sessionAfterDisconnectedOutput(
        disconnectedDeviceID: String,
        currentSession: PlaybackSession?,
        localDeviceID: String,
        disconnectedAt: Date = Date()
    ) -> PlaybackSession? {
        guard let currentSession,
              currentSession.outputDeviceID == disconnectedDeviceID,
              currentSession.isPlaying else {
            return nil
        }

        return PlaybackSession(
            id: currentSession.id,
            revision: currentSession.revision,
            queue: currentSession.queue,
            currentIndex: currentSession.currentIndex,
            position: currentSession.estimatedPosition(at: disconnectedAt),
            isPlaying: false,
            volume: currentSession.volume,
            outputDeviceID: currentSession.outputDeviceID,
            updatedAt: disconnectedAt,
            updatedByDeviceID: localDeviceID
        )
    }
}

struct LocalPlaybackPublicationPositionPolicy: Sendable {
    static let liveTimeTolerance: TimeInterval = 1

    static func publishedPosition(
        playerLiveTime: TimeInterval,
        logicalCurrentTime: TimeInterval,
        previousSession: PlaybackSession?,
        queueIDs: [String],
        currentSongID: String?,
        currentIndex: Int
    ) -> TimeInterval {
        let liveTime = sanitized(playerLiveTime)
        let logicalTime = sanitized(logicalCurrentTime)

        guard let previousSession,
              previousSession.queue.map(\.id) == queueIDs,
              previousSession.currentSong?.id == currentSongID,
              previousSession.currentIndex == currentIndex else {
            return logicalTime
        }

        return abs(liveTime - logicalTime) <= liveTimeTolerance ? liveTime : logicalTime
    }

    private static func sanitized(_ time: TimeInterval) -> TimeInterval {
        max(0, time.isFinite ? time : 0)
    }
}

struct LocalPlaybackDisplayStatePolicy: Sendable {
    static func effectiveIsPlaying(
        playerIsPlaying: Bool,
        sharedSession: PlaybackSession?,
        localDeviceID: String,
        localQueueIDs: [String],
        localCurrentSongID: String?,
        localCurrentIndex: Int
    ) -> Bool {
        guard let sharedSession,
              sharedSession.outputDeviceID == localDeviceID,
              let sessionSong = sharedSession.currentSong,
              localCurrentSongID == sessionSong.id,
              localCurrentIndex == sharedSession.currentIndex,
              localQueueIDs == sharedSession.queue.map(\.id) else {
            return playerIsPlaying
        }

        return sharedSession.isPlaying
    }
}

struct RemoteCommandLocalPublicationPolicy: Sendable {
    static func intendedIsPlaying(after action: PlaybackSyncCommandAction) -> Bool? {
        switch action {
        case .play, .next, .previous, .playQueue:
            return true
        case .pause, .stop:
            return false
        case .toggle, .seek, .setVolume, .enqueue, .syncQueue:
            return nil
        }
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
        case playbackSession
        case playbackCommand
        case credentials
    }

    let envelopeID: String?
    let kind: Kind
    let sender: SyncPeerInfo
    let playbackSession: PlaybackSession?
    let command: PlaybackCommand?
    let credentials: SyncedCredentials?
    let targetDeviceID: String?

    init(
        envelopeID: String = UUID().uuidString,
        kind: Kind,
        sender: SyncPeerInfo,
        playbackSession: PlaybackSession? = nil,
        command: PlaybackCommand?,
        credentials: SyncedCredentials?,
        targetDeviceID: String?
    ) {
        self.envelopeID = envelopeID
        self.kind = kind
        self.sender = sender
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
        }
    }

    @Published var credentialSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(credentialSyncEnabled, forKey: Self.credentialSyncKey)
            configureTransports()
            if credentialSyncEnabled {
                NavidromeAPI.shared.authorizeCredentialImportFromTrustedSync()
                requestCredentialsFromPeers()
                maybeSendCredentialsToInterestedPeers()
            }
            broadcastHello()
        }
    }

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
    private var remoteCommandApplicationState = RemoteCommandApplicationState()
    private var isApplyingRemoteCommand: Bool {
        remoteCommandApplicationState.isApplying
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
    private var isHandlingSyncTransportFailure = false
    private let sharedSessionID: String
#if os(iOS) || os(watchOS)
    private var watchSession: WCSession?
    private var isWatchConnectivityActivationInProgress = false
    private var hasBootstrappedWatchConnectivitySession = false
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
        bootstrapCredentialSyncIfNeeded()
    }

    nonisolated private static func enqueueDelegateEvent(_ operation: @escaping @MainActor @Sendable () -> Void) {
        delegateEventSubmitter.enqueue(operation)
    }

    private func withRemoteCommandApplication(_ body: () -> Void) {
        remoteCommandApplicationState.begin()
        defer { remoteCommandApplicationState.end() }
        body()
    }

    var hasActiveRemotePlayback: Bool {
        guard syncModeEnabled, let sharedSession else { return false }
        return sharedSession.outputDeviceID != localDeviceID && sharedSession.currentSong != nil
    }

    var isLocalPlaybackOutput: Bool {
        guard syncModeEnabled, let sharedSession else { return true }
        return sharedSession.outputDeviceID == localDeviceID
    }

    var localPlaybackIsPlayingForDisplay: Bool {
        let player = AudioPlayer.shared
        return LocalPlaybackDisplayStatePolicy.effectiveIsPlaying(
            playerIsPlaying: player.isPlaying,
            sharedSession: sharedSession,
            localDeviceID: localDeviceID,
            localQueueIDs: player.queue.map(\.id),
            localCurrentSongID: player.currentSong?.id,
            localCurrentIndex: player.currentIndex
        )
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
            deviceName: outputPeer?.name ?? "Remote Device",
            platform: outputPeer?.platform ?? "Device"
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

        return targets
    }

    private func isPeerSelectable(_ peer: SyncPeerInfo) -> Bool {
        let localPlatform = SyncPlatformKind(platformName: platformName)
        let remotePlatform = SyncPlatformKind(platformName: peer.platform)
#if os(iOS) || os(macOS)
        return PlaybackTargetSelectionPolicy.isSelectable(
            localPlatform: localPlatform,
            remotePlatform: remotePlatform,
            hasDirectMultipeer: multipeerDeviceIDs.contains(peer.id)
        )
#else
        return PlaybackTargetSelectionPolicy.isSelectable(
            localPlatform: localPlatform,
            remotePlatform: remotePlatform,
            hasDirectMultipeer: false
        )
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

    var localPlaybackTargetID: String {
        localDeviceID
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
        _ = sendEnvelope(.init(kind: .syncRequest, sender: localPeerInfo(), command: nil, credentials: nil, targetDeviceID: nil))
        sendCurrentSyncState(includeHello: true)
    }

    func searchForNearbyDevices() {
        guard SyncManualSearchPolicy.shouldSearch(
            syncModeEnabled: syncModeEnabled,
            credentialSyncEnabled: credentialSyncEnabled
        ) else { return }

        configureTransports()

#if os(iOS) || os(macOS)
        restartMultipeerDiscoveryForManualSearch()
#endif

        _ = sendEnvelope(.init(kind: .syncRequest, sender: localPeerInfo(), command: nil, credentials: nil, targetDeviceID: nil))
        sendAuthoritativeSyncState(includeHello: true)
        requestCredentialsFromPeers()
        maybeSendCredentialsToInterestedPeers()
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
            withRemoteCommandApplication {
                guard let song = session.currentSong else {
                    if plan.shouldStop {
                        player.stop()
                    }
                    return
                }

                let currentMatches = localState.currentSongID == song.id

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
            withRemoteCommandApplication {
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
        } else {
            baseQueue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
            currentIndex = min(player.currentIndex, max(baseQueue.count - 1, 0))
        }

        let sharedTargetFinished = sharedSession?.outputDeviceID == selectedPlaybackTargetID
            && sharedSession?.isFinishedAtQueueEnd == true
        let shouldStartAppendedSongs = sharedTargetFinished
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
            broadcastLocalQueueAsShared(
                isExplicitLocalPlaybackIntent: true,
                intendedIsPlaying: isPlaying
            )
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

    @discardableResult
    func removeSharedQueueItem(at index: Int) -> Bool {
        guard syncModeEnabled,
              let sharedSession,
              sharedSession.queue.indices.contains(index),
              index != sharedSession.currentIndex else {
            return false
        }

        var queue = sharedSession.queue
        queue.remove(at: index)
        guard !queue.isEmpty else { return false }

        let currentIndex = index < sharedSession.currentIndex
            ? sharedSession.currentIndex - 1
            : min(sharedSession.currentIndex, queue.count - 1)
        let didMutateLocalQueue = mutateLocalQueueIfBackingSharedSession {
            AudioPlayer.shared.removeQueueItem(at: index)
        }

        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: currentIndex,
            position: sharedSession.estimatedPosition,
            isPlaying: sharedSession.isPlaying,
            outputDeviceID: sharedSession.outputDeviceID,
            volume: sharedSession.volume
        ), applyLocally: !didMutateLocalQueue)
        return true
    }

    @discardableResult
    func clearSharedQueueKeepingCurrent() -> Bool {
        guard syncModeEnabled, let sharedSession, !sharedSession.queue.isEmpty else { return false }
        let safeIndex = min(max(sharedSession.currentIndex, 0), sharedSession.queue.count - 1)
        let retainedQueue = [sharedSession.queue[safeIndex]]
        guard sharedSession.queue.map(\.id) != retainedQueue.map(\.id) else { return false }

        let didMutateLocalQueue = mutateLocalQueueIfBackingSharedSession {
            AudioPlayer.shared.clearQueueKeepingCurrent()
        }

        publishSharedSession(makeSession(
            queue: retainedQueue,
            currentIndex: 0,
            position: sharedSession.estimatedPosition,
            isPlaying: sharedSession.isPlaying,
            outputDeviceID: sharedSession.outputDeviceID,
            volume: sharedSession.volume
        ), applyLocally: !didMutateLocalQueue)
        return true
    }

    private func mutateLocalQueueIfBackingSharedSession(_ mutation: () -> Bool) -> Bool {
        guard sharedSession?.outputDeviceID == localDeviceID,
              AudioPlayer.shared.queue.map(\.id) == sharedSession?.queue.map(\.id) else {
            return false
        }
        return mutation()
    }

    func takeOverRemotePlayback() {
        guard syncModeEnabled, let sharedPlayback = activeSharedPlayback, let song = sharedPlayback.song else { return }
        selectedPlaybackTargetID = localDeviceID
        let queue = sharedPlayback.queue.isEmpty ? [song] : sharedPlayback.queue
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: sharedPlayback.currentIndex,
            position: sharedPlayback.estimatedCurrentTime,
            isPlaying: sharedPlayback.isPlaying,
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
            position: localPlaybackPublishedPosition(queue: queue, currentIndex: index),
            isPlaying: player.isPlaying,
            outputDeviceID: targetID
        ))
    }

    func broadcastLocalQueueAsShared(
        isExplicitLocalPlaybackIntent: Bool = false,
        intendedIsPlaying: Bool? = nil
    ) {
        guard syncModeEnabled, !isApplyingRemoteCommand else { return }
        let player = AudioPlayer.shared
        let isPlaying = LocalPlaybackPublicationPolicy.publishedIsPlaying(
            playerIsPlaying: player.isPlaying,
            intendedIsPlaying: intendedIsPlaying
        )
        guard LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: sharedSession?.outputDeviceID,
            localDeviceID: localDeviceID,
            selectedPlaybackTargetID: validSelectedPlaybackTargetID,
            hasLocalPlayback: player.currentSong != nil,
            isLocalPlaying: isPlaying,
            isExplicitLocalPlaybackIntent: isExplicitLocalPlaybackIntent
        ) else { return }
        let queue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
        guard !queue.isEmpty else { return }
        let currentIndex = min(player.currentIndex, queue.count - 1)
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: currentIndex,
            position: localPlaybackPublishedPosition(queue: queue, currentIndex: currentIndex),
            isPlaying: isPlaying,
            outputDeviceID: localDeviceID,
            volume: player.volume
        ), applyLocally: false)
    }

    private func localPlaybackPublishedPosition(queue: [Song], currentIndex: Int) -> TimeInterval {
        let player = AudioPlayer.shared
        return LocalPlaybackPublicationPositionPolicy.publishedPosition(
            playerLiveTime: player.liveCurrentTime,
            logicalCurrentTime: player.currentTime,
            previousSession: sharedSession,
            queueIDs: queue.map(\.id),
            currentSongID: player.currentSong?.id,
            currentIndex: currentIndex
        )
    }

    func credentialsDidChange() {
        broadcastHello()
        maybeSendCredentialsToInterestedPeers()
    }

    func requestCredentialSyncNow() {
        guard credentialSyncEnabled else { return }
        NavidromeAPI.shared.authorizeCredentialImportFromTrustedSync()
        configureTransports()
        broadcastHello()
        requestCredentialsFromPeers()
        maybeSendCredentialsToInterestedPeers()
    }

    func disableCredentialSyncAfterLocalLogout() {
        guard credentialSyncEnabled else { return }
        credentialSyncEnabled = false
    }

#if os(iOS) || os(watchOS)
    private func bootstrapWatchConnectivitySync() {
        hasBootstrappedWatchConnectivitySession = true
        watchConnectivityActivationRetryAttempt = 0
        watchConnectivityActivationRetryTask?.cancel()
        watchConnectivityActivationRetryTask = nil
        sendCurrentSyncState(includeHello: true)
        maybeSendCredentialsToInterestedPeers()
        if WatchConnectivityCredentialBootstrapPolicy.shouldRequestCredentialsOnBootstrap(
            credentialSyncEnabled: credentialSyncEnabled,
            localHasCredentials: NavidromeAPI.shared.hasCredentials
        ) {
            NavidromeAPI.shared.authorizeCredentialImportFromTrustedSync()
            requestCredentialsFromPeers()
        }
    }

    private func bootstrapAlreadyActivatedWatchConnectivitySessionIfNeeded(_ session: WCSession) {
        guard WatchConnectivityActivationPolicy.shouldBootstrapConfiguredSession(
            isActivated: session.activationState == .activated,
            activationInProgress: isWatchConnectivityActivationInProgress,
            hasBootstrapped: hasBootstrappedWatchConnectivitySession
        ) else { return }
        bootstrapWatchConnectivitySync()
    }
#endif

    private func bootstrapCredentialSyncIfNeeded() {
        if CredentialSyncBootstrapPolicy.shouldAuthorizeImportOnBootstrap(
            localCredentialSyncEnabled: credentialSyncEnabled,
            localHasCredentials: NavidromeAPI.shared.hasCredentials
        ) {
            NavidromeAPI.shared.authorizeCredentialImportFromTrustedSync()
            requestCredentialsFromPeers()
        }
        maybeSendCredentialsToInterestedPeers()
    }

    private func observePlayback() {
        let player = AudioPlayer.shared

        Publishers.CombineLatest4(player.$currentSong, player.$isPlaying, player.$queue, player.$currentIndex)
            .sink { [weak self] _, _, _, _ in
                guard let self else { return }
                self.broadcastLocalQueueAsShared()
            }
            .store(in: &cancellables)

        player.$volume
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { [weak self] _ in
                guard let self, !self.isApplyingRemoteCommand else { return }
                self.broadcastLocalQueueAsShared()
            }
            .store(in: &cancellables)
    }

    private func configureTransports() {
        let shouldConnect = syncModeEnabled || credentialSyncEnabled

#if os(iOS)
        if shouldConnect, WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            if WatchConnectivityActivationPolicy.shouldStartActivation(
                isSupported: true,
                isNotActivated: session.activationState == .notActivated,
                activationInProgress: isWatchConnectivityActivationInProgress
            ) {
                isWatchConnectivityActivationInProgress = true
                hasBootstrappedWatchConnectivitySession = false
                session.activate()
            }
            watchSession = session
            bootstrapAlreadyActivatedWatchConnectivitySessionIfNeeded(session)
        } else {
            watchConnectivityActivationRetryTask?.cancel()
            watchConnectivityActivationRetryTask = nil
            hasBootstrappedWatchConnectivitySession = false
            watchSession = nil
        }
#elseif os(watchOS)
        if shouldConnect, WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            if WatchConnectivityActivationPolicy.shouldStartActivation(
                isSupported: true,
                isNotActivated: session.activationState == .notActivated,
                activationInProgress: isWatchConnectivityActivationInProgress
            ) {
                isWatchConnectivityActivationInProgress = true
                hasBootstrappedWatchConnectivitySession = false
                session.activate()
            }
            watchSession = session
            bootstrapAlreadyActivatedWatchConnectivitySessionIfNeeded(session)
        } else {
            watchConnectivityActivationRetryTask?.cancel()
            watchConnectivityActivationRetryTask = nil
            hasBootstrappedWatchConnectivitySession = false
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

    private func refreshLocalSharedSessionIfNeeded() {
        guard syncModeEnabled, !isApplyingRemoteCommand else { return }

        let player = AudioPlayer.shared
        let queue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
        let currentIndex = min(player.currentIndex, queue.count - 1)
        guard SyncStateRefreshPublicationPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: sharedSession?.outputDeviceID,
            localDeviceID: localDeviceID,
            hasLocalPlayback: !queue.isEmpty
        ) else { return }

        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: currentIndex,
            position: localPlaybackPublishedPosition(queue: queue, currentIndex: currentIndex),
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
    }

    private func sendAuthoritativeSyncState(includeHello: Bool = false) {
        refreshLocalSharedSessionIfNeeded()
        if includeHello {
            broadcastPeerPresence()
        }

        guard SyncStateRefreshPublicationPolicy.shouldRebroadcastSharedPlayback(
            sharedOutputDeviceID: sharedSession?.outputDeviceID,
            localDeviceID: localDeviceID
        ), let sharedSession else {
            return
        }

        broadcastSharedSession(sharedSession)
    }

    private func broadcastPeerPresence() {
        _ = sendEnvelope(.init(kind: .hello, sender: localPeerInfo(), command: nil, credentials: nil, targetDeviceID: nil))
    }

    private func broadcastHello() {
        broadcastPeerPresence()
        guard SyncStateRefreshPublicationPolicy.shouldRebroadcastSharedPlayback(
            sharedOutputDeviceID: sharedSession?.outputDeviceID,
            localDeviceID: localDeviceID
        ), let sharedSession else {
            return
        }

        broadcastSharedSession(sharedSession)
    }

    private func broadcastSharedSession(_ sharedSession: PlaybackSession) {
        _ = sendEnvelope(.init(
            kind: .playbackSession,
            sender: localPeerInfo(),
            playbackSession: sharedSession,
            command: nil,
            credentials: nil,
            targetDeviceID: nil
        ))
    }

    private func maybeSendCredentialsToInterestedPeers() {
        guard CredentialSyncBootstrapPolicy.shouldOfferCredentials(
            localCredentialSyncEnabled: credentialSyncEnabled,
            localHasCredentials: NavidromeAPI.shared.hasCredentials
        ), let credentials = NavidromeAPI.shared.exportCredentialsForSync() else { return }
        _ = sendEnvelope(.init(kind: .credentials, sender: localPeerInfo(), command: nil, credentials: credentials, targetDeviceID: nil))
    }

    private func requestCredentialsFromPeers(targetDeviceID: String? = nil) {
        guard credentialSyncEnabled, !NavidromeAPI.shared.hasCredentials else { return }
        _ = sendEnvelope(.init(kind: .syncRequest, sender: localPeerInfo(), command: nil, credentials: nil, targetDeviceID: targetDeviceID))
    }

    private func requestCredentialsIfNeeded(from sender: SyncPeerInfo) {
        guard CredentialSyncBootstrapPolicy.shouldRequestCredentialsFromHello(
            localCredentialSyncEnabled: credentialSyncEnabled,
            localHasCredentials: NavidromeAPI.shared.hasCredentials,
            senderCredentialSyncEnabled: sender.credentialSyncEnabled,
            senderHasCredentials: sender.hasCredentials
        ) else { return }
        requestCredentialsFromPeers(targetDeviceID: sender.id)
    }

    private func handlePeerUnavailable(deviceID: String) {
        clearAllPendingCommands(for: deviceID)
        peerInfos.removeValue(forKey: deviceID)

        if selectedPlaybackTargetID == deviceID {
            selectedPlaybackTargetID = localDeviceID
        }

        connectedDeviceNames = Array(Set(peerInfos.values.map(\.name))).sorted()
        pauseSharedPlaybackForDisconnectedOutput(deviceID)
    }

    private func pauseSharedPlaybackForDisconnectedOutput(_ deviceID: String) {
        guard let pausedSession = ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: deviceID,
            currentSession: sharedSession,
            localDeviceID: localDeviceID
        ) else { return }

        publishSharedSession(pausedSession, applyLocally: true)
    }

    private var selectedRemotePlaybackTargetID: String? {
        validateSelectedPlaybackTarget()
        let availableTargetIDs = Set(availablePlaybackTargets.map(\.id))
        return PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: selectedPlaybackTargetID,
            localDeviceID: localDeviceID,
            availableTargetIDs: availableTargetIDs
        )
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

        let sent = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), command: command, credentials: nil, targetDeviceID: targetDeviceID))

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
        let receivedTransport: SyncTransportKind = peerDisplayName == nil ? .watchConnectivity : .multipeer

        peerInfos[envelope.sender.id] = envelope.sender
#if os(iOS) || os(macOS)
        if let peerDisplayName {
            multipeerDeviceIDs.insert(envelope.sender.id)
            deviceIDsByPeerDisplayName[peerDisplayName] = envelope.sender.id
        }
#endif
        connectedDeviceNames = Array(Set(peerInfos.values.map(\.name))).sorted()
        relayEnvelopeIfNeeded(envelope, receivedVia: receivedTransport)

        switch envelope.kind {
        case .hello:
            flushPendingCommands(for: envelope.sender.id)
            if credentialSyncEnabled,
               envelope.sender.credentialSyncEnabled,
               !envelope.sender.hasCredentials,
               let credentials = NavidromeAPI.shared.exportCredentialsForSync() {
                _ = sendEnvelope(.init(kind: .credentials, sender: localPeerInfo(), command: nil, credentials: credentials, targetDeviceID: nil))
            }
            requestCredentialsIfNeeded(from: envelope.sender)
            sendCurrentSyncState()

        case .syncRequest:
            guard SyncRequestTargetPolicy.shouldHandle(targetDeviceID: envelope.targetDeviceID, localDeviceID: localDeviceID) else { return }
            flushPendingCommands(for: envelope.sender.id)
            sendCurrentSyncState(includeHello: true)
            if CredentialSyncBootstrapPolicy.shouldOfferCredentialsToRequester(
                localCredentialSyncEnabled: credentialSyncEnabled,
                localHasCredentials: NavidromeAPI.shared.hasCredentials,
                requesterCredentialSyncEnabled: envelope.sender.credentialSyncEnabled,
                requesterHasCredentials: envelope.sender.hasCredentials
            ) {
                maybeSendCredentialsToInterestedPeers()
            }

        case .playbackSession:
            guard syncModeEnabled,
                  envelope.sender.syncModeEnabled,
                  let session = envelope.playbackSession else { return }
            let acknowledgingPendingCommandKey = acknowledgingPendingCommandKey(for: session)
            let isAcknowledgingSession = acknowledgingPendingCommandKey != nil
            let hasPendingCommandForDevice = !pendingCommandKeys(for: session.outputDeviceID).isEmpty
            guard PendingPlaybackUpdatePolicy.shouldApplyUpdate(
                hasPendingCommandForDevice: hasPendingCommandForDevice,
                isAcknowledgingPendingCommand: isAcknowledgingSession
            ) else {
                flushPendingCommands(for: envelope.sender.id)
                return
            }
            if let acknowledgingPendingCommandKey {
                clearPendingCommand(forKey: acknowledgingPendingCommandKey)
            }
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

    private func relayEnvelopeIfNeeded(_ envelope: SyncEnvelope, receivedVia receivedTransport: SyncTransportKind) {
#if os(iOS)
        let hasDestinationTransport: Bool
        switch receivedTransport {
        case .watchConnectivity:
            hasDestinationTransport = session?.connectedPeers.isEmpty == false
        case .multipeer:
            hasDestinationTransport = watchSession.map { $0.isReachable || canQueueWatchConnectivityPayload($0) } ?? false
        }

        guard SyncBridgeRelayPolicy.shouldRelay(
            kind: envelope.watchConnectivityPayloadKind,
            receivedVia: receivedTransport,
            localPlatform: SyncPlatformKind(platformName: platformName),
            hasDestinationTransport: hasDestinationTransport
        ) else { return }
        guard let data = try? encoder.encode(envelope) else { return }

        switch receivedTransport {
        case .watchConnectivity:
            guard let session, !session.connectedPeers.isEmpty else { return }
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                handleEnvelopeSendFailure(
                    kind: envelope.watchConnectivityPayloadKind,
                    transport: .multipeer,
                    errorDescription: String(describing: error)
                )
            }

        case .multipeer:
            guard let watchSession else { return }
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
            } else if shouldQueueWatchConnectivityEnvelope(envelope, for: watchSession) {
                watchSession.transferUserInfo(["payload": data])
            }
        }
#endif
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
        let intendedIsPlaying = RemoteCommandLocalPublicationPolicy.intendedIsPlaying(after: command.action)
        withRemoteCommandApplication {
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
            broadcastLocalQueueAsShared(
                isExplicitLocalPlaybackIntent: true,
                intendedIsPlaying: intendedIsPlaying
            )
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
        _ = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), command: command, credentials: nil, targetDeviceID: ownerDeviceID))
    }

    private func mirrorSharedQueue(songs: [Song], currentIndex: Int, currentTime: TimeInterval) {
        guard !songs.isEmpty else { return }
        withRemoteCommandApplication {
            AudioPlayer.shared.mirrorQueueWithoutPlayback(songs, currentIndex: currentIndex, currentTime: currentTime)
        }
    }

    private func commandNeedsPlaybackAcknowledgment(_ command: PlaybackCommand) -> Bool {
        PlaybackCommandSyncPolicy.needsPlaybackAcknowledgment(command.action)
    }

    private func acknowledgingPendingCommandKey(for session: PlaybackSession) -> String? {
        for key in pendingCommandKeys(for: session.outputDeviceID) {
            guard let command = pendingTargetedCommands[key],
                  commandNeedsPlaybackAcknowledgment(command),
                  PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
                    session,
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

    private func clearAllPendingCommands(for deviceID: String) {
        for key in pendingCommandKeys(for: deviceID) {
            clearPendingCommand(forKey: key)
        }
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

        _ = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), command: command, credentials: nil, targetDeviceID: deviceID))
        schedulePendingCommandRetry(for: deviceID, action: command.action)
    }

    private func handleExpiredPendingCommand(_ command: PlaybackCommand, deviceID: String, key: String) {
        print("⚠️ Dropping unacknowledged sync command \(command.action.rawValue) for \(deviceID)")
        clearPendingCommand(forKey: key)
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
        case .playbackSession, .playbackCommand:
            return WatchConnectivitySyncPolicy.shouldQueue(envelope.watchConnectivityPayloadKind)
        }
    }

    private func canQueueWatchConnectivityPayload(_ session: WCSession) -> Bool {
        WatchConnectivityPayloadQueuePolicy.canQueueDurablePayload(activationSucceeded: session.activationState == .activated)
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
            if WatchConnectivityActivationPolicy.shouldStartActivation(
                isSupported: true,
                isNotActivated: session.activationState == .notActivated,
                activationInProgress: self.isWatchConnectivityActivationInProgress
            ) {
                self.isWatchConnectivityActivationInProgress = true
                self.hasBootstrappedWatchConnectivitySession = false
                session.activate()
            }
        }
    }

    private func handleWatchConnectivityReachabilityChanged(isReachable: Bool) {
        if isReachable {
            sendCurrentSyncState(includeHello: true)
            maybeSendCredentialsToInterestedPeers()
            return
        }

        guard let peer = watchConnectivityPeerInfo() else { return }
        handlePeerUnavailable(deviceID: peer.id)
    }

    private func watchConnectivityPeerInfo() -> SyncPeerInfo? {
        let localPlatform = SyncPlatformKind(platformName: platformName)
        let remotePlatform: SyncPlatformKind

        switch localPlatform {
        case .iPhone:
            remotePlatform = .appleWatch
        case .appleWatch:
            remotePlatform = .iPhone
        case .mac, .other:
            return nil
        }

        return peerInfos.values.first {
            SyncPlatformKind(platformName: $0.platform) == remotePlatform
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

    private func restartMultipeerDiscoveryForManualSearch() {
        guard syncModeEnabled || credentialSyncEnabled else { return }

        multipeerRestartTask?.cancel()
        multipeerRestartTask = nil
        multipeerRestartAttempt = 0
        inviteRetryTasksByPeerDisplayName.values.forEach { $0.cancel() }
        inviteRetryTasksByPeerDisplayName.removeAll()
        inviteAttemptsByPeerDisplayName.removeAll()
        discoveredMultipeerPeers.removeAll()

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil

        startMultipeerDiscovery()
        print("🔎 Manual nearby device search started")
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
            handlePeerUnavailable(deviceID: deviceID)
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
            DeviceSyncManager.shared.isWatchConnectivityActivationInProgress = false
            if shouldBootstrap {
                DeviceSyncManager.shared.bootstrapWatchConnectivitySync()
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

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Self.enqueueDelegateEvent {
            DeviceSyncManager.shared.handleWatchConnectivityReachabilityChanged(isReachable: isReachable)
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Self.enqueueDelegateEvent {
            DeviceSyncManager.shared.isWatchConnectivityActivationInProgress = true
            DeviceSyncManager.shared.hasBootstrappedWatchConnectivitySession = false
        }
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
