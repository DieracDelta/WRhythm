//
//  PlaybackSyncPolicyTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing
@testable import WRhythm_Watch_App

struct PlaybackSyncPolicyTests {
    @Test func newerSessionRevisionWinsOverCurrentSession() {
        let now = Date()
        let current = makeSession(revision: 4, updatedAt: now, updatedByDeviceID: "iphone")
        let older = makeSession(revision: 3, updatedAt: now.addingTimeInterval(10), updatedByDeviceID: "mac")
        let newer = makeSession(revision: 5, updatedAt: now.addingTimeInterval(-10), updatedByDeviceID: "mac")

        #expect(PlaybackSessionSyncPolicy.shouldApply(older, over: current) == false)
        #expect(PlaybackSessionSyncPolicy.shouldApply(newer, over: current) == true)
    }

    @Test func localOwnerPausePublishesNewerAuthoritativeSession() {
        let now = Date()
        let current = makeSession(
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 120,
            revision: 4,
            updatedAt: now.addingTimeInterval(-1),
            updatedByDeviceID: "iphone"
        )
        let paused = makeSession(
            outputDeviceID: "iphone",
            isPlaying: false,
            position: 123,
            revision: 5,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(paused, over: current, now: now) == true)
    }

    @Test func remoteDisplayUsesPausedSessionOverLaterPlayingTelemetry() throws {
        let now = Date()
        let pausedSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: false,
            position: 123,
            revision: 5,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: pausedSession,
            deviceName: "iPhone",
            platform: "iPhone",
            now: now.addingTimeInterval(0.5)
        ))

        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 123)
    }

    @Test func newerDifferentSessionWinsEvenWhenRevisionIsLower() {
        let now = Date()
        let staleMacSession = makeSession(id: "mac-session", revision: 20, updatedAt: now.addingTimeInterval(-5), updatedByDeviceID: "mac")
        let freshIPhoneSession = makeSession(
            id: "iphone-session",
            outputDeviceID: "iphone",
            revision: 1,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(freshIPhoneSession, over: staleMacSession) == true)
    }

    @Test func olderDifferentSessionDoesNotReplaceNewerSession() {
        let now = Date()
        let currentMacSession = makeSession(id: "mac-session", revision: 2, updatedAt: now, updatedByDeviceID: "mac")
        let delayedIPhoneSession = makeSession(
            id: "iphone-session",
            outputDeviceID: "iphone",
            revision: 99,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "iphone"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(delayedIPhoneSession, over: currentMacSession) == false)
    }

    @Test func reconnectBootstrapKeepsNewestDifferentSession() {
        let now = Date()
        let staleSession = makeSession(
            id: "iphone-session",
            outputDeviceID: "iphone",
            revision: 42,
            updatedAt: now.addingTimeInterval(-10),
            updatedByDeviceID: "iphone"
        )
        let freshSession = makeSession(
            id: "mac-session",
            outputDeviceID: "mac",
            revision: 1,
            updatedAt: now,
            updatedByDeviceID: "mac"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(freshSession, over: staleSession) == true)
        #expect(PlaybackSessionSyncPolicy.shouldApply(staleSession, over: freshSession) == false)
    }

    @Test func sameRevisionSessionUsesTimestampThenDeviceIDTieBreaker() {
        let now = Date()
        let current = makeSession(revision: 4, updatedAt: now, updatedByDeviceID: "iphone")
        let olderTimestamp = makeSession(revision: 4, updatedAt: now.addingTimeInterval(-1), updatedByDeviceID: "zzzz")
        let newerTimestamp = makeSession(revision: 4, updatedAt: now.addingTimeInterval(1), updatedByDeviceID: "aaaa")
        let lowerDeviceTie = makeSession(revision: 4, updatedAt: now, updatedByDeviceID: "aaaa")
        let higherDeviceTie = makeSession(revision: 4, updatedAt: now, updatedByDeviceID: "mac")

        #expect(PlaybackSessionSyncPolicy.shouldApply(olderTimestamp, over: current) == false)
        #expect(PlaybackSessionSyncPolicy.shouldApply(newerTimestamp, over: current) == true)
        #expect(PlaybackSessionSyncPolicy.shouldApply(lowerDeviceTie, over: current) == false)
        #expect(PlaybackSessionSyncPolicy.shouldApply(higherDeviceTie, over: current) == true)
    }

    @Test func remoteOutputSessionPausesLocalPlaybackWithoutReplacingQueue() {
        let now = Date()
        let localState = makeLocalState(currentTime: 10, isPlaying: true)
        let session = makeSession(outputDeviceID: "iphone", isPlaying: true, position: 20, updatedAt: now)

        let plan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: "mac",
            localState: localState,
            now: now
        )

        #expect(plan.shouldPause == true)
        #expect(plan.shouldReplaceQueue == false)
        #expect(plan.shouldSeek == false)
    }

    @Test func localOutputPauseSessionSeeksAndPausesWhenPositionChanged() {
        let now = Date()
        let localState = makeLocalState(currentTime: 2, isPlaying: true)
        let session = makeSession(outputDeviceID: "mac", isPlaying: false, position: 30, updatedAt: now)

        let plan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: "mac",
            localState: localState,
            now: now
        )

        #expect(plan.shouldReplaceQueue == false)
        #expect(plan.shouldSeek == true)
        #expect(plan.shouldPause == true)
        #expect(plan.shouldPlay == false)
    }

    @Test func pausedDifferentTrackSessionStillPausesAfterQueueReplacement() {
        let now = Date()
        let localState = makeLocalState(
            queueIDs: ["song-1"],
            currentSongID: "song-1",
            currentIndex: 0,
            currentTime: 2,
            isPlaying: false
        )
        let session = makeSession(
            songs: [makeSong(id: "song-2")],
            outputDeviceID: "mac",
            isPlaying: false,
            position: 30,
            updatedAt: now
        )

        let plan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: "mac",
            localState: localState,
            now: now
        )

        #expect(plan.shouldReplaceQueue == true)
        #expect(plan.shouldSeek == true)
        #expect(plan.shouldPause == true)
    }

    @Test func localOutputSessionIgnoresSmallDriftButSeeksLargeDrift() {
        let now = Date()
        let nearbyState = makeLocalState(currentTime: 11.5)
        let farState = makeLocalState(currentTime: 20)
        let session = makeSession(outputDeviceID: "mac", isPlaying: true, position: 10, updatedAt: now)

        let nearbyPlan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: "mac",
            localState: nearbyState,
            now: now
        )
        let farPlan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: "mac",
            localState: farState,
            now: now
        )

        #expect(nearbyPlan.shouldSeek == false)
        #expect(farPlan.shouldSeek == true)
    }

    @Test func localOutputSessionPlansVolumeUpdateOnlyOutsideTolerance() {
        let now = Date()
        let withinTolerance = makeLocalState(volume: 0.505)
        let outsideTolerance = makeLocalState(volume: 0.55)
        let session = makeSession(outputDeviceID: "mac", volume: 0.5, updatedAt: now)

        let withinPlan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: "mac",
            localState: withinTolerance,
            now: now
        )
        let outsidePlan = PlaybackSessionSyncPolicy.reconciliationPlan(
            for: session,
            localDeviceID: "mac",
            localState: outsideTolerance,
            now: now
        )

        #expect(withinPlan.shouldSetVolume == false)
        #expect(outsidePlan.shouldSetVolume == true)
    }

    @Test func localPlaybackOwnershipAllowsPlayingDeviceToPublishOverRemoteOwner() {
        #expect(LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "mac",
            localDeviceID: "iphone",
            selectedPlaybackTargetID: "iphone",
            hasLocalPlayback: true,
            isLocalPlaying: true
        ) == true)
    }

    @Test func localPlaybackStartupPublishesIntendedPlayingStateBeforePlayerIsReady() {
        #expect(LocalPlaybackPublicationPolicy.publishedIsPlaying(
            playerIsPlaying: false,
            intendedIsPlaying: true
        ) == true)
    }

    @Test func localPlaybackTelemetryPublishesActualStateWithoutIntentOverride() {
        #expect(LocalPlaybackPublicationPolicy.publishedIsPlaying(
            playerIsPlaying: false,
            intendedIsPlaying: nil
        ) == false)
        #expect(LocalPlaybackPublicationPolicy.publishedIsPlaying(
            playerIsPlaying: true,
            intendedIsPlaying: nil
        ) == true)
    }

    @Test func localPlaybackOwnershipKeepsPausedMirrorFromPublishingOverRemoteOwner() {
        #expect(LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "mac",
            localDeviceID: "iphone",
            selectedPlaybackTargetID: "mac",
            hasLocalPlayback: true,
            isLocalPlaying: false
        ) == false)
    }

    @Test func pausedLocalSelectedTargetCanPublishOverStaleRemoteOwner() {
        #expect(LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "iphone",
            localDeviceID: "mac",
            selectedPlaybackTargetID: "mac",
            hasLocalPlayback: true,
            isLocalPlaying: false
        ) == true)
    }

    @Test func pausedLocalSelectedTargetWithoutPlaybackDoesNotPublishOverRemoteOwner() {
        #expect(LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "iphone",
            localDeviceID: "mac",
            selectedPlaybackTargetID: "mac",
            hasLocalPlayback: false,
            isLocalPlaying: false
        ) == false)
    }

    @Test func explicitLocalPauseIntentCanClaimOwnershipFromStaleRemoteOwner() {
        #expect(LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "mac",
            localDeviceID: "iphone",
            selectedPlaybackTargetID: "iphone",
            hasLocalPlayback: true,
            isLocalPlaying: false,
            isExplicitLocalPlaybackIntent: true
        ) == true)
    }

    @Test(arguments: [
        (WatchConnectivitySyncPayloadKind.hello, true),
        (.syncRequest, true),
        (.credentials(hasPayload: true), true),
        (.credentials(hasPayload: false), false),
        (.playbackSession, false),
        (.playbackCommand, false)
    ])
    func watchConnectivityQueuesOnlyDurablePayloads(kind: WatchConnectivitySyncPayloadKind, expected: Bool) {
        #expect(WatchConnectivitySyncPolicy.shouldQueue(kind) == expected)
    }

    @Test(arguments: [
        (PlaybackSyncCommandAction.play, true),
        (.pause, true),
        (.seek, true),
        (.setVolume, true),
        (.toggle, false),
        (.next, true),
        (.previous, true),
        (.playQueue, true),
        (.enqueue, true),
        (.syncQueue, true),
        (.stop, true)
    ])
    func playbackCommandsThatNeedAcknowledgmentAreRetried(action: PlaybackSyncCommandAction, expected: Bool) {
        #expect(PlaybackCommandSyncPolicy.needsPlaybackAcknowledgment(action) == expected)
    }

    @Test func pauseCommandIsAcknowledgedByPausedSession() {
        let session = makeSession(isPlaying: false, updatedAt: Date())

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(session, action: .pause) == true)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(session, action: .play) == false)
    }

    @Test func seekCommandIsAcknowledgedOnlyNearRequestedPosition() {
        let now = Date()
        let nearSeekTarget = makeSession(position: 30.5, updatedAt: now)
        let stalePosition = makeSession(position: 2, updatedAt: now)

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(nearSeekTarget, action: .seek, expectedTime: 30) == true)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(stalePosition, action: .seek, expectedTime: 30) == false)
    }

    @Test func seekCommandAcknowledgmentUsesEstimatedPlayingProgress() {
        let now = Date()
        let progressedSession = makeSession(
            isPlaying: true,
            position: 25,
            updatedAt: now.addingTimeInterval(-5)
        )

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            progressedSession,
            action: .seek,
            expectedTime: 30,
            now: now
        ) == true)
    }

    @Test func toggledPlaybackResolvesToExplicitCommandActions() {
        #expect(PlaybackCommandSyncPolicy.explicitActionForToggledPlayback(isPlaying: true) == .pause)
        #expect(PlaybackCommandSyncPolicy.explicitActionForToggledPlayback(isPlaying: false) == .play)
    }

    @Test func incomingToggleCommandsAreRejectedAsAmbiguous() {
        #expect(PlaybackCommandSyncPolicy.shouldApplyIncomingCommand(.toggle) == false)
        #expect(PlaybackCommandSyncPolicy.shouldApplyIncomingCommand(.play) == true)
        #expect(PlaybackCommandSyncPolicy.shouldApplyIncomingCommand(.pause) == true)
    }

    @Test func volumeCommandUsesToleranceForAcknowledgment() {
        let now = Date()
        let matchingVolume = makeSession(volume: 0.51, updatedAt: now)
        let differentVolume = makeSession(volume: 0.62, updatedAt: now)

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(matchingVolume, action: .setVolume, expectedVolume: 0.5) == true)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(differentVolume, action: .setVolume, expectedVolume: 0.5) == false)
    }

    @Test func navigationCommandsRequireExpectedQueuePosition() {
        let now = Date()
        let first = makeSong(id: "song-1")
        let second = makeSong(id: "song-2")
        let session = makeSession(songs: [first, second], currentIndex: 1, updatedAt: now)

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(session, action: .next, expectedIndex: 1) == true)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(session, action: .next, expectedIndex: 0) == false)
    }

    @Test func previousCommandCanAcknowledgeRestartingCurrentTrack() {
        let now = Date()
        let first = makeSong(id: "song-1")
        let second = makeSong(id: "song-2")
        let session = makeSession(songs: [first, second], currentIndex: 1, position: 0.5, updatedAt: now)

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            session,
            action: .previous,
            expectedIndex: 1,
            expectedTime: 0
        ) == true)
    }

    @Test func playQueueCommandAcknowledgesExpectedQueueAndIndex() {
        let now = Date()
        let songs = [makeSong(id: "song-1"), makeSong(id: "song-2")]
        let session = makeSession(songs: songs, currentIndex: 1, updatedAt: now)

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            session,
            action: .playQueue,
            expectedSongs: songs,
            expectedIndex: 1
        ) == true)
    }

    @Test func enqueueCommandAcknowledgesInsertedContiguousSongs() {
        let now = Date()
        let songs = [makeSong(id: "song-1"), makeSong(id: "song-2"), makeSong(id: "song-3")]
        let session = makeSession(songs: songs, currentIndex: 0, updatedAt: now)

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            session,
            action: .enqueue,
            expectedSongs: Array(songs[1...2])
        ) == true)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            session,
            action: .enqueue,
            expectedSongs: [songs[2], songs[1]]
        ) == false)
    }

    @Test func syncQueueCommandAcknowledgesExactQueueAndIndex() {
        let now = Date()
        let songs = [makeSong(id: "song-1"), makeSong(id: "song-2")]
        let session = makeSession(songs: songs, currentIndex: 0, updatedAt: now)

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            session,
            action: .syncQueue,
            expectedSongs: songs,
            expectedIndex: 0
        ) == true)
    }

    @Test func stopCommandAcknowledgesStoppedEmptySession() {
        let session = makeSession(songs: [], isPlaying: false, updatedAt: Date())

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(session, action: .stop) == true)
    }

    @Test func queueCommandsInvalidateStalePendingCommandFamilies() {
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .playQueue) == [.transport, .navigation, .seek, .queue, .stop])
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .stop) == [.transport, .navigation, .seek, .queue, .stop])
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .next) == [.navigation, .seek])
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .seek).isEmpty)
    }

    @Test func transportFailuresInvalidatePlaybackButNotDurablePayloads() {
        #expect(SyncTransportFailurePolicy.shouldInvalidatePlaybackBroadcastAttempt(kind: .playbackCommand) == true)
        #expect(SyncTransportFailurePolicy.shouldInvalidatePlaybackBroadcastAttempt(kind: .hello) == false)
        #expect(SyncTransportFailurePolicy.shouldInvalidatePlaybackBroadcastAttempt(kind: .credentials(hasPayload: true)) == false)
        #expect(SyncTransportFailurePolicy.shouldRequestPlaybackRefresh(kind: .playbackSession) == true)
        #expect(SyncTransportFailurePolicy.shouldRequestPlaybackRefresh(kind: .syncRequest) == false)
    }

    @Test func watchConnectivitySendFailuresFallbackOnlyForDurablePayloads() {
        #expect(WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(kind: .credentials(hasPayload: true), canQueuePayload: true) == true)
        #expect(WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(kind: .hello, canQueuePayload: true) == true)
        #expect(WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(kind: .syncRequest, canQueuePayload: true) == true)
        #expect(WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(kind: .playbackSession, canQueuePayload: true) == false)
        #expect(WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(kind: .credentials(hasPayload: true), canQueuePayload: false) == false)
        #expect(WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(kind: .credentials(hasPayload: false), canQueuePayload: true) == false)
    }

    @Test func multipeerSendFailuresRestartOnlyWhenSessionHadPeers() {
        #expect(SyncTransportFailurePolicy.shouldRestartMultipeerDiscoveryAfterSendFailure(hasConnectedPeers: true) == true)
        #expect(SyncTransportFailurePolicy.shouldRestartMultipeerDiscoveryAfterSendFailure(hasConnectedPeers: false) == false)
    }

    @Test func watchConnectivityBootstrapsOnlyAfterCleanActivation() {
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapSync(activationSucceeded: true, hasError: false) == true)
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapSync(activationSucceeded: false, hasError: false) == false)
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapSync(activationSucceeded: true, hasError: true) == false)
    }

    @Test func watchConnectivityActivationRetryUsesBackoffOnlyForRetryableFailures() {
        #expect(WatchConnectivityActivationRetryPolicy.shouldRetry(activationSucceeded: false, hasError: true, canActivate: true) == true)
        #expect(WatchConnectivityActivationRetryPolicy.shouldRetry(activationSucceeded: true, hasError: false, canActivate: true) == false)
        #expect(WatchConnectivityActivationRetryPolicy.shouldRetry(activationSucceeded: false, hasError: true, canActivate: false) == false)
        #expect(WatchConnectivityActivationRetryPolicy.retryDelay(forAttempt: 0) == 1)
        #expect(WatchConnectivityActivationRetryPolicy.retryDelay(forAttempt: 1) == 2)
        #expect(WatchConnectivityActivationRetryPolicy.retryDelay(forAttempt: 20) == 120)
    }

    @Test func multipeerInviteRetriesUseCurrentDiscoveredPeer() {
        #expect(MultipeerInviteRetryPolicy.shouldInvite(
            scheduledPeerDisplayName: "mac-1234",
            discoveredPeerDisplayName: "mac-1234",
            isAlreadyConnected: false
        ) == true)
        #expect(MultipeerInviteRetryPolicy.shouldInvite(
            scheduledPeerDisplayName: "mac-1234",
            discoveredPeerDisplayName: nil,
            isAlreadyConnected: false
        ) == false)
        #expect(MultipeerInviteRetryPolicy.shouldInvite(
            scheduledPeerDisplayName: "mac-1234",
            discoveredPeerDisplayName: "iphone-1234",
            isAlreadyConnected: false
        ) == false)
        #expect(MultipeerInviteRetryPolicy.shouldInvite(
            scheduledPeerDisplayName: "mac-1234",
            discoveredPeerDisplayName: "mac-1234",
            isAlreadyConnected: true
        ) == false)
    }

    @Test func pendingCommandRetriesArePinnedToCommandID() {
        #expect(PendingPlaybackCommandRetryPolicy.shouldRunRetry(pendingCommandID: "command-1", scheduledCommandID: "command-1") == true)
        #expect(PendingPlaybackCommandRetryPolicy.shouldRunRetry(pendingCommandID: "command-2", scheduledCommandID: "command-1") == false)
        #expect(PendingPlaybackCommandRetryPolicy.shouldRunRetry(pendingCommandID: nil, scheduledCommandID: "command-1") == false)
    }

    @Test func pendingPlaybackCommandDefersConflictingNonAcknowledgingUpdates() {
        #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: false
        ) == false)
        #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: true
        ) == true)
        #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
            hasPendingCommandForDevice: false,
            isAcknowledgingPendingCommand: false
        ) == true)
    }

    @Test func pendingPauseRejectsDelayedPlayingSessionUntilPausedSessionAcknowledges() {
        let now = Date()
        let delayedPlayingSession = makeSession(outputDeviceID: "mac", isPlaying: true, position: 122, updatedAt: now)
        let pausedSession = makeSession(outputDeviceID: "mac", isPlaying: false, position: 120.3, updatedAt: now.addingTimeInterval(0.2))

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            delayedPlayingSession,
            action: .pause
        ) == false)
        #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: false
        ) == false)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            pausedSession,
            action: .pause
        ) == true)
        #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: true
        ) == true)
    }

    @Test func stalePrebufferCompletionsDoNotPublish() {
        #expect(PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
            key: "song-1|flac",
            desiredKeys: ["song-1|flac"],
            activeTaskKeys: ["song-1|flac"],
            capturedToken: "token-1",
            activeToken: "token-1"
        ) == true)
        #expect(PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
            key: "song-1|flac",
            desiredKeys: ["song-2|flac"],
            activeTaskKeys: ["song-1|flac"],
            capturedToken: "token-1",
            activeToken: "token-1"
        ) == false)
        #expect(PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
            key: "song-1|flac",
            desiredKeys: ["song-1|flac"],
            activeTaskKeys: [],
            capturedToken: "token-1",
            activeToken: "token-1"
        ) == false)
        #expect(PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
            key: "song-1|flac",
            desiredKeys: ["song-1|flac"],
            activeTaskKeys: ["song-1|flac"],
            capturedToken: "token-1",
            activeToken: "token-2"
        ) == false)
    }

    @Test func asyncTaskOwnershipRequiresMatchingToken() {
        #expect(AsyncTaskOwnershipPolicy.isCurrent(capturedToken: "token-1", activeToken: "token-1") == true)
        #expect(AsyncTaskOwnershipPolicy.isCurrent(capturedToken: "token-1", activeToken: "token-2") == false)
        #expect(AsyncTaskOwnershipPolicy.isCurrent(capturedToken: "token-1", activeToken: nil) == false)
    }

    @Test func playerItemEventsOnlyHandleCurrentItem() {
        #expect(PlayerItemEventPolicy.shouldHandle(currentItemMatches: true) == true)
        #expect(PlayerItemEventPolicy.shouldHandle(currentItemMatches: false) == false)
    }

    @Test func asyncResultOwnershipRequiresCurrentGenerationAndActiveTask() {
        #expect(AsyncResultOwnershipPolicy.shouldApply(capturedGeneration: 2, currentGeneration: 2, isCancelled: false) == true)
        #expect(AsyncResultOwnershipPolicy.shouldApply(capturedGeneration: 2, currentGeneration: 3, isCancelled: false) == false)
        #expect(AsyncResultOwnershipPolicy.shouldApply(capturedGeneration: 2, currentGeneration: 2, isCancelled: true) == false)
    }

    @Test func searchResultOwnershipRequiresCurrentQueryAndActiveTask() {
        #expect(SearchResultOwnershipPolicy.shouldApply(query: "queen", currentQuery: "queen", isCancelled: false) == true)
        #expect(SearchResultOwnershipPolicy.shouldApply(query: "queen", currentQuery: "queen ", isCancelled: false) == false)
        #expect(SearchResultOwnershipPolicy.shouldApply(query: "queen", currentQuery: "queen", isCancelled: true) == false)
    }

    @Test func remotePauseRoundTripCanApplyAndAcknowledgeAcrossDevices() {
        let now = Date()
        let macPausedSession = makeSession(outputDeviceID: "mac", isPlaying: false, position: 120.2, updatedAt: now)

        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .pause,
            targetDeviceID: "mac",
            localDeviceID: "mac"
        ) == true)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            macPausedSession,
            action: .pause
        ) == true)
    }

    @Test func remoteSeekRoundTripCanApplyAndAcknowledgeAcrossDevices() {
        let now = Date()
        let macSeekSession = makeSession(outputDeviceID: "mac", position: 30.5, updatedAt: now)

        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .seek,
            targetDeviceID: "mac",
            localDeviceID: "mac"
        ) == true)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            macSeekSession,
            action: .seek,
            expectedTime: 30
        ) == true)
    }

    @Test(arguments: [
        (0, 1.0),
        (1, 2.0),
        (2, 4.0),
        (3, 8.0),
        (4, 8.0),
        (20, 8.0)
    ])
    func commandRetryBackoffCapsAtEightSeconds(attempt: Int, expectedDelay: TimeInterval) {
        #expect(PlaybackCommandSyncPolicy.retryDelay(forAttempt: attempt) == expectedDelay)
    }

    @Test func newerTargetedCommandReplacesExistingPendingCommand() {
        #expect(PendingPlaybackCommandPolicy.shouldReplacePendingCommand(
            existingAction: .pause,
            incomingAction: .play
        ) == true)
        #expect(PendingPlaybackCommandPolicy.shouldReplacePendingCommand(
            existingAction: .seek,
            incomingAction: .seek
        ) == true)
        #expect(PendingPlaybackCommandPolicy.shouldReplacePendingCommand(
            existingAction: .pause,
            incomingAction: .setVolume
        ) == false)
    }

    @Test func incomingOppositePlaybackCommandSupersedesPendingCommand() {
        #expect(PendingPlaybackCommandPolicy.shouldIncomingCommandSupersedePendingCommand(
            pendingAction: .pause,
            incomingAction: .play
        ) == true)
        #expect(PendingPlaybackCommandPolicy.shouldIncomingCommandSupersedePendingCommand(
            pendingAction: .seek,
            incomingAction: .seek
        ) == true)
        #expect(PendingPlaybackCommandPolicy.shouldIncomingCommandSupersedePendingCommand(
            pendingAction: .enqueue,
            incomingAction: .play
        ) == false)
        #expect(PendingPlaybackCommandPolicy.shouldIncomingCommandSupersedePendingCommand(
            pendingAction: .pause,
            incomingAction: .setVolume
        ) == false)
    }

    @Test func pendingCommandDeadlineDependsOnAcknowledgmentNeed() {
        #expect(PendingPlaybackCommandPolicy.deadlineInterval(needsAcknowledgment: true) == 20)
        #expect(PendingPlaybackCommandPolicy.deadlineInterval(needsAcknowledgment: false) == 6)
    }

    @Test func commandReceivePolicyRejectsCommandsBeforeDedupeWhenTargetedElsewhere() {
        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .pause,
            targetDeviceID: "iphone",
            localDeviceID: "mac"
        ) == false)
        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .pause,
            targetDeviceID: "mac",
            localDeviceID: "mac"
        ) == true)
        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .pause,
            targetDeviceID: nil,
            localDeviceID: "mac"
        ) == true)
        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .toggle,
            targetDeviceID: "mac",
            localDeviceID: "mac"
        ) == false)
    }

    @Test func syncQueueCommandsApplyOnlyToMirroringNonOwnersWithSongs() {
        #expect(PlaybackCommandReceivePolicy.shouldApplySyncQueue(
            targetDeviceID: "mac",
            localDeviceID: "iphone",
            hasSongs: true
        ) == true)
        #expect(PlaybackCommandReceivePolicy.shouldApplySyncQueue(
            targetDeviceID: "iphone",
            localDeviceID: "iphone",
            hasSongs: true
        ) == false)
        #expect(PlaybackCommandReceivePolicy.shouldApplySyncQueue(
            targetDeviceID: "mac",
            localDeviceID: "iphone",
            hasSongs: false
        ) == false)
    }

    @Test func defaultControlTargetIgnoresLegacyRemotePlaybackState() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone", "mac"]
        ) == "iphone")
    }

    @Test func defaultControlTargetKeepsSelectedSharedOutputWhenItIsStillActive() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone", "mac"]
        ) == "iphone")
    }

    @Test func defaultControlTargetDoesNotYieldToUnavailableRemotePlayback() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone"]
        ) == "iphone")
    }

    @Test func defaultControlTargetKeepsSelectedIndependentRemoteTarget() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "watch",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["watch", "mac"]
        ) == "watch")
    }

    @Test func defaultControlTargetReturnsNilForLocalOrInvalidSelection() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone-local",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone-local", "mac"]
        ) == nil)
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "missing",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone-local", "mac"]
        ) == nil)
    }

    @Test func duplicatePolicySkipsAlreadyProcessedEnvelopeID() {
        #expect(SyncDuplicatePolicy.shouldProcess(envelopeID: nil, processedEnvelopeIDs: ["seen"]) == true)
        #expect(SyncDuplicatePolicy.shouldProcess(envelopeID: "fresh", processedEnvelopeIDs: ["seen"]) == true)
        #expect(SyncDuplicatePolicy.shouldProcess(envelopeID: "seen", processedEnvelopeIDs: ["seen"]) == false)
    }

    @Test func duplicatePolicyKeepsOnlyRecentEnvelopeIDs() {
        let ids = (0..<505).map { "id-\($0)" }
        let trimmed = SyncDuplicatePolicy.trimmedEnvelopeIDOrder(ids)

        #expect(trimmed.count == SyncDuplicatePolicy.maxTrackedEnvelopeIDs)
        #expect(trimmed.first == "id-5")
        #expect(trimmed.last == "id-504")
    }

    @Test func playbackSessionRejectsStaleAndFarFutureUpdates() {
        let now = Date()
        let current = makeSession(updatedAt: now)
        let stale = makeSession(revision: 99, updatedAt: now.addingTimeInterval(-31), updatedByDeviceID: "iphone")
        let farFuture = makeSession(revision: 99, updatedAt: now.addingTimeInterval(11), updatedByDeviceID: "iphone")

        #expect(PlaybackSessionSyncPolicy.isStale(stale, current: current, now: now) == true)
        #expect(PlaybackSessionSyncPolicy.isStale(farFuture, current: current, now: now) == true)
        #expect(PlaybackSessionSyncPolicy.shouldApply(stale, over: current, now: now) == false)
        #expect(PlaybackSessionSyncPolicy.shouldApply(farFuture, over: current, now: now) == false)
    }

    @Test func playbackSessionSnapshotUsesEstimatedPositionForRemoteDisplay() throws {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: true,
            position: 10,
            updatedAt: now.addingTimeInterval(-5)
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: session,
            deviceName: "Mac",
            platform: "Mac",
            now: now
        ))

        #expect(snapshot.currentTime == 15)
        #expect(snapshot.updatedAt == now)
    }

    @Test func playbackSessionSnapshotUsesPausedSessionState() throws {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: false,
            position: 20,
            updatedAt: now
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: session,
            deviceName: "Mac",
            platform: "Mac",
            now: now
        ))

        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 20)
        #expect(snapshot.updatedAt == now)
    }

    @Test func remotePauseCommandFinalTruthComesFromOwnerSessionAcknowledgment() throws {
        let now = Date()
        let pausedSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: false,
            position: 120,
            revision: 7,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )

        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            pausedSession,
            action: .pause,
            now: now
        ) == true)

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: pausedSession,
            deviceName: "iPhone",
            platform: "iPhone",
            now: now
        ))

        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 120)
    }

    @Test func playbackSessionSnapshotIsBuiltOnlyFromSession() throws {
        let now = Date()
        let song = makeSong(id: "song-1")
        let session = makeSession(
            songs: [song],
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 30,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "iphone"
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: session,
            deviceName: "iPhone",
            platform: "iPhone",
            now: now
        ))

        #expect(snapshot.id == "iphone")
        #expect(snapshot.song?.id == "song-1")
        #expect(snapshot.queue.map(\.id) == ["song-1"])
        #expect(snapshot.isPlaying == true)
        #expect(snapshot.currentTime == 35)
    }

    @Test func playbackRetryPolicyRejectsRetryAfterUserIntentChanges() {
        #expect(PlaybackRetryPolicy.shouldRunRetry(
            capturedSongID: "song-1",
            currentSongID: "song-1",
            capturedIntentRevision: 2,
            currentIntentRevision: 3,
            capturedShouldAutoplay: true,
            isCurrentlyPlaying: false
        ) == false)
    }

    @Test func playbackRetryPolicyAllowsSameIntentRetryWhileStillPlaying() {
        #expect(PlaybackRetryPolicy.shouldRunRetry(
            capturedSongID: "song-1",
            currentSongID: "song-1",
            capturedIntentRevision: 2,
            currentIntentRevision: 2,
            capturedShouldAutoplay: true,
            isCurrentlyPlaying: true
        ) == true)
    }

    @Test func playbackRetryPolicyRejectsRetryAfterQueueOccurrenceChanges() {
        #expect(PlaybackRetryPolicy.shouldRunRetry(
            capturedSongID: "song-1",
            currentSongID: "song-1",
            capturedIntentRevision: 2,
            currentIntentRevision: 2,
            capturedShouldAutoplay: true,
            isCurrentlyPlaying: true,
            capturedQueueIDs: ["song-1", "song-1"],
            currentQueueIDs: ["song-1", "song-1"],
            capturedIndex: 0,
            currentIndex: 1
        ) == false)
        #expect(PlaybackRetryPolicy.shouldRunRetry(
            capturedSongID: "song-1",
            currentSongID: "song-1",
            capturedIntentRevision: 2,
            currentIntentRevision: 2,
            capturedShouldAutoplay: true,
            isCurrentlyPlaying: true,
            capturedQueueIDs: ["song-1", "song-2"],
            currentQueueIDs: ["song-2", "song-1"],
            capturedIndex: 0,
            currentIndex: 0
        ) == false)
    }

    @Test func prebufferRetryBackoffCapsAtThirtySeconds() {
        #expect(PrebufferRetryPolicy.retryDelay(forAttempt: 0) == 1)
        #expect(PrebufferRetryPolicy.retryDelay(forAttempt: 1) == 2)
        #expect(PrebufferRetryPolicy.retryDelay(forAttempt: 5) == 30)
        #expect(PrebufferRetryPolicy.retryDelay(forAttempt: 20) == 30)
    }

    @Test func prebufferSchedulingCountsOnlyPreparedTracksAsReady() {
        #expect(PrebufferSchedulingPolicy.readyCount(
            upcomingKeys: ["a", "b", "c"],
            preparedKeys: ["a", "c"]
        ) == 2)
    }

    @Test func prebufferSchedulingSkipsFailedPreparedAndActiveKeysToFillSlots() {
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            upcomingKeys: ["a", "b", "c", "d"],
            activeKeys: ["a"],
            preparedKeys: ["b"],
            failedKeys: ["c"],
            maxConcurrentTasks: 3
        )

        #expect(scheduled == ["d"])
    }

    @Test func nowPlayingArtworkPolicyAvoidsDuplicateLoadsForCachedOrInFlightSongs() {
        #expect(NowPlayingArtworkLoadPolicy.shouldStartLoad(
            songID: "song-1",
            inFlightSongID: nil,
            cachedSongIDs: []
        ) == true)
        #expect(NowPlayingArtworkLoadPolicy.shouldStartLoad(
            songID: "song-1",
            inFlightSongID: "song-1",
            cachedSongIDs: []
        ) == false)
        #expect(NowPlayingArtworkLoadPolicy.shouldStartLoad(
            songID: "song-1",
            inFlightSongID: nil,
            cachedSongIDs: ["song-1"]
        ) == false)
    }

    @Test func remoteCommandApplicationStateIsReferenceCounted() {
        var state = RemoteCommandApplicationState()

        #expect(state.isApplying == false)
        state.begin()
        state.begin()
        #expect(state.isApplying == true)
        state.end()
        #expect(state.isApplying == true)
        state.end()
        #expect(state.isApplying == false)
        state.end()
        #expect(state.isApplying == false)
    }

    @Test @MainActor func syncDelegateEventQueueRunsEventsInOrderAndDrains() async {
        let queue = SyncDelegateEventQueue()
        var values: [Int] = []

        await queue.enqueue {
            values.append(1)
        }
        await queue.enqueue {
            values.append(2)
        }
        await queue.waitForIdle()

        #expect(values == [1, 2])
    }

    @Test @MainActor func syncDelegateEventQueueRunsReentrantEventsAfterCurrentEvent() async {
        let queue = SyncDelegateEventQueue()
        var values: [Int] = []
        var enqueueThirdTask: Task<Void, Never>?

        await queue.enqueue {
            values.append(1)
            enqueueThirdTask = Task {
                await queue.enqueue {
                    values.append(3)
                }
            }
        }
        await queue.enqueue {
            values.append(2)
        }
        await queue.waitForIdle()
        await enqueueThirdTask?.value
        await queue.waitForIdle()

        #expect(values == [1, 2, 3])
    }

    @Test @MainActor func syncDelegateEventQueueWaitForIdleIncludesReentrantEvents() async {
        let queue = SyncDelegateEventQueue()
        var values: [Int] = []

        await queue.enqueue {
            values.append(1)
            Task {
                await queue.enqueue {
                    values.append(3)
                }
            }
        }
        await queue.enqueue {
            values.append(2)
        }
        await queue.waitForIdle()

        #expect(values == [1, 2, 3])
    }

    @Test @MainActor func syncDelegateEventQueuePreservesLargeDelegateBurstOrder() async {
        let queue = SyncDelegateEventQueue()
        var values: [Int] = []

        for value in 0..<100 {
            await queue.enqueue {
                values.append(value)
            }
        }
        await queue.waitForIdle()

        #expect(values == Array(0..<100))
    }

    @Test @MainActor func syncDelegateEventSubmitterPreservesNonisolatedSubmissionOrder() async {
        let submitter = SyncDelegateEventSubmitter(label: "WRhythm.Tests.SyncDelegateSubmitter")
        var values: [Int] = []

        for value in 0..<100 {
            submitter.enqueue {
                values.append(value)
                if value == 49 {
                    submitter.enqueue {
                        values.append(100)
                    }
                }
            }
        }
        await submitter.waitForIdle()

        #expect(values == Array(0..<100) + [100])
    }

    @Test @MainActor func syncDelegateEventSubmitterPreservesLargeConcurrentBurstOrder() async {
        let submitter = SyncDelegateEventSubmitter(label: "WRhythm.Tests.SyncDelegateSubmitterLargeBurst")
        var values: [Int] = []

        await withTaskGroup(of: Void.self) { group in
            for value in 0..<500 {
                group.addTask {
                    submitter.enqueue {
                        values.append(value)
                    }
                }
            }
        }
        await submitter.waitForIdle()

        #expect(values.sorted() == Array(0..<500))
        #expect(Set(values).count == 500)
    }

    @Test func serialFileWriteQueuePreservesLatestEnqueuedWrite() throws {
        let queue = SerialFileWriteQueue(label: "WRhythm.Tests.SerialFileWriteQueue")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrhythm-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: url) }

        queue.write(Data("first".utf8), to: url, label: "first test write")
        queue.write(Data("second".utf8), to: url, label: "second test write")
        queue.waitForIdle()

        let value = try String(contentsOf: url, encoding: .utf8)
        #expect(value == "second")
    }

    @Test func downloadProgressStateSerializesProgressUpdates() async {
        let state = DownloadProgressState()

        let initial = await state.reset(expectedBytes: 100)
        let first = await state.append(byteCount: 25)
        let second = await state.append(byteCount: 50)

        #expect(initial.receivedBytes == 0)
        #expect(first.receivedBytes == 25)
        #expect(first.progress == 0.25)
        #expect(second.receivedBytes == 75)
        #expect(second.progress == 0.75)
    }

    @Test func displayPolicyShowsRemoteSharedPlaybackInsteadOfStaleLocalMirror() {
        let visibility = PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: true,
            localIsPlaying: false,
            hasRemotePlayback: true,
            hasActiveSharedPlayback: true,
            remoteQueueMatchesLocal: true
        )

        #expect(visibility.showsLocal == false)
        #expect(visibility.showsRemote == true)
    }

    @Test func displayPolicyShowsLocalPlaybackWhenLocalDeviceIsActivelyPlayingMirroredQueue() {
        let visibility = PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: true,
            localIsPlaying: true,
            hasRemotePlayback: true,
            hasActiveSharedPlayback: false,
            remoteQueueMatchesLocal: true
        )

        #expect(visibility.showsLocal == true)
        #expect(visibility.showsRemote == false)
    }

    @Test func displayPolicyShowsPausedLocalOwnerInsteadOfRemoteMirror() {
        let visibility = PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: true,
            localIsPlaying: false,
            hasRemotePlayback: true,
            hasActiveSharedPlayback: false,
            remoteQueueMatchesLocal: true,
            localIsPlaybackOutput: true
        )

        #expect(visibility.showsLocal == true)
        #expect(visibility.showsRemote == false)
    }

    @Test func remotePauseOnLocalOutputDisplaysPausedOwnerInsteadOfPlayingMirror() throws {
        let now = Date()
        let song = makeSong(id: "song-1")
        let pausedOwnerSession = makeSession(
            songs: [song],
            outputDeviceID: "iphone",
            isPlaying: false,
            position: 120,
            revision: 8,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )
        let ownerSnapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: pausedOwnerSession,
            deviceName: "iPhone",
            platform: "iPhone",
            now: now.addingTimeInterval(1)
        ))
        let visibility = PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: ownerSnapshot.song != nil,
            localIsPlaying: ownerSnapshot.isPlaying,
            hasRemotePlayback: true,
            hasActiveSharedPlayback: false,
            remoteQueueMatchesLocal: true,
            localIsPlaybackOutput: true
        )

        #expect(ownerSnapshot.isPlaying == false)
        #expect(ownerSnapshot.currentTime == 120)
        #expect(visibility.showsLocal == true)
        #expect(visibility.showsRemote == false)
    }

    @Test func remoteObserverDisplaysPausedSharedOutputInsteadOfStaleLocalMirror() throws {
        let now = Date()
        let song = makeSong(id: "song-1")
        let pausedOwnerSession = makeSession(
            songs: [song],
            outputDeviceID: "iphone",
            isPlaying: false,
            position: 120,
            revision: 8,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )

        let sharedSnapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: pausedOwnerSession,
            deviceName: "iPhone",
            platform: "iPhone",
            now: now
        ))
        let visibility = PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: true,
            localIsPlaying: true,
            hasRemotePlayback: sharedSnapshot.song != nil,
            hasActiveSharedPlayback: true,
            remoteQueueMatchesLocal: true,
            localIsPlaybackOutput: false
        )

        #expect(sharedSnapshot.isPlaying == false)
        #expect(sharedSnapshot.currentTime == 120)
        #expect(visibility.showsLocal == false)
        #expect(visibility.showsRemote == true)
    }

    @Test func displayPolicyCanShowIndependentLocalAndRemotePlaybackRows() {
        let visibility = PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: true,
            localIsPlaying: true,
            hasRemotePlayback: true,
            hasActiveSharedPlayback: false,
            remoteQueueMatchesLocal: false
        )

        #expect(visibility.showsLocal == true)
        #expect(visibility.showsRemote == true)
    }

    @Test func credentialImportRejectsPayloadIssuedBeforeLocalLogout() {
        let logoutTime = Date()
        let staleCredentialIssuedAt = logoutTime.addingTimeInterval(-1)

        #expect(CredentialSyncPolicy.shouldImport(incomingIssuedAt: staleCredentialIssuedAt, localClearedAt: logoutTime) == false)
    }

    @Test func credentialImportAcceptsPayloadIssuedAfterLocalLogout() {
        let logoutTime = Date()
        let freshCredentialIssuedAt = logoutTime.addingTimeInterval(1)

        #expect(CredentialSyncPolicy.shouldImport(incomingIssuedAt: freshCredentialIssuedAt, localClearedAt: logoutTime) == true)
    }

    @MainActor
    @Test func credentialPayloadRequiresIssuedAt() {
        let payload = """
        {
          "baseURL": "https://example.test",
          "username": "admin",
          "password": "secret"
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SyncedCredentials.self, from: Data(payload.utf8))
        }
    }

    @MainActor
    @Test func similarSongsResponseIgnoresLegacySimilarSongsPayload() throws {
        let payload = """
        {
          "status": "ok",
          "version": "1.16.1",
          "similarSongs": {
            "song": [
              {
                "id": "legacy-song",
                "title": "Legacy Song",
                "album": "Album",
                "albumId": "album-1",
                "artist": "Artist",
                "artistId": "artist-1",
                "duration": 180
              }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(SimilarSongsResponse.self, from: Data(payload.utf8))

        #expect(response.songs.isEmpty)
    }

    @MainActor
    @Test func similarSongsForSongWithoutArtistIdReturnsEmpty() async throws {
        let song = Song(
            id: "song-without-artist-id",
            title: "Track",
            album: "Album",
            albumId: "album-1",
            artist: "Artist",
            artistId: nil,
            track: 1,
            year: 2026,
            genre: "Genre",
            coverArt: "cover-1",
            size: 1024,
            contentType: "audio/flac",
            suffix: "flac",
            duration: 180,
            bitRate: 900,
            path: "music/song.flac"
        )

        let songs = try await NavidromeAPI.shared.getSimilarSongsForSong(song, count: 10)

        #expect(songs.isEmpty)
    }

    @MainActor
    @Test func downloadedSongRequiresExplicitBitrate() {
        let payload = """
        {
          "songId": "song-1",
          "title": "Track",
          "artist": "Artist",
          "album": "Album",
          "coverArt": "cover-1",
          "filePath": "song-1.mp3",
          "downloadedAt": 1770000000,
          "fileSize": 12345
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DownloadedSong.self, from: Data(payload.utf8))
        }
    }

    private func makeSnapshot(
        id: String = "device-1",
        song: Song? = nil,
        queue: [Song]? = nil,
        isPlaying: Bool = true,
        volume: Double = 0.8,
        currentTime: TimeInterval = 10,
        duration: TimeInterval = 180,
        currentIndex: Int = 0,
        updatedAt: Date
    ) -> PlaybackSnapshot {
        let resolvedSong = song ?? makeSong(id: "song-1")
        let resolvedQueue = queue ?? [resolvedSong]

        return PlaybackSnapshot(
            id: id,
            deviceName: "Mac",
            platform: "Mac",
            song: resolvedSong,
            isPlaying: isPlaying,
            isBuffering: false,
            prebufferedTrackCount: 3,
            volume: volume,
            currentTime: currentTime,
            duration: duration,
            queue: resolvedQueue,
            currentIndex: currentIndex,
            updatedAt: updatedAt
        )
    }

    private func makeSong(id: String) -> Song {
        Song(
            id: id,
            title: "Track \(id)",
            album: "Album",
            albumId: "album-1",
            artist: "Artist",
            artistId: "artist-1",
            track: 1,
            year: 2026,
            genre: "Genre",
            coverArt: "cover-1",
            size: 1024,
            contentType: "audio/flac",
            suffix: "flac",
            duration: 180,
            bitRate: 900,
            path: "music/\(id).flac"
        )
    }

    private func makeSession(
        id: String = "session-1",
        songs: [Song]? = nil,
        currentIndex: Int = 0,
        outputDeviceID: String = "mac",
        isPlaying: Bool = true,
        position: TimeInterval = 10,
        volume: Double? = 0.8,
        revision: Int = 1,
        updatedAt: Date,
        updatedByDeviceID: String = "mac"
    ) -> PlaybackSession {
        let resolvedSongs = songs ?? [makeSong(id: "song-1")]
        return PlaybackSession(
            id: id,
            revision: revision,
            queue: resolvedSongs,
            currentIndex: currentIndex,
            position: position,
            isPlaying: isPlaying,
            volume: volume,
            outputDeviceID: outputDeviceID,
            updatedAt: updatedAt,
            updatedByDeviceID: updatedByDeviceID
        )
    }

    private func makeLocalState(
        queueIDs: [String] = ["song-1"],
        currentSongID: String? = "song-1",
        currentIndex: Int = 0,
        currentTime: TimeInterval = 10,
        isPlaying: Bool = true,
        volume: Double = 0.8
    ) -> LocalPlaybackSyncState {
        LocalPlaybackSyncState(
            queueIDs: queueIDs,
            currentSongID: currentSongID,
            currentIndex: currentIndex,
            currentTime: currentTime,
            isPlaying: isPlaying,
            volume: volume
        )
    }
}
