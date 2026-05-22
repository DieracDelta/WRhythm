//
//  PlaybackSyncPolicyTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing
@testable import WRhythm_Watch_App

struct PlaybackSyncPolicyTests {
    @Test func staleSnapshotOlderThanFreshnessWindowIsRejected() {
        let now = Date()
        let snapshot = makeSnapshot(updatedAt: now.addingTimeInterval(-31))

        #expect(PlaybackSyncPolicy.isStalePlaybackSnapshot(snapshot, current: nil, now: now) == true)
    }

    @Test func snapshotTooFarInFutureIsRejectedAsClockSkewed() {
        let now = Date()
        let snapshot = makeSnapshot(updatedAt: now.addingTimeInterval(11))

        #expect(PlaybackSyncPolicy.isStalePlaybackSnapshot(snapshot, current: nil, now: now) == true)
    }

    @Test func smallFutureClockSkewIsAccepted() {
        let now = Date()
        let snapshot = makeSnapshot(updatedAt: now.addingTimeInterval(5))

        #expect(PlaybackSyncPolicy.isStalePlaybackSnapshot(snapshot, current: nil, now: now) == false)
    }

    @Test func olderSnapshotFromSameDeviceIsRejectedEvenInsideFreshnessWindow() {
        let now = Date()
        let current = makeSnapshot(currentTime: 20, updatedAt: now.addingTimeInterval(-5))
        let older = makeSnapshot(currentTime: 12, updatedAt: now.addingTimeInterval(-6))

        #expect(PlaybackSyncPolicy.isStalePlaybackSnapshot(older, current: current, now: now) == true)
        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(older, current: current) == false)
    }

    @Test func freshSnapshotPublishesWhenQueueOrTrackChanges() {
        let now = Date()
        let current = makeSnapshot(song: makeSong(id: "song-1"), queue: [makeSong(id: "song-1")], updatedAt: now)
        let changed = makeSnapshot(song: makeSong(id: "song-2"), queue: [makeSong(id: "song-2")], updatedAt: now.addingTimeInterval(1))

        #expect(PlaybackSyncPolicy.isStalePlaybackSnapshot(changed, current: current, now: now.addingTimeInterval(1)) == false)
        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(changed, current: current) == true)
    }

    @Test func pauseSnapshotPublishesEvenWhenTrackAndQueueAreUnchanged() {
        let now = Date()
        let current = makeSnapshot(isPlaying: true, currentTime: 42, updatedAt: now)
        let paused = makeSnapshot(isPlaying: false, currentTime: 42.2, updatedAt: now.addingTimeInterval(0.5))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(paused, current: current) == true)
    }

    @Test func smallPlaybackClockDriftDoesNotRepublishImmediately() {
        let now = Date()
        let current = makeSnapshot(currentTime: 42, updatedAt: now)
        let drift = makeSnapshot(currentTime: 43.5, updatedAt: now.addingTimeInterval(0.5))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(drift, current: current) == false)
    }

    @Test func playingProgressReanchorsAfterShortIntervalEvenWithSmallDrift() {
        let now = Date()
        let current = makeSnapshot(currentTime: 42, updatedAt: now)
        let drift = makeSnapshot(currentTime: 43.5, updatedAt: now.addingTimeInterval(2.1))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(drift, current: current) == true)
    }

    @Test func pausedProgressReanchorsOnSubsecondDifference() {
        let now = Date()
        let current = makeSnapshot(isPlaying: false, currentTime: 42, updatedAt: now)
        let correctedPause = makeSnapshot(isPlaying: false, currentTime: 42.5, updatedAt: now.addingTimeInterval(0.5))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(correctedPause, current: current) == true)
    }

    @Test func seekPositionJumpPublishesEvenWhenTrackAndQueueAreUnchanged() {
        let now = Date()
        let current = makeSnapshot(currentTime: 2, updatedAt: now)
        let seeked = makeSnapshot(currentTime: 30, updatedAt: now.addingTimeInterval(0.5))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(seeked, current: current) == true)
    }

    @Test func localPauseStateBypassesPlaybackBroadcastThrottle() {
        let now = Date()
        let playing = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42, updatedAt: now.addingTimeInterval(-0.2))
        let paused = makeSnapshot(id: "mac", isPlaying: false, currentTime: 42.1, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: paused,
            previousSnapshot: playing,
            lastBroadcastAt: now,
            now: now,
            localDeviceID: "mac"
        ) == true)
    }

    @Test func localPlayStateBypassesPlaybackBroadcastThrottle() {
        let now = Date()
        let paused = makeSnapshot(id: "mac", isPlaying: false, currentTime: 42, updatedAt: now.addingTimeInterval(-0.2))
        let playing = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42.1, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: playing,
            previousSnapshot: paused,
            lastBroadcastAt: now,
            now: now,
            localDeviceID: "mac"
        ) == true)
    }

    @Test func progressOnlyPlaybackBroadcastIsThrottledInsideMinimumInterval() {
        let now = Date()
        let previous = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42, updatedAt: now.addingTimeInterval(-0.5))
        let progressed = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42.7, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: progressed,
            previousSnapshot: previous,
            lastBroadcastAt: now.addingTimeInterval(-0.5),
            now: now,
            localDeviceID: "mac"
        ) == false)
    }

    @Test func progressOnlyPlaybackBroadcastPublishesAfterMinimumInterval() {
        let now = Date()
        let previous = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42, updatedAt: now.addingTimeInterval(-2))
        let progressed = makeSnapshot(id: "mac", isPlaying: true, currentTime: 45, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: progressed,
            previousSnapshot: previous,
            lastBroadcastAt: now.addingTimeInterval(-2),
            now: now,
            localDeviceID: "mac"
        ) == true)
    }

    @Test func forcedPlaybackBroadcastPublishesEvenInsideThrottleWindow() {
        let now = Date()
        let previous = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42, updatedAt: now.addingTimeInterval(-0.2))
        let current = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42.1, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: current,
            previousSnapshot: previous,
            lastBroadcastAt: now,
            now: now,
            force: true,
            localDeviceID: "mac"
        ) == true)
    }

    @Test func playbackBroadcastIsSuppressedWhileAnotherDeviceOwnsSharedOutput() {
        let now = Date()
        let previous = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42, updatedAt: now.addingTimeInterval(-2))
        let paused = makeSnapshot(id: "mac", isPlaying: false, currentTime: 42, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: paused,
            previousSnapshot: previous,
            lastBroadcastAt: now.addingTimeInterval(-2),
            now: now,
            sharedOutputDeviceID: "iphone",
            localDeviceID: "mac"
        ) == false)
    }

    @Test func explicitLocalPauseIntentBypassesStaleRemoteOwnerSuppression() {
        let now = Date()
        let previous = makeSnapshot(id: "iphone", isPlaying: true, currentTime: 42, updatedAt: now.addingTimeInterval(-2))
        let paused = makeSnapshot(id: "iphone", isPlaying: false, currentTime: 42, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: paused,
            previousSnapshot: previous,
            lastBroadcastAt: now,
            now: now,
            force: true,
            sharedOutputDeviceID: "mac",
            isExplicitLocalPlaybackIntent: true,
            localDeviceID: "iphone"
        ) == true)
    }

    @Test func localPlayingSnapshotCanClaimPlaybackFromStaleRemoteSharedOutput() {
        let now = Date()
        let previous = makeSnapshot(id: "iphone", isPlaying: false, currentTime: 42, updatedAt: now.addingTimeInterval(-2))
        let playing = makeSnapshot(id: "iphone", isPlaying: true, currentTime: 42, updatedAt: now)

        #expect(PlaybackStateBroadcastPolicy.shouldBroadcast(
            snapshot: playing,
            previousSnapshot: previous,
            lastBroadcastAt: now,
            now: now,
            sharedOutputDeviceID: "mac",
            localDeviceID: "iphone"
        ) == true)
    }

    @Test func remotePauseSnapshotFromMacPublishesOnIPhoneEvenWithTinyTimeDelta() {
        let now = Date()
        let current = makeSnapshot(id: "mac", isPlaying: true, currentTime: 42, updatedAt: now.addingTimeInterval(-0.3))
        let paused = makeSnapshot(id: "mac", isPlaying: false, currentTime: 42.05, updatedAt: now)

        #expect(PlaybackSyncPolicy.isStalePlaybackSnapshot(paused, current: current, now: now) == false)
        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(paused, current: current) == true)
    }

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
        let laterPlayingTelemetry = makeSnapshot(
            id: "iphone",
            isPlaying: true,
            currentTime: 124,
            updatedAt: now.addingTimeInterval(0.5)
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: pausedSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: laterPlayingTelemetry,
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
            isLocalPlaying: true
        ) == true)
    }

    @Test func localPlaybackOwnershipKeepsPausedDeviceFromPublishingOverRemoteOwner() {
        #expect(LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "mac",
            localDeviceID: "iphone",
            isLocalPlaying: false
        ) == false)
    }

    @Test func explicitLocalPauseIntentCanClaimOwnershipFromStaleRemoteOwner() {
        #expect(LocalPlaybackOwnershipPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "mac",
            localDeviceID: "iphone",
            isLocalPlaying: false,
            isExplicitLocalPlaybackIntent: true
        ) == true)
    }

    @Test(arguments: [
        (WatchConnectivitySyncPayloadKind.hello, true),
        (.syncRequest, true),
        (.credentials(hasPayload: true), true),
        (.credentials(hasPayload: false), false),
        (.playbackState, false),
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

    @Test func pauseCommandIsAcknowledgedByPausedRemoteSnapshot() {
        let playback = makeSnapshot(isPlaying: false, updatedAt: Date())

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .pause, by: playback) == true)
        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .play, by: playback) == false)
    }

    @Test func seekCommandIsAcknowledgedOnlyNearRequestedPosition() {
        let now = Date()
        let nearSeekTarget = makeSnapshot(currentTime: 30.5, updatedAt: now)
        let stalePosition = makeSnapshot(currentTime: 2, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .seek, expectedTime: 30, by: nearSeekTarget) == true)
        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .seek, expectedTime: 30, by: stalePosition) == false)
    }

    @Test func seekCommandAcknowledgmentUsesEstimatedPlayingProgress() {
        let now = Date()
        let progressedSnapshot = makeSnapshot(
            isPlaying: true,
            currentTime: 25,
            updatedAt: now.addingTimeInterval(-5)
        )

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(
            action: .seek,
            expectedTime: 30,
            by: progressedSnapshot,
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
        let matchingVolume = makeSnapshot(volume: 0.51, updatedAt: now)
        let differentVolume = makeSnapshot(volume: 0.62, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .setVolume, expectedVolume: 0.5, by: matchingVolume) == true)
        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .setVolume, expectedVolume: 0.5, by: differentVolume) == false)
    }

    @Test func navigationCommandsRequireExpectedQueuePosition() {
        let now = Date()
        let first = makeSong(id: "song-1")
        let second = makeSong(id: "song-2")
        let playback = makeSnapshot(song: second, queue: [first, second], currentIndex: 1, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .next, expectedIndex: 1, by: playback) == true)
        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .next, expectedIndex: 0, by: playback) == false)
    }

    @Test func previousCommandCanAcknowledgeRestartingCurrentTrack() {
        let now = Date()
        let first = makeSong(id: "song-1")
        let second = makeSong(id: "song-2")
        let playback = makeSnapshot(song: second, queue: [first, second], currentTime: 0.5, currentIndex: 1, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(
            action: .previous,
            expectedIndex: 1,
            expectedTime: 0,
            by: playback
        ) == true)
    }

    @Test func playQueueCommandAcknowledgesExpectedQueueAndIndex() {
        let now = Date()
        let songs = [makeSong(id: "song-1"), makeSong(id: "song-2")]
        let playback = makeSnapshot(song: songs[1], queue: songs, currentIndex: 1, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(
            action: .playQueue,
            expectedSongs: songs,
            expectedIndex: 1,
            by: playback
        ) == true)
    }

    @Test func enqueueCommandAcknowledgesInsertedContiguousSongs() {
        let now = Date()
        let songs = [makeSong(id: "song-1"), makeSong(id: "song-2"), makeSong(id: "song-3")]
        let playback = makeSnapshot(song: songs[0], queue: songs, currentIndex: 0, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(
            action: .enqueue,
            expectedSongs: Array(songs[1...2]),
            by: playback
        ) == true)
        #expect(PlaybackCommandSyncPolicy.isAcknowledged(
            action: .enqueue,
            expectedSongs: [songs[2], songs[1]],
            by: playback
        ) == false)
    }

    @Test func syncQueueCommandAcknowledgesExactQueueAndIndex() {
        let now = Date()
        let songs = [makeSong(id: "song-1"), makeSong(id: "song-2")]
        let playback = makeSnapshot(song: songs[0], queue: songs, currentIndex: 0, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(
            action: .syncQueue,
            expectedSongs: songs,
            expectedIndex: 0,
            by: playback
        ) == true)
    }

    @Test func stopCommandAcknowledgesStoppedEmptySnapshot() {
        let playback = PlaybackSnapshot(
            id: "device-1",
            deviceName: "Mac",
            platform: "Mac",
            song: nil,
            isPlaying: false,
            isBuffering: false,
            prebufferedTrackCount: 0,
            volume: 0.8,
            currentTime: 0,
            duration: 0,
            queue: [],
            currentIndex: 0,
            updatedAt: Date()
        )

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .stop, by: playback) == true)
    }

    @Test func acknowledgingSnapshotCanReplaceNewerOptimisticRemoteMirror() {
        let now = Date()
        let optimisticMirror = makeSnapshot(id: "iphone", isPlaying: true, currentTime: 42, updatedAt: now)
        let remotePauseAck = makeSnapshot(id: "iphone", isPlaying: false, currentTime: 42.2, updatedAt: now.addingTimeInterval(-5))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(remotePauseAck, current: optimisticMirror) == false)
        #expect(PendingPlaybackAcknowledgmentPolicy.shouldAcceptAcknowledgingSnapshot(
            remotePauseAck,
            current: optimisticMirror,
            action: .pause
        ) == true)
    }

    @Test func acknowledgingSnapshotMustMatchCurrentQueueIdentity() {
        let now = Date()
        let optimisticMirror = makeSnapshot(id: "iphone", queue: [makeSong(id: "song-1")], updatedAt: now)
        let unrelatedPauseAck = makeSnapshot(
            id: "iphone",
            song: makeSong(id: "song-2"),
            queue: [makeSong(id: "song-2")],
            isPlaying: false,
            updatedAt: now.addingTimeInterval(-5)
        )

        #expect(PendingPlaybackAcknowledgmentPolicy.shouldAcceptAcknowledgingSnapshot(
            unrelatedPauseAck,
            current: optimisticMirror,
            action: .pause
        ) == false)
    }

    @Test func queueAcknowledgmentsCanReplaceChangedOptimisticMirror() {
        let now = Date()
        let oldSong = makeSong(id: "song-1")
        let newSongs = [makeSong(id: "song-2"), makeSong(id: "song-3")]
        let optimisticMirror = makeSnapshot(id: "iphone", song: oldSong, queue: [oldSong], updatedAt: now)
        let remoteQueueAck = makeSnapshot(
            id: "iphone",
            song: newSongs[1],
            queue: newSongs,
            currentIndex: 1,
            updatedAt: now.addingTimeInterval(-1)
        )

        #expect(PendingPlaybackAcknowledgmentPolicy.shouldAcceptAcknowledgingSnapshot(
            remoteQueueAck,
            current: optimisticMirror,
            action: .playQueue,
            expectedSongs: newSongs,
            expectedIndex: 1
        ) == true)
    }

    @Test func queueCommandsInvalidateStalePendingCommandFamilies() {
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .playQueue) == [.transport, .navigation, .seek, .queue, .stop])
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .stop) == [.transport, .navigation, .seek, .queue, .stop])
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .next) == [.navigation, .seek])
        #expect(PendingPlaybackCommandPolicy.commandFamiliesInvalidated(by: .seek).isEmpty)
    }

    @Test func expiredCommandInvalidatesMatchingOptimisticRemotePlayback() {
        #expect(PendingPlaybackCommandExpiryPolicy.shouldInvalidateOptimisticRemotePlayback(
            remotePlaybackID: "iphone",
            expiredDeviceID: "iphone"
        ) == true)
        #expect(PendingPlaybackCommandExpiryPolicy.shouldInvalidateOptimisticRemotePlayback(
            remotePlaybackID: "mac",
            expiredDeviceID: "iphone"
        ) == false)
    }

    @Test func playbackBroadcastDeliveryOnlyRecordsSuccessfulSends() {
        #expect(PlaybackStateBroadcastDeliveryPolicy.shouldRecordAttempt(didSend: true) == true)
        #expect(PlaybackStateBroadcastDeliveryPolicy.shouldRecordAttempt(didSend: false) == false)
    }

    @Test func telemetryBroadcastsAreThrottledSeparately() {
        let now = Date()

        #expect(PlaybackTelemetryBroadcastPolicy.shouldBroadcast(lastBroadcastAt: nil, now: now) == true)
        #expect(PlaybackTelemetryBroadcastPolicy.shouldBroadcast(lastBroadcastAt: now.addingTimeInterval(-0.5), now: now) == false)
        #expect(PlaybackTelemetryBroadcastPolicy.shouldBroadcast(lastBroadcastAt: now.addingTimeInterval(-2), now: now) == true)
    }

    @Test func transportFailuresInvalidatePlaybackButNotDurablePayloads() {
        #expect(SyncTransportFailurePolicy.shouldInvalidatePlaybackBroadcastAttempt(kind: .playbackState) == true)
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
        #expect(WatchConnectivitySendFailurePolicy.shouldFallbackToUserInfo(kind: .playbackState, canQueuePayload: true) == false)
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

    @Test func pendingPlaybackCommandDefersConflictingNonAcknowledgingSnapshots() {
        #expect(PendingPlaybackSnapshotPolicy.shouldApplySnapshot(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: false
        ) == false)
        #expect(PendingPlaybackSnapshotPolicy.shouldApplySnapshot(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: true
        ) == true)
        #expect(PendingPlaybackSnapshotPolicy.shouldApplySnapshot(
            hasPendingCommandForDevice: false,
            isAcknowledgingPendingCommand: false
        ) == true)
    }

    @Test func pendingPauseKeepsOptimisticPausedMirrorUntilAcknowledgmentArrives() {
        let now = Date()
        let optimisticPausedMirror = makeSnapshot(id: "mac", isPlaying: false, currentTime: 120, updatedAt: now)
        let delayedPlayingSnapshot = makeSnapshot(id: "mac", isPlaying: true, currentTime: 122, updatedAt: now.addingTimeInterval(0.5))
        let pausedAcknowledgment = makeSnapshot(id: "mac", isPlaying: false, currentTime: 120.3, updatedAt: now.addingTimeInterval(-1))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(delayedPlayingSnapshot, current: optimisticPausedMirror) == true)
        #expect(PendingPlaybackSnapshotPolicy.shouldApplySnapshot(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: false
        ) == false)
        #expect(PendingPlaybackAcknowledgmentPolicy.shouldAcceptAcknowledgingSnapshot(
            pausedAcknowledgment,
            current: optimisticPausedMirror,
            action: .pause
        ) == true)
        #expect(PendingPlaybackSnapshotPolicy.shouldApplySnapshot(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: true
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
        #expect(PendingPlaybackSnapshotPolicy.shouldApplySnapshot(
            hasPendingCommandForDevice: true,
            isAcknowledgingPendingCommand: false
        ) == false)
        #expect(PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
            pausedSession,
            action: .pause
        ) == true)
        #expect(PendingPlaybackSnapshotPolicy.shouldApplySnapshot(
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
        let optimisticMirror = makeSnapshot(id: "mac", isPlaying: true, currentTime: 120, updatedAt: now)
        let macPausedAck = makeSnapshot(id: "mac", isPlaying: false, currentTime: 120.2, updatedAt: now.addingTimeInterval(-2))

        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .pause,
            targetDeviceID: "mac",
            localDeviceID: "mac"
        ) == true)
        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(macPausedAck, current: optimisticMirror) == false)
        #expect(PendingPlaybackAcknowledgmentPolicy.shouldAcceptAcknowledgingSnapshot(
            macPausedAck,
            current: optimisticMirror,
            action: .pause
        ) == true)
    }

    @Test func remoteSeekRoundTripCanApplyAndAcknowledgeAcrossDevices() {
        let now = Date()
        let optimisticMirror = makeSnapshot(id: "mac", currentTime: 2, updatedAt: now)
        let macSeekAck = makeSnapshot(id: "mac", currentTime: 30.5, updatedAt: now.addingTimeInterval(-2))

        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .seek,
            targetDeviceID: "mac",
            localDeviceID: "mac"
        ) == true)
        #expect(PendingPlaybackAcknowledgmentPolicy.shouldAcceptAcknowledgingSnapshot(
            macSeekAck,
            current: optimisticMirror,
            action: .seek,
            expectedTime: 30
        ) == true)
    }

    @Test func stalePlaybackSnapshotIsRejectedBeforeFingerprintingUnlessItAcknowledgesPendingCommand() {
        let now = Date()
        let current = makeSnapshot(id: "mac", updatedAt: now)
        let stale = makeSnapshot(id: "mac", currentTime: 3, updatedAt: now.addingTimeInterval(-31))

        #expect(PlaybackSnapshotReceivePolicy.shouldAccept(
            stale,
            current: current,
            isAcknowledgingPendingCommand: false,
            now: now
        ) == false)
        #expect(PlaybackSnapshotReceivePolicy.shouldAccept(
            stale,
            current: current,
            isAcknowledgingPendingCommand: true,
            now: now
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

    @Test func defaultControlTargetYieldsFromStaleSharedOutputToFreshRemotePlayback() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone", "mac"],
            sharedSessionOutputDeviceID: "iphone",
            activeSharedPlaybackID: nil,
            remotePlaybackID: "mac"
        ) == "mac")
    }

    @Test func defaultControlTargetKeepsSelectedSharedOutputWhenItIsStillActive() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone", "mac"],
            sharedSessionOutputDeviceID: "iphone",
            activeSharedPlaybackID: "iphone",
            remotePlaybackID: "mac"
        ) == "iphone")
    }

    @Test func defaultControlTargetDoesNotYieldToUnavailableRemotePlayback() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone"],
            sharedSessionOutputDeviceID: "iphone",
            activeSharedPlaybackID: nil,
            remotePlaybackID: "mac"
        ) == "iphone")
    }

    @Test func defaultControlTargetKeepsSelectedIndependentRemoteTarget() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "watch",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["watch", "mac"],
            sharedSessionOutputDeviceID: "iphone",
            activeSharedPlaybackID: nil,
            remotePlaybackID: "mac"
        ) == "watch")
    }

    @Test func defaultControlTargetReturnsNilForLocalOrInvalidSelection() {
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "iphone-local",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone-local", "mac"],
            sharedSessionOutputDeviceID: "iphone",
            activeSharedPlaybackID: nil,
            remotePlaybackID: "mac"
        ) == nil)
        #expect(PlaybackControlTargetPolicy.resolvedDefaultRemoteTargetID(
            selectedTargetID: "missing",
            localDeviceID: "iphone-local",
            availableTargetIDs: ["iphone-local", "mac"],
            sharedSessionOutputDeviceID: "missing",
            activeSharedPlaybackID: nil,
            remotePlaybackID: "mac"
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

    @Test func playbackSnapshotFingerprintSuppressesSamePayloadFromSecondTransport() {
        let snapshot = makeSnapshot(updatedAt: Date())
        let fingerprint = PlaybackSnapshotFingerprintPolicy.fingerprint(for: snapshot)

        #expect(PlaybackSnapshotFingerprintPolicy.shouldProcess(
            fingerprint: fingerprint,
            processedFingerprints: []
        ) == true)
        #expect(PlaybackSnapshotFingerprintPolicy.shouldProcess(
            fingerprint: fingerprint,
            processedFingerprints: [fingerprint]
        ) == false)
    }

    @Test func playbackSnapshotFingerprintNormalizesTransportTimingJitter() {
        let now = Date()
        let first = makeSnapshot(currentTime: 42.1, updatedAt: now)
        let second = makeSnapshot(currentTime: 42.8, updatedAt: now.addingTimeInterval(0.7))

        #expect(PlaybackSnapshotFingerprintPolicy.fingerprint(for: first) == PlaybackSnapshotFingerprintPolicy.fingerprint(for: second))
    }

    @Test func playbackSnapshotFingerprintKeepsOnlyRecentFingerprints() {
        let ids = (0..<505).map { "fingerprint-\($0)" }
        let trimmed = PlaybackSnapshotFingerprintPolicy.trimmedFingerprintOrder(ids)

        #expect(trimmed.count == PlaybackSnapshotFingerprintPolicy.maxTrackedFingerprints)
        #expect(trimmed.first == "fingerprint-5")
        #expect(trimmed.last == "fingerprint-504")
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
            remotePlayback: nil,
            now: now
        ))

        #expect(snapshot.currentTime == 15)
        #expect(snapshot.updatedAt == now)
    }

    @Test func playbackSessionSnapshotKeepsPlayingSessionOverPauseTelemetry() throws {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: true,
            position: 10,
            updatedAt: now.addingTimeInterval(-5)
        )
        let remotePause = makeSnapshot(
            id: "mac",
            isPlaying: false,
            currentTime: 13,
            updatedAt: now
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: session,
            deviceName: "Mac",
            platform: "Mac",
            remotePlayback: remotePause,
            now: now
        ))

        #expect(snapshot.isPlaying == true)
        #expect(snapshot.currentTime == 15)
        #expect(snapshot.updatedAt == now)
    }

    @Test func playbackSessionSnapshotKeepsSessionStateWhenRemotePlaybackIsOlder() throws {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: false,
            position: 20,
            updatedAt: now
        )
        let staleRemotePlaying = makeSnapshot(
            id: "mac",
            isPlaying: true,
            currentTime: 12,
            updatedAt: now.addingTimeInterval(-5)
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: session,
            deviceName: "Mac",
            platform: "Mac",
            remotePlayback: staleRemotePlaying,
            now: now
        ))

        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 20)
        #expect(snapshot.updatedAt == now)
    }

    @Test func stalePlayingTelemetryCannotOverwriteNewerPausedSession() throws {
        let now = Date()
        let pausedSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: false,
            position: 42,
            revision: 6,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )
        let playingTelemetry = makeSnapshot(
            id: "iphone",
            isPlaying: true,
            currentTime: 44,
            updatedAt: now.addingTimeInterval(2)
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: pausedSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: playingTelemetry,
            now: now.addingTimeInterval(2)
        ))

        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 42)
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
        let olderPlayingTelemetry = makeSnapshot(
            id: "iphone",
            isPlaying: true,
            currentTime: 119,
            updatedAt: now.addingTimeInterval(-1)
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
            remotePlayback: olderPlayingTelemetry,
            now: now
        ))

        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 120)
    }

    @Test func playbackSessionSnapshotUsesFreshLiveRemotePlayingProgressOverSessionEstimate() throws {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: true,
            position: 10,
            updatedAt: now.addingTimeInterval(-5)
        )
        let remotePlaying = makeSnapshot(
            id: "mac",
            isPlaying: true,
            currentTime: 13,
            updatedAt: now.addingTimeInterval(-1)
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: session,
            deviceName: "Mac",
            platform: "Mac",
            remotePlayback: remotePlaying,
            now: now
        ))

        #expect(snapshot.isPlaying == true)
        #expect(snapshot.currentTime == 14)
        #expect(snapshot.updatedAt == now)
    }

    @Test func playbackSessionSnapshotYieldsToFreshDifferentRemoteOutput() {
        let now = Date()
        let staleIPhoneSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 30,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "iphone"
        )
        let freshMacPlayback = makeSnapshot(
            id: "mac",
            song: makeSong(id: "song-1"),
            queue: [makeSong(id: "song-1")],
            isPlaying: true,
            currentTime: 35,
            updatedAt: now
        )

        let snapshot = PlaybackSessionSnapshotPolicy.snapshot(
            from: staleIPhoneSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: freshMacPlayback,
            now: now
        )

        #expect(snapshot == nil)
    }

    @Test func playbackSessionSnapshotYieldsToFreshDifferentRemotePause() {
        let now = Date()
        let staleIPhoneSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 30,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "iphone"
        )
        let freshMacPause = makeSnapshot(
            id: "mac",
            song: makeSong(id: "song-1"),
            queue: [makeSong(id: "song-1")],
            isPlaying: false,
            currentTime: 35,
            updatedAt: now
        )

        let snapshot = PlaybackSessionSnapshotPolicy.snapshot(
            from: staleIPhoneSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: freshMacPause,
            now: now
        )

        #expect(snapshot == nil)
    }

    @Test func playbackSessionSnapshotYieldsToFreshDifferentRemoteWithSparseQueue() {
        let now = Date()
        let staleIPhoneSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 30,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "iphone"
        )
        let freshMacPlayback = makeSnapshot(
            id: "mac",
            song: makeSong(id: "song-1"),
            queue: [],
            isPlaying: true,
            currentTime: 35,
            updatedAt: now
        )

        let snapshot = PlaybackSessionSnapshotPolicy.snapshot(
            from: staleIPhoneSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: freshMacPlayback,
            now: now
        )

        #expect(snapshot == nil)
    }

    @Test func playbackSessionSnapshotKeepsSessionWhenDifferentRemotePlaybackIsOlder() throws {
        let now = Date()
        let currentIPhoneSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: false,
            position: 40,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )
        let staleMacPlayback = makeSnapshot(
            id: "mac",
            song: makeSong(id: "song-1"),
            queue: [makeSong(id: "song-1")],
            isPlaying: true,
            currentTime: 35,
            updatedAt: now.addingTimeInterval(-5)
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: currentIPhoneSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: staleMacPlayback,
            now: now
        ))

        #expect(snapshot.id == "iphone")
        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 40)
    }

    @Test func playbackSessionSnapshotKeepsSessionWhenDifferentRemoteSongDoesNotMatch() throws {
        let now = Date()
        let staleIPhoneSession = makeSession(
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 30,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "iphone"
        )
        let freshMacPlayback = makeSnapshot(
            id: "mac",
            song: makeSong(id: "song-2"),
            queue: [makeSong(id: "song-2")],
            isPlaying: true,
            currentTime: 35,
            updatedAt: now
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: staleIPhoneSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: freshMacPlayback,
            now: now
        ))

        #expect(snapshot.id == "iphone")
        #expect(snapshot.song?.id == "song-1")
        #expect(snapshot.currentTime == 35)
    }

    @Test func playbackSessionSnapshotKeepsSessionWhenDifferentRemoteQueueDoesNotMatch() throws {
        let now = Date()
        let staleIPhoneSession = makeSession(
            songs: [makeSong(id: "song-1"), makeSong(id: "song-2")],
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 30,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "iphone"
        )
        let freshMacPlayback = makeSnapshot(
            id: "mac",
            song: makeSong(id: "song-1"),
            queue: [makeSong(id: "song-1"), makeSong(id: "song-3")],
            isPlaying: true,
            currentTime: 35,
            updatedAt: now
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: staleIPhoneSession,
            deviceName: "iPhone",
            platform: "iPhone",
            remotePlayback: freshMacPlayback,
            now: now
        ))

        #expect(snapshot.id == "iphone")
        #expect(snapshot.queue.map(\.id) == ["song-1", "song-2"])
        #expect(snapshot.currentTime == 35)
    }

    @Test func playbackSessionSnapshotKeepsPlayingSessionOverSameOutputPauseTelemetryWithSparseQueue() throws {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: true,
            position: 10,
            updatedAt: now.addingTimeInterval(-5)
        )
        let remotePause = makeSnapshot(
            id: "mac",
            song: makeSong(id: "song-1"),
            queue: [],
            isPlaying: false,
            currentTime: 13,
            updatedAt: now
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: session,
            deviceName: "Mac",
            platform: "Mac",
            remotePlayback: remotePause,
            now: now
        ))

        #expect(snapshot.id == "mac")
        #expect(snapshot.isPlaying == true)
        #expect(snapshot.currentTime == 15)
        #expect(snapshot.queue.map(\.id) == ["song-1"])
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

    @Test func remotePlaybackApplicationStateIsReferenceCounted() {
        var state = RemotePlaybackApplicationState()

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

    @Test func legacyCredentialsOnlyImportWhenDeviceHasNeverClearedCredentials() {
        #expect(CredentialSyncPolicy.shouldImport(incomingIssuedAt: nil, localClearedAt: .distantPast) == true)
        #expect(CredentialSyncPolicy.shouldImport(incomingIssuedAt: nil, localClearedAt: Date()) == false)
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
