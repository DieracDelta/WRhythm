//
//  PlaybackSyncPolicyTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing

#if os(watchOS)
@testable import WRhythm_Watch_App
#else
@testable import WRhythm
#endif

struct PlaybackSyncPolicyTests {
    @Test func newerSessionRevisionWinsOverCurrentSession() {
        let now = Date()
        let current = makeSession(revision: 4, updatedAt: now, updatedByDeviceID: "iphone")
        let older = makeSession(revision: 3, updatedAt: now.addingTimeInterval(10), updatedByDeviceID: "iphone")
        let newer = makeSession(revision: 5, updatedAt: now.addingTimeInterval(-10), updatedByDeviceID: "iphone")

        #expect(PlaybackSessionSyncPolicy.shouldApply(older, over: current) == false)
        #expect(PlaybackSessionSyncPolicy.shouldApply(newer, over: current) == true)
    }

    @Test func newerOutputHandoffWinsEvenWhenLocalRevisionIsLower() {
        let now = Date()
        let staleMacView = makeSession(
            outputDeviceID: "mac",
            isPlaying: false,
            revision: 120,
            updatedAt: now.addingTimeInterval(-1),
            updatedByDeviceID: "mac"
        )
        let iphoneMoveHere = makeSession(
            outputDeviceID: "iphone",
            isPlaying: true,
            revision: 8,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(iphoneMoveHere, over: staleMacView, now: now) == true)
    }

    @Test func olderOutputOwnerCannotReclaimWithHigherRevisionAfterMoveHere() {
        let now = Date()
        let iphoneMoveHere = makeSession(
            outputDeviceID: "iphone",
            isPlaying: true,
            revision: 8,
            updatedAt: now,
            updatedByDeviceID: "iphone"
        )
        let delayedMacRebroadcast = makeSession(
            outputDeviceID: "mac",
            isPlaying: false,
            revision: 120,
            updatedAt: now.addingTimeInterval(-1),
            updatedByDeviceID: "mac"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(delayedMacRebroadcast, over: iphoneMoveHere, now: now) == false)
    }

    @Test func newerOwnerPlaybackBeatsObserverConnectivityPauseEvenWithLowerRevision() {
        let now = Date()
        let observerPause = makeSession(
            outputDeviceID: "watch",
            isPlaying: false,
            revision: 139,
            updatedAt: now.addingTimeInterval(-1),
            updatedByDeviceID: "iphone"
        )
        let watchStillPlaying = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            revision: 108,
            updatedAt: now,
            updatedByDeviceID: "watch"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(watchStillPlaying, over: observerPause, now: now) == true)
    }

    @Test func olderObserverConnectivityPauseCannotOverrideNewerOwnerPlaybackWithHigherRevision() {
        let now = Date()
        let watchStillPlaying = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            revision: 108,
            updatedAt: now,
            updatedByDeviceID: "watch"
        )
        let delayedObserverPause = makeSession(
            outputDeviceID: "watch",
            isPlaying: false,
            revision: 139,
            updatedAt: now.addingTimeInterval(-1),
            updatedByDeviceID: "iphone"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(delayedObserverPause, over: watchStillPlaying, now: now) == false)
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

    @Test func reconnectBootstrapPublishesLocalPlaybackWithoutExistingSharedSession() {
        #expect(SyncStateRefreshPublicationPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: nil,
            localDeviceID: "mac",
            hasLocalPlayback: true
        ) == true)
    }

    @Test func reconnectBootstrapDoesNotPublishLocalPlaybackOverActiveRemoteOwner() {
        #expect(SyncStateRefreshPublicationPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "iphone",
            localDeviceID: "mac",
            hasLocalPlayback: true
        ) == false)
    }

    @Test func reconnectBootstrapPublishesActiveLocalPlaybackOverStaleRemoteOwner() {
        let now = Date()
        #expect(SyncStateRefreshPublicationPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "mac",
            localDeviceID: "iphone",
            hasLocalPlayback: true,
            isLocalPlaying: true,
            localUpdatedAt: now,
            sharedUpdatedAt: now.addingTimeInterval(-1)
        ) == true)
    }

    @Test func reconnectBootstrapDoesNotLetOlderActiveLocalPlaybackReclaimNewerRemoteOwner() {
        let now = Date()
        #expect(SyncStateRefreshPublicationPolicy.shouldPublishLocalPlayback(
            sharedOutputDeviceID: "iphone",
            localDeviceID: "mac",
            hasLocalPlayback: true,
            isLocalPlaying: true,
            localUpdatedAt: now.addingTimeInterval(-1),
            sharedUpdatedAt: now
        ) == false)
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

    @Test func remotePlayQueuePublishesPlayingIntentBeforePlayerIsReady() {
        let intendedState = RemoteCommandLocalPublicationPolicy.intendedIsPlaying(after: .playQueue)

        #expect(intendedState == true)
        #expect(LocalPlaybackPublicationPolicy.publishedIsPlaying(
            playerIsPlaying: false,
            intendedIsPlaying: intendedState
        ) == true)
    }

    @Test func localPlaybackStartupDisplaysAutoplayIntentBeforePlayerIsReady() {
        #expect(PlaybackStartupStatePolicy.isPlayingDuringStartup(autoplay: true) == true)
        #expect(PlaybackStartupStatePolicy.isPlayingDuringStartup(autoplay: false) == false)
    }

    @Test func localOutputControlsDisplaySharedSessionPlayingWhilePlayerStateLags() {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: true,
            position: 42,
            updatedAt: now
        )

        #expect(LocalPlaybackDisplayStatePolicy.effectiveIsPlaying(
            playerIsPlaying: false,
            sharedSession: session,
            localDeviceID: "mac",
            localQueueIDs: session.queue.map { $0.id },
            localCurrentSongID: session.currentSong?.id,
            localCurrentIndex: session.currentIndex
        ) == true)
    }

    @Test func localOutputControlsDisplaySharedSessionPausedWhilePlayerStateLags() {
        let now = Date()
        let session = makeSession(
            outputDeviceID: "mac",
            isPlaying: false,
            position: 42,
            updatedAt: now
        )

        #expect(LocalPlaybackDisplayStatePolicy.effectiveIsPlaying(
            playerIsPlaying: true,
            sharedSession: session,
            localDeviceID: "mac",
            localQueueIDs: session.queue.map { $0.id },
            localCurrentSongID: session.currentSong?.id,
            localCurrentIndex: session.currentIndex
        ) == false)
    }

    @Test func localPlaybackPublicationUsesLogicalTimeWhenQueuePositionChanges() {
        let oldSong = makeSong(id: "song-1")
        let newSong = makeSong(id: "song-2")
        let previousSession = makeSession(
            songs: [oldSong, newSong],
            currentIndex: 0,
            outputDeviceID: "mac",
            isPlaying: true,
            position: 93,
            updatedAt: Date()
        )

        #expect(LocalPlaybackPublicationPositionPolicy.publishedPosition(
            playerLiveTime: 93,
            logicalCurrentTime: 0,
            previousSession: previousSession,
            queueIDs: [oldSong.id, newSong.id],
            currentSongID: newSong.id,
            currentIndex: 1
        ) == 0)
    }

    @Test func localPlaybackPublicationUsesLogicalTimeWhenQueuePositionChangesBackwards() {
        let firstSong = makeSong(id: "song-1")
        let oldSong = makeSong(id: "song-2")
        let previousSession = makeSession(
            songs: [firstSong, oldSong],
            currentIndex: 1,
            outputDeviceID: "mac",
            isPlaying: true,
            position: 93,
            updatedAt: Date()
        )

        #expect(LocalPlaybackPublicationPositionPolicy.publishedPosition(
            playerLiveTime: 93,
            logicalCurrentTime: 0,
            previousSession: previousSession,
            queueIDs: [firstSong.id, oldSong.id],
            currentSongID: firstSong.id,
            currentIndex: 0
        ) == 0)
    }

    @Test func localPlaybackPublicationPositionPolicyIsDeviceAgnostic() {
        let oldSong = makeSong(id: "song-1")
        let newSong = makeSong(id: "song-2")
        let previousSession = makeSession(
            songs: [oldSong, newSong],
            currentIndex: 0,
            outputDeviceID: "iphone",
            isPlaying: true,
            position: 93,
            updatedAt: Date()
        )

        #expect(LocalPlaybackPublicationPositionPolicy.publishedPosition(
            playerLiveTime: 93,
            logicalCurrentTime: 0,
            previousSession: previousSession,
            queueIDs: [oldSong.id, newSong.id],
            currentSongID: newSong.id,
            currentIndex: 1
        ) == 0)
    }

    @Test func localPlaybackPublicationUsesLiveTimeWhenQueuePositionMatches() {
        let song = makeSong(id: "song-1")
        let previousSession = makeSession(
            songs: [song],
            currentIndex: 0,
            outputDeviceID: "mac",
            isPlaying: true,
            position: 90,
            updatedAt: Date()
        )

        #expect(LocalPlaybackPublicationPositionPolicy.publishedPosition(
            playerLiveTime: 93,
            logicalCurrentTime: 92.8,
            previousSession: previousSession,
            queueIDs: [song.id],
            currentSongID: song.id,
            currentIndex: 0
        ) == 93)
    }

    @Test func localPlaybackPublicationUsesLogicalTimeWhenSameTrackSeekIsPending() {
        let song = makeSong(id: "song-1")
        let previousSession = makeSession(
            songs: [song],
            currentIndex: 0,
            outputDeviceID: "mac",
            isPlaying: true,
            position: 20,
            updatedAt: Date()
        )

        #expect(LocalPlaybackPublicationPositionPolicy.publishedPosition(
            playerLiveTime: 20,
            logicalCurrentTime: 93,
            previousSession: previousSession,
            queueIDs: [song.id],
            currentSongID: song.id,
            currentIndex: 0
        ) == 93)
    }

    @Test func localPlaybackPublicationUsesLogicalZeroWhenPreviousRestartsCurrentTrack() {
        let song = makeSong(id: "song-1")
        let previousSession = makeSession(
            songs: [song],
            currentIndex: 0,
            outputDeviceID: "mac",
            isPlaying: true,
            position: 93,
            updatedAt: Date()
        )

        #expect(LocalPlaybackPublicationPositionPolicy.publishedPosition(
            playerLiveTime: 93,
            logicalCurrentTime: 0,
            previousSession: previousSession,
            queueIDs: [song.id],
            currentSongID: song.id,
            currentIndex: 0
        ) == 0)
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

    @Test func credentialSyncBootstrapOffersCredentialsWhenLocalDeviceHasThem() {
        #expect(CredentialSyncBootstrapPolicy.shouldAuthorizeImportOnBootstrap(
            localCredentialSyncEnabled: true,
            localHasCredentials: false
        ) == true)
        #expect(CredentialSyncBootstrapPolicy.shouldAuthorizeImportOnBootstrap(
            localCredentialSyncEnabled: false,
            localHasCredentials: false
        ) == false)
        #expect(CredentialSyncBootstrapPolicy.shouldAuthorizeImportOnBootstrap(
            localCredentialSyncEnabled: true,
            localHasCredentials: true
        ) == false)

        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentials(
            localCredentialSyncEnabled: true,
            localHasCredentials: true
        ) == true)
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentials(
            localCredentialSyncEnabled: false,
            localHasCredentials: true
        ) == false)
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentials(
            localCredentialSyncEnabled: true,
            localHasCredentials: false
        ) == false)
    }

    @Test func credentialSyncRequestsCredentialsWhenHelloAdvertisesAvailableCredentials() {
        #expect(CredentialSyncBootstrapPolicy.shouldRequestCredentialsFromHello(
            localCredentialSyncEnabled: true,
            localHasCredentials: false,
            senderCredentialSyncEnabled: true,
            senderHasCredentials: true
        ) == true)
        #expect(CredentialSyncBootstrapPolicy.shouldRequestCredentialsFromHello(
            localCredentialSyncEnabled: true,
            localHasCredentials: true,
            senderCredentialSyncEnabled: true,
            senderHasCredentials: true
        ) == false)
        #expect(CredentialSyncBootstrapPolicy.shouldRequestCredentialsFromHello(
            localCredentialSyncEnabled: true,
            localHasCredentials: false,
            senderCredentialSyncEnabled: true,
            senderHasCredentials: false
        ) == false)
    }

    @Test func credentialSyncRequestOffersCredentialsOnlyToEmptyCredentialSyncPeers() {
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentialsToRequester(
            localCredentialSyncEnabled: true,
            localHasCredentials: true,
            requesterCredentialSyncEnabled: true,
            requesterHasCredentials: false
        ) == true)
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentialsToRequester(
            localCredentialSyncEnabled: true,
            localHasCredentials: true,
            requesterCredentialSyncEnabled: false,
            requesterHasCredentials: false
        ) == false)
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentialsToRequester(
            localCredentialSyncEnabled: true,
            localHasCredentials: true,
            requesterCredentialSyncEnabled: true,
            requesterHasCredentials: true
        ) == false)
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentialsToRequester(
            localCredentialSyncEnabled: true,
            localHasCredentials: false,
            requesterCredentialSyncEnabled: true,
            requesterHasCredentials: false
        ) == false)
    }

    @Test func syncRequestTargetsOnlyHandleMatchingDeviceID() {
        #expect(SyncRequestTargetPolicy.shouldHandle(targetDeviceID: nil, localDeviceID: "iphone") == true)
        #expect(SyncRequestTargetPolicy.shouldHandle(targetDeviceID: "iphone", localDeviceID: "iphone") == true)
        #expect(SyncRequestTargetPolicy.shouldHandle(targetDeviceID: "iphone", localDeviceID: "mac") == false)
    }

    @Test func watchAndMacDoNotHaveDirectDiscoveryTransport() {
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .appleWatch, remote: .mac) == false)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .mac, remote: .appleWatch) == false)
    }

    @Test func iPhoneCanBridgeDurablePresenceBetweenWatchConnectivityAndMultipeer() {
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .hello,
            receivedVia: .watchConnectivity,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .credentials(hasPayload: true),
            receivedVia: .multipeer,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
    }

    @Test func iPhoneCanBridgeLivePlaybackBetweenWatchConnectivityAndMultipeer() {
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .playbackSession,
            receivedVia: .watchConnectivity,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .playbackCommand,
            receivedVia: .watchConnectivity,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .playbackSession,
            receivedVia: .multipeer,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .playbackCommand,
            receivedVia: .multipeer,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
    }

    @Test func bridgeRequiresIPhoneAndDestinationTransport() {
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .hello,
            receivedVia: .multipeer,
            localPlatform: .mac,
            hasDestinationTransport: true
        ) == false)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .hello,
            receivedVia: .multipeer,
            localPlatform: .iPhone,
            hasDestinationTransport: false
        ) == false)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .playbackSession,
            receivedVia: .watchConnectivity,
            localPlatform: .iPhone,
            hasDestinationTransport: false
        ) == false)
    }

    @Test func relayedLivePlaybackEnvelopeIsStillDeduplicatedOnReturnPath() {
        let processedEnvelopeIDs: Set<String> = ["watch-session-1"]

        #expect(SyncDuplicatePolicy.shouldProcess(
            envelopeID: "watch-session-1",
            processedEnvelopeIDs: processedEnvelopeIDs
        ) == false)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .playbackSession,
            receivedVia: .multipeer,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
    }

    @Test func playbackTargetsOnlyExposeReachableControlPaths() {
        #expect(PlaybackTargetSelectionPolicy.isSelectable(
            localPlatform: .iPhone,
            remotePlatform: .appleWatch,
            hasDirectMultipeer: false
        ) == true)
        #expect(PlaybackTargetSelectionPolicy.isSelectable(
            localPlatform: .mac,
            remotePlatform: .appleWatch,
            hasDirectMultipeer: false
        ) == false)
        #expect(PlaybackTargetSelectionPolicy.isSelectable(
            localPlatform: .appleWatch,
            remotePlatform: .mac,
            hasDirectMultipeer: false
        ) == false)
        #expect(PlaybackTargetSelectionPolicy.isSelectable(
            localPlatform: .mac,
            remotePlatform: .iPhone,
            hasDirectMultipeer: true
        ) == true)
    }

    @Test func iPadIsDistinctFromIPhoneAndUsesMultipeerSync() {
        #expect(SyncPlatformKind(platformName: "iPad") == .iPad)
        #expect(SyncTransportAvailabilityPolicy.canUseMultipeer(.iPad) == true)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .iPad, remote: .mac) == true)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .iPad, remote: .iPhone) == true)
        #expect(SyncTransportAvailabilityPolicy.canUseWatchConnectivity(local: .iPad, remote: .appleWatch) == false)

        let target = PlaybackTargetDevice(id: "ipad", name: "Justin's iPad", platform: "iPad", isLocal: true)
        #expect(target.displayName == "This iPad")
        #expect(target.iconName == "ipad")
    }

    @Test func macCanDisplayRelayedWatchPlaybackWithoutWatchControlTarget() throws {
        let now = Date()
        let watchSession = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 42,
            updatedAt: now,
            updatedByDeviceID: "watch"
        )

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: watchSession,
            deviceName: "Justin's Watch",
            platform: "Apple Watch",
            now: now.addingTimeInterval(3)
        ))
        let visibility = PlaybackDisplaySourcePolicy.visibility(
            hasLocalSong: false,
            localIsPlaying: false,
            hasRemotePlayback: snapshot.song != nil,
            hasActiveSharedPlayback: true,
            remoteQueueMatchesLocal: false
        )

        #expect(PlaybackTargetSelectionPolicy.isSelectable(
            localPlatform: .mac,
            remotePlatform: .appleWatch,
            hasDirectMultipeer: false
        ) == false)
        #expect(snapshot.platform == "Apple Watch")
        #expect(snapshot.deviceName == "Justin's Watch")
        #expect(snapshot.isPlaying == true)
        #expect(snapshot.currentTime == 45)
        #expect(visibility.showsRemote == true)
    }

    @Test func multipeerSendFailuresRestartOnlyWhenSessionHadPeers() {
        #expect(SyncTransportFailurePolicy.shouldRestartMultipeerDiscoveryAfterSendFailure(hasConnectedPeers: true) == true)
        #expect(SyncTransportFailurePolicy.shouldRestartMultipeerDiscoveryAfterSendFailure(hasConnectedPeers: false) == false)
    }

    @Test func manualNearbySearchIsAvailableForSyncOrCredentialSync() {
        #expect(SyncManualSearchPolicy.shouldSearch(syncModeEnabled: true, credentialSyncEnabled: false) == true)
        #expect(SyncManualSearchPolicy.shouldSearch(syncModeEnabled: false, credentialSyncEnabled: true) == true)
        #expect(SyncManualSearchPolicy.shouldSearch(syncModeEnabled: false, credentialSyncEnabled: false) == false)
    }

    @Test func manualResyncRebroadcastsPlaybackFromCurrentOutputOrBridge() {
        #expect(SyncStateRefreshPublicationPolicy.shouldRebroadcastSharedPlayback(
            sharedOutputDeviceID: "mac",
            localDeviceID: "mac"
        ) == true)
        #expect(SyncStateRefreshPublicationPolicy.shouldRebroadcastSharedPlayback(
            sharedOutputDeviceID: "watch",
            localDeviceID: "iphone"
        ) == true)
        #expect(SyncStateRefreshPublicationPolicy.shouldRebroadcastSharedPlayback(
            sharedOutputDeviceID: nil,
            localDeviceID: "iphone"
        ) == false)
    }

    @Test func supportedSyncGraphKeepsWatchIndependentWithIPhoneBridgeToMac() {
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .appleWatch, remote: .iPhone) == true)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .iPhone, remote: .appleWatch) == true)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .iPhone, remote: .mac) == true)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .mac, remote: .iPhone) == true)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .appleWatch, remote: .mac) == false)
        #expect(SyncTransportAvailabilityPolicy.canDirectlyDiscover(local: .mac, remote: .appleWatch) == false)
        #expect(SyncBridgeRelayPolicy.shouldRelay(
            kind: .playbackSession,
            receivedVia: .watchConnectivity,
            localPlatform: .iPhone,
            hasDestinationTransport: true
        ) == true)
    }

    @Test func watchConnectivityBootstrapsOnlyAfterCleanActivation() {
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapSync(activationSucceeded: true, hasError: false) == true)
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapSync(activationSucceeded: false, hasError: false) == false)
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapSync(activationSucceeded: true, hasError: true) == false)
    }

    @Test func watchConnectivityActivationStartsOnlyFromNotActivatedState() {
        #expect(WatchConnectivityActivationPolicy.shouldStartActivation(
            isSupported: true,
            isNotActivated: true,
            activationInProgress: false
        ) == true)
        #expect(WatchConnectivityActivationPolicy.shouldStartActivation(
            isSupported: true,
            isNotActivated: false,
            activationInProgress: false
        ) == false)
        #expect(WatchConnectivityActivationPolicy.shouldStartActivation(
            isSupported: false,
            isNotActivated: true,
            activationInProgress: false
        ) == false)
        #expect(WatchConnectivityActivationPolicy.shouldStartActivation(
            isSupported: true,
            isNotActivated: true,
            activationInProgress: true
        ) == false)
    }

    @Test func alreadyActivatedWatchConnectivitySessionBootstrapsOnceWhenConfigured() {
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapConfiguredSession(
            isActivated: true,
            activationInProgress: false,
            hasBootstrapped: false
        ) == true)
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapConfiguredSession(
            isActivated: true,
            activationInProgress: false,
            hasBootstrapped: true
        ) == false)
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapConfiguredSession(
            isActivated: false,
            activationInProgress: false,
            hasBootstrapped: false
        ) == false)
        #expect(WatchConnectivityActivationPolicy.shouldBootstrapConfiguredSession(
            isActivated: true,
            activationInProgress: true,
            hasBootstrapped: false
        ) == false)
    }

    @Test func pairedWatchCanBeShownBeforeWRhythmHelloArrives() {
        #expect(WatchConnectivityCompanionPresencePolicy.shouldExposeCompanion(
            activationSucceeded: true,
            hasUsableCompanion: true,
            syncModeEnabled: true,
            credentialSyncEnabled: false,
            hasKnownWRhythmPeer: false
        ) == true)
        #expect(WatchConnectivityCompanionPresencePolicy.shouldExposeCompanion(
            activationSucceeded: true,
            hasUsableCompanion: true,
            syncModeEnabled: true,
            credentialSyncEnabled: false,
            hasKnownWRhythmPeer: true
        ) == false)
        #expect(WatchConnectivityCompanionPresencePolicy.shouldExposeCompanion(
            activationSucceeded: true,
            hasUsableCompanion: false,
            syncModeEnabled: true,
            credentialSyncEnabled: false,
            hasKnownWRhythmPeer: false
        ) == false)
        #expect(WatchConnectivityCompanionPresencePolicy.shouldExposeCompanion(
            activationSucceeded: false,
            hasUsableCompanion: true,
            syncModeEnabled: true,
            credentialSyncEnabled: false,
            hasKnownWRhythmPeer: false
        ) == false)
    }

    @Test func watchConnectivityPlaceholderRoutesCommandsAsUntargetedDirectPeerCommands() {
        #expect(PlaybackControlTargetPolicy.envelopeTargetDeviceID(for: PlaybackControlTargetPolicy.watchConnectivityCompanionDeviceID) == nil)
        #expect(PlaybackControlTargetPolicy.envelopeTargetDeviceID(for: "real-watch-device-id") == "real-watch-device-id")
        #expect(PlaybackCommandReceivePolicy.shouldApplyNormalCommand(
            action: .pause,
            targetDeviceID: nil,
            localDeviceID: "watch"
        ) == true)
    }

    @Test func watchConnectivityQueuesDurablePayloadsAfterActivationWithoutReachability() {
        #expect(WatchConnectivityPayloadQueuePolicy.canQueueDurablePayload(activationSucceeded: true) == true)
        #expect(WatchConnectivityPayloadQueuePolicy.canQueueDurablePayload(activationSucceeded: false) == false)
    }

    @Test func credentialBootstrapRequestsCredentialsWhenLocalDeviceIsEmpty() {
        #expect(WatchConnectivityCredentialBootstrapPolicy.shouldRequestCredentialsOnBootstrap(
            credentialSyncEnabled: true,
            localHasCredentials: false
        ) == true)
        #expect(WatchConnectivityCredentialBootstrapPolicy.shouldRequestCredentialsOnBootstrap(
            credentialSyncEnabled: false,
            localHasCredentials: false
        ) == false)
        #expect(WatchConnectivityCredentialBootstrapPolicy.shouldRequestCredentialsOnBootstrap(
            credentialSyncEnabled: true,
            localHasCredentials: true
        ) == false)
    }

    @Test func standaloneWatchCredentialFlowDoesNotRequirePeerImportWhenCredentialsExist() {
        #expect(CredentialSyncBootstrapPolicy.shouldAuthorizeImportOnBootstrap(
            localCredentialSyncEnabled: true,
            localHasCredentials: true
        ) == false)
        #expect(WatchConnectivityCredentialBootstrapPolicy.shouldRequestCredentialsOnBootstrap(
            credentialSyncEnabled: true,
            localHasCredentials: true
        ) == false)
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentials(
            localCredentialSyncEnabled: true,
            localHasCredentials: true
        ) == true)
    }

    @Test func standaloneWatchCanDeclineCredentialSyncAndStillUseManualCredentials() {
        #expect(CredentialSyncBootstrapPolicy.shouldAuthorizeImportOnBootstrap(
            localCredentialSyncEnabled: false,
            localHasCredentials: false
        ) == false)
        #expect(WatchConnectivityCredentialBootstrapPolicy.shouldRequestCredentialsOnBootstrap(
            credentialSyncEnabled: false,
            localHasCredentials: false
        ) == false)
        #expect(CredentialSyncBootstrapPolicy.shouldOfferCredentials(
            localCredentialSyncEnabled: false,
            localHasCredentials: true
        ) == false)
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

    @Test func activePrebufferCompletionsPublishEvenAfterQueueWindowMoves() {
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
        ) == true)
    }

    @Test func stalePrebufferCompletionsDoNotPublish() {
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

    @Test func completedPrebufferStillPublishesWhenTrackMovedOutOfQueueBeforeCompletion() {
        #expect(PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
            key: "song-1|flac",
            desiredKeys: ["song-2|flac", "song-3|flac"],
            activeTaskKeys: ["song-1|flac"],
            capturedToken: "token-1",
            activeToken: "token-1"
        ) == true)

        #expect(PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
            key: "song-1|flac",
            desiredKeys: ["song-2|flac", "song-3|flac"],
            activeTaskKeys: ["song-1|flac"],
            capturedToken: "token-1",
            activeToken: "token-1"
        ) == true)
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

    @Test func disconnectedPlayingOutputProducesPausedConnectivitySession() throws {
        let now = Date()
        let song = makeSong(id: "song-1")
        let playingSession = makeSession(
            songs: [song],
            outputDeviceID: "watch",
            isPlaying: true,
            position: 20,
            revision: 7,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "watch"
        )

        let pausedSession = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: playingSession,
            localDeviceID: "iphone",
            disconnectedAt: now
        ))

        #expect(pausedSession.id == playingSession.id)
        #expect(pausedSession.revision == playingSession.revision)
        #expect(pausedSession.outputDeviceID == "watch")
        #expect(pausedSession.updatedByDeviceID == "iphone")
        #expect(pausedSession.isPlaying == false)
        #expect(pausedSession.position == 25)
        #expect(pausedSession.currentSong?.id == song.id)
    }

    @Test func disconnectedNonOutputOrAlreadyPausedSessionDoesNotCreateConnectivityPause() {
        let now = Date()
        let playingElsewhere = makeSession(
            outputDeviceID: "mac",
            isPlaying: true,
            updatedAt: now,
            updatedByDeviceID: "mac"
        )
        let alreadyPaused = makeSession(
            outputDeviceID: "watch",
            isPlaying: false,
            updatedAt: now,
            updatedByDeviceID: "watch"
        )

        #expect(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: playingElsewhere,
            localDeviceID: "iphone",
            disconnectedAt: now
        ) == nil)
        #expect(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: alreadyPaused,
            localDeviceID: "iphone",
            disconnectedAt: now
        ) == nil)
    }

    @Test func activeLocalPlaybackDoesNotCreateConnectivityPauseForDisconnectedRemoteOutput() {
        let now = Date()
        let remotePlayingBeforeDisconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 20,
            revision: 7,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "watch"
        )

        #expect(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: remotePlayingBeforeDisconnect,
            localDeviceID: "ipad",
            localIsPlaying: true,
            disconnectedAt: now
        ) == nil)
    }

    @Test func reconnectedOwnerPlayingSessionOverwritesConnectivityPauseWhenNewer() throws {
        let now = Date()
        let ownerPlayingBeforeDisconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 20,
            revision: 7,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "watch"
        )
        let connectivityPause = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: ownerPlayingBeforeDisconnect,
            localDeviceID: "iphone",
            disconnectedAt: now
        ))
        let ownerStillPlayingAfterReconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 40,
            revision: 7,
            updatedAt: now.addingTimeInterval(1),
            updatedByDeviceID: "watch"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(ownerStillPlayingAfterReconnect, over: connectivityPause, now: now.addingTimeInterval(1)) == true)
    }

    @Test(arguments: ["iphone", "mac"])
    func passiveObserversPauseDisconnectedPlayingOwner(observerDeviceID: String) throws {
        let now = Date()
        let ownerPlayingBeforeDisconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 50,
            revision: 12,
            updatedAt: now.addingTimeInterval(-10),
            updatedByDeviceID: "watch"
        )

        let connectivityPause = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: ownerPlayingBeforeDisconnect,
            localDeviceID: observerDeviceID,
            disconnectedAt: now
        ))

        #expect(connectivityPause.id == ownerPlayingBeforeDisconnect.id)
        #expect(connectivityPause.outputDeviceID == "watch")
        #expect(connectivityPause.updatedByDeviceID == observerDeviceID)
        #expect(connectivityPause.isPlaying == false)
        #expect(connectivityPause.position == 60)
    }

    @Test func simultaneousPassiveConnectivityPausesResolveDeterministically() throws {
        let now = Date()
        let ownerPlayingBeforeDisconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 50,
            revision: 12,
            updatedAt: now.addingTimeInterval(-10),
            updatedByDeviceID: "watch"
        )
        let iphonePause = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: ownerPlayingBeforeDisconnect,
            localDeviceID: "iphone",
            disconnectedAt: now
        ))
        let macPause = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: ownerPlayingBeforeDisconnect,
            localDeviceID: "mac",
            disconnectedAt: now
        ))

        #expect(PlaybackSessionSyncPolicy.shouldApply(macPause, over: iphonePause, now: now) == true)
        #expect(PlaybackSessionSyncPolicy.shouldApply(iphonePause, over: macPause, now: now) == false)
    }

    @Test(arguments: ["iphone", "mac"])
    func reconnectedOwnerStillPlayingOverwritesPassivePauseOnEachObserver(observerDeviceID: String) throws {
        let now = Date()
        let ownerPlayingBeforeDisconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 20,
            revision: 7,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "watch"
        )
        let connectivityPause = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: ownerPlayingBeforeDisconnect,
            localDeviceID: observerDeviceID,
            disconnectedAt: now
        ))
        let ownerStillPlayingAfterReconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 40,
            revision: 7,
            updatedAt: now.addingTimeInterval(1),
            updatedByDeviceID: "watch"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(ownerStillPlayingAfterReconnect, over: connectivityPause, now: now.addingTimeInterval(1)) == true)
    }

    @Test func connectivityPauseRejectsOlderInFlightPlayingSessionAfterDisconnect() throws {
        let now = Date()
        let ownerPlayingBeforeDisconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 20,
            revision: 7,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "watch"
        )
        let connectivityPause = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: ownerPlayingBeforeDisconnect,
            localDeviceID: "iphone",
            disconnectedAt: now
        ))
        let delayedPreDisconnectPlayingSession = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 24,
            revision: 7,
            updatedAt: now.addingTimeInterval(-1),
            updatedByDeviceID: "watch"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(delayedPreDisconnectPlayingSession, over: connectivityPause, now: now) == false)
    }

    @Test func localActivePlaybackCanCompeteWithConnectivityPauseWhenNewer() throws {
        let now = Date()
        let ownerPlayingBeforeDisconnect = makeSession(
            outputDeviceID: "watch",
            isPlaying: true,
            position: 20,
            revision: 7,
            updatedAt: now.addingTimeInterval(-5),
            updatedByDeviceID: "watch"
        )
        let connectivityPause = try #require(ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
            disconnectedDeviceID: "watch",
            currentSession: ownerPlayingBeforeDisconnect,
            localDeviceID: "iphone",
            disconnectedAt: now
        ))
        let localPlayingSession = makeSession(
            id: "mac-session",
            outputDeviceID: "mac",
            isPlaying: true,
            position: 3,
            revision: 1,
            updatedAt: now.addingTimeInterval(1),
            updatedByDeviceID: "mac"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(localPlayingSession, over: connectivityPause, now: now.addingTimeInterval(1)) == true)
    }

    @Test func activeLocalPlaybackCanWinOverReconnectedOwnerWhenNewer() {
        let now = Date()
        let reconnectedOwnerStillPlaying = makeSession(
            id: "watch-session",
            outputDeviceID: "watch",
            isPlaying: true,
            position: 40,
            revision: 7,
            updatedAt: now,
            updatedByDeviceID: "watch"
        )
        let localPlaybackStartedWhileDisconnected = makeSession(
            id: "mac-session",
            outputDeviceID: "mac",
            isPlaying: true,
            position: 3,
            revision: 1,
            updatedAt: now.addingTimeInterval(1),
            updatedByDeviceID: "mac"
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(localPlaybackStartedWhileDisconnected, over: reconnectedOwnerStillPlaying, now: now.addingTimeInterval(1)) == true)
        #expect(PlaybackSessionSyncPolicy.shouldApply(reconnectedOwnerStillPlaying, over: localPlaybackStartedWhileDisconnected, now: now.addingTimeInterval(1)) == false)
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

    @Test func prebufferRetryJitterKeepsDelayBoundedAndDeterministic() {
        let first = PrebufferRetryPolicy.retryDelay(forAttempt: 2, key: "song-a")
        let repeated = PrebufferRetryPolicy.retryDelay(forAttempt: 2, key: "song-a")
        let other = PrebufferRetryPolicy.retryDelay(forAttempt: 2, key: "song-b")

        #expect(first == repeated)
        #expect(first >= 3.2)
        #expect(first <= 4.8)
        #expect(other >= 3.2)
        #expect(other <= 4.8)
    }

    @Test func prebufferRetryStopsAfterBoundedAttempts() {
        #expect(PrebufferRetryPolicy.shouldRetry(afterAttempt: 0))
        #expect(PrebufferRetryPolicy.shouldRetry(afterAttempt: PrebufferRetryPolicy.maxRetryAttempts - 1))
        #expect(PrebufferRetryPolicy.shouldRetry(afterAttempt: PrebufferRetryPolicy.maxRetryAttempts) == false)
    }

    @Test func prebufferRetryCooldownStartsAfterRepeatedRecentFailures() {
        let now = Date(timeIntervalSince1970: 10_000)
        let recentFailures = [
            now.addingTimeInterval(-1),
            now.addingTimeInterval(-5),
            now.addingTimeInterval(-12),
            now.addingTimeInterval(-30),
        ]
        let spreadOutFailures = [
            now.addingTimeInterval(-1),
            now.addingTimeInterval(-5),
            now.addingTimeInterval(-70),
            now.addingTimeInterval(-100),
        ]

        #expect(PrebufferRetryPolicy.shouldEnterCooldown(recentFailureDates: recentFailures, now: now))
        #expect(PrebufferRetryPolicy.shouldEnterCooldown(recentFailureDates: spreadOutFailures, now: now) == false)
    }

    @Test func logRedactorRemovesSubsonicCredentialsButKeepsUsefulQueryContext() throws {
        let url = try #require(URL(string: "https://example.test/rest/stream.view?u=admin&t=token&s=salt&c=WRhythm&v=1.16.1&id=song-1&maxBitRate=192&format=mp3"))
        let redacted = WRhythmLogRedactor.redacted(url)

        #expect(redacted.contains("u=%3Credacted%3E"))
        #expect(redacted.contains("t=%3Credacted%3E"))
        #expect(redacted.contains("s=%3Credacted%3E"))
        #expect(redacted.contains("id=song-1"))
        #expect(redacted.contains("maxBitRate=192"))
        #expect(redacted.contains("format=mp3"))
        #expect(redacted.contains("admin") == false)
        #expect(redacted.contains("token") == false)
        #expect(redacted.contains("salt") == false)
    }

    @Test func logRedactorScrubsSensitiveURLsInsideErrorText() {
        let raw = "Error url=https://example.test/rest/scrobble.view?u=admin&t=token&s=salt&id=song-1 failed"
        let redacted = WRhythmLogRedactor.redactSensitiveURLData(in: raw)

        #expect(redacted.contains("u=<redacted>"))
        #expect(redacted.contains("t=<redacted>"))
        #expect(redacted.contains("s=<redacted>"))
        #expect(redacted.contains("id=song-1"))
        #expect(redacted.contains("admin") == false)
        #expect(redacted.contains("token") == false)
        #expect(redacted.contains("salt") == false)
    }

    @Test func prebufferSchedulingSkipsRetryExhaustedKeys() {
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: ["a", "b", "c"],
            activeKeys: [],
            preparedKeys: [],
            failedKeys: ["a"],
            maxConcurrentTasks: 2
        )

        #expect(scheduled == ["b", "c"])
    }

    @Test func prebufferSchedulingUsesConfigurableForwardWindow() {
        let queueKeys = ["a", "b", "c", "d", "e", "f"]

        #expect(PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 1,
            aheadCount: 2
        ) == ["c", "d"])
        #expect(PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 1,
            aheadCount: 4
        ) == ["c", "d", "e", "f"])
        #expect(PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 1,
            aheadCount: 0
        ).isEmpty)
    }

    @Test func prebufferSchedulingClampsStaleIndexAfterQueueShrinks() {
        let queueKeys = ["only-result"]

        #expect(PrebufferSchedulingPolicy.upcomingRange(
            queueCount: queueKeys.count,
            currentIndex: 19,
            aheadCount: 8
        ) == 1..<1)
        #expect(PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 19,
            aheadCount: 8
        ).isEmpty)
        #expect(PrebufferSchedulingPolicy.previousRange(
            queueCount: queueKeys.count,
            currentIndex: 19,
            keepCount: 8
        ) == 0..<1)
        #expect(PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: 19,
            keepCount: 8
        ) == ["only-result"])
    }

    @Test func prebufferSchedulingBackfillsPreviousKeysAfterCurrentAndUpcomingCandidates() {
        let queueKeys = ["a", "b", "c", "d", "e"]
        let previousKeys = PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: 3,
            keepCount: 2
        )
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 3,
            aheadCount: 1
        )
        let candidates = PrebufferSchedulingPolicy.orderedCandidateKeys(
            currentKey: queueKeys[3],
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )

        #expect(previousKeys == ["b", "c"])
        #expect(upcomingKeys == ["e"])
        #expect(candidates == ["d", "e", "b", "c"])
    }

    @Test func prebufferSchedulingRetainsAndSchedulesPreviousTracksAsBackfill() {
        let queueKeys = (0..<8).map { "song-\($0)" }
        let currentKey = queueKeys[4]
        let previousKeys = PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: 4,
            keepCount: 3
        )
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 4,
            aheadCount: 2
        )
        let desiredKeys = PrebufferSchedulingPolicy.desiredKeys(
            currentKey: currentKey,
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )
        let retainedKeys = desiredKeys.union(previousKeys)
        let candidates = PrebufferSchedulingPolicy.orderedCandidateKeys(
            currentKey: nil,
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: candidates,
            activeKeys: ["song-5"],
            preparedKeys: ["song-4", "song-6"],
            failedKeys: [],
            maxConcurrentTasks: 4
        )

        #expect(previousKeys == ["song-1", "song-2", "song-3"])
        #expect(retainedKeys == Set(["song-1", "song-2", "song-3", "song-4", "song-5", "song-6"]))
        #expect(candidates == ["song-5", "song-6", "song-1", "song-2", "song-3"])
        #expect(scheduled == ["song-1", "song-2", "song-3"])
    }

    @Test func prebufferSchedulingCanRetainCurrentWithoutSchedulingCurrentDownload() {
        let queueKeys = (0..<6).map { "song-\($0)" }
        let currentKey = queueKeys[2]
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 2,
            aheadCount: 2
        )
        let previousKeys = PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: 2,
            keepCount: 2
        )
        let retainedKeys = PrebufferSchedulingPolicy.desiredKeys(
            currentKey: currentKey,
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )
        let downloadCandidates = PrebufferSchedulingPolicy.orderedCandidateKeys(
            currentKey: nil,
            upcomingKeys: upcomingKeys,
            previousKeys: previousKeys
        )

        #expect(retainedKeys.contains(currentKey))
        #expect(downloadCandidates == ["song-3", "song-4", "song-0", "song-1"])
        #expect(downloadCandidates.contains(currentKey) == false)
    }

    @Test func prebufferCachePruningKeepsActiveTemporaryDownloads() {
        #expect(PrebufferCachePruningPolicy.shouldRemove(
            filename: "track.download",
            keepFilenames: []
        ) == false)
        #expect(PrebufferCachePruningPolicy.shouldRemove(
            filename: "track.mp3",
            keepFilenames: ["track.mp3"]
        ) == false)
        #expect(PrebufferCachePruningPolicy.shouldRemove(
            filename: "old.mp3",
            keepFilenames: ["track.mp3"]
        ))
    }

    @Test func prebufferCachePruningKeepsPreviousCurrentAndUpcomingFilenamesOnly() {
        let keepFilenames: Set<String> = [
            "previous.mp3",
            "current.mp3",
            "next-1.mp3",
            "next-2.mp3"
        ]

        #expect(PrebufferCachePruningPolicy.shouldRemove(filename: "previous.mp3", keepFilenames: keepFilenames) == false)
        #expect(PrebufferCachePruningPolicy.shouldRemove(filename: "current.mp3", keepFilenames: keepFilenames) == false)
        #expect(PrebufferCachePruningPolicy.shouldRemove(filename: "next-1.mp3", keepFilenames: keepFilenames) == false)
        #expect(PrebufferCachePruningPolicy.shouldRemove(filename: "outside-window.mp3", keepFilenames: keepFilenames) == true)
        #expect(PrebufferCachePruningPolicy.shouldRemove(filename: "outside-window.download", keepFilenames: keepFilenames) == false)
        #expect(PrebufferCachePruningPolicy.shouldRemove(filename: "prebufferManifest.v1.json", keepFilenames: keepFilenames) == false)
    }

    @Test func prebufferSchedulingCountsOnlyPreparedTracksAsReady() {
        #expect(PrebufferSchedulingPolicy.readyCount(
            upcomingKeys: ["a", "b", "c"],
            preparedKeys: ["a", "c"]
        ) == 2)
    }

    @Test func prebufferSchedulingKeepsCurrentQueueItemDesiredWhenSkippingIntoReadyTrack() {
        // Given
        let currentQueueKey = "song-2"
        let previousNowPlayingKey = "song-1"
        let upcomingKeys = ["song-3", "song-4"]

        // When
        let desiredKeys = PrebufferSchedulingPolicy.desiredKeys(
            currentKey: currentQueueKey,
            upcomingKeys: upcomingKeys
        )

        // Then
        #expect(desiredKeys.contains(currentQueueKey))
        #expect(desiredKeys.contains(previousNowPlayingKey) == false)
        #expect(desiredKeys == ["song-2", "song-3", "song-4"])
    }

    @Test func jumpingToCachedPreviousTrackStillSchedulesNewUpcomingWindow() {
        let queueKeys = (0..<10).map { "song-\($0)" }
        let currentIndex = 2
        let currentKey = queueKeys[currentIndex]
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: currentIndex,
            aheadCount: 4
        )
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: PrebufferSchedulingPolicy.orderedCandidateKeys(
                currentKey: currentKey,
                upcomingKeys: upcomingKeys
            ),
            activeKeys: [],
            preparedKeys: ["song-1", "song-2"],
            failedKeys: [],
            maxConcurrentTasks: 3
        )

        #expect(upcomingKeys == ["song-3", "song-4", "song-5", "song-6"])
        #expect(scheduled == ["song-3", "song-4", "song-5"])
    }

    @Test func prebufferSchedulingPrioritizesCurrentItemBeforeUpcomingItems() {
        // Given
        let candidates = PrebufferSchedulingPolicy.orderedCandidateKeys(
            currentKey: "song-2",
            upcomingKeys: ["song-2", "song-3", "song-4"]
        )

        // When
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: candidates,
            activeKeys: [],
            preparedKeys: [],
            failedKeys: [],
            maxConcurrentTasks: 2
        )

        // Then
        #expect(candidates == ["song-2", "song-3", "song-4"])
        #expect(scheduled == ["song-2", "song-3"])
    }

    @Test func prebufferSchedulingRecalculatesWindowsAfterJumpingBackward() {
        let queueKeys = (0..<12).map { "song-\($0)" }

        let previousKeys = PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: 2,
            keepCount: 4
        )
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 2,
            aheadCount: 5
        )
        let desiredKeys = PrebufferSchedulingPolicy.desiredKeys(
            currentKey: queueKeys[2],
            upcomingKeys: upcomingKeys
        )

        #expect(previousKeys == ["song-0", "song-1"])
        #expect(upcomingKeys == ["song-3", "song-4", "song-5", "song-6", "song-7"])
        #expect(desiredKeys == ["song-2", "song-3", "song-4", "song-5", "song-6", "song-7"])
        #expect(desiredKeys.contains("song-8") == false)
    }

    @Test func prebufferSchedulingRecalculatesWindowsAfterJumpingForward() {
        let queueKeys = (0..<12).map { "song-\($0)" }

        let previousKeys = PrebufferSchedulingPolicy.previousKeys(
            queueKeys: queueKeys,
            currentIndex: 8,
            keepCount: 3
        )
        let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
            queueKeys: queueKeys,
            currentIndex: 8,
            aheadCount: 5
        )
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: PrebufferSchedulingPolicy.orderedCandidateKeys(
                currentKey: queueKeys[8],
                upcomingKeys: upcomingKeys
            ),
            activeKeys: ["song-9"],
            preparedKeys: ["song-8"],
            failedKeys: [],
            maxConcurrentTasks: 3
        )

        #expect(previousKeys == ["song-5", "song-6", "song-7"])
        #expect(upcomingKeys == ["song-9", "song-10", "song-11"])
        #expect(scheduled == ["song-10", "song-11"])
    }

    @Test func prebufferSchedulingSkipsFailedPreparedAndActiveKeysToFillSlots() {
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: ["a", "b", "c", "d"],
            activeKeys: ["a"],
            preparedKeys: ["b"],
            failedKeys: ["c"],
            maxConcurrentTasks: 3
        )

        #expect(scheduled == ["d"])
    }

    @Test func clearingQueuePreventsStalePrebufferPublicationAndNewScheduling() {
        let desiredKeys = PrebufferSchedulingPolicy.desiredKeys(currentKey: nil, upcomingKeys: [])
        let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
            candidateKeys: [],
            activeKeys: ["old-current", "old-next"],
            preparedKeys: [],
            failedKeys: [],
            maxConcurrentTasks: 3
        )

        #expect(desiredKeys.isEmpty)
        #expect(scheduled.isEmpty)
        #expect(PrebufferPublicationPolicy.shouldPublishPreparedBuffer(
            key: "old-next",
            desiredKeys: desiredKeys,
            activeTaskKeys: [],
            capturedToken: "token-1",
            activeToken: "token-1"
        ) == false)
    }

    @Test func prebufferProgressPercentUsesActualReceivedBytes() {
        let progress = PrebufferProgressPolicy.normalizedProgress(receivedBytes: 800, expectedBytes: 1_000)

        #expect(progress == 0.8)
        #expect(PrebufferProgressPolicy.percent(for: progress) == 80)
    }

    @Test func prebufferProgressDoesNotReportZeroForNonzeroProgress() {
        let progress = PrebufferProgressPolicy.normalizedProgress(receivedBytes: 1, expectedBytes: 1_000)

        #expect(PrebufferProgressPolicy.percent(for: progress) == 1)
    }

    @Test func prebufferProgressIgnoresUnknownContentLength() {
        #expect(PrebufferProgressPolicy.normalizedProgress(receivedBytes: 500, expectedBytes: -1) == nil)
        #expect(PrebufferProgressPolicy.percent(for: nil) == nil)
    }

    @Test func prebufferProgressSummaryShowsActiveDownloadPercent() {
        let summary = PrebufferProgressPolicy.statusSummary(
            previousReadyCount: 2,
            nextReadyCount: 5,
            activeCount: 1,
            activePercent: 80,
            playerIsBuffering: false,
            playerBufferPercent: nil
        )

        #expect(summary == "2 prev available • 5 next available • 1 downloading 80%")
    }

    @Test func prebufferProgressSummaryUsesBufferingOnlyForCurrentPlayback() {
        let summary = PrebufferProgressPolicy.statusSummary(
            previousReadyCount: 0,
            nextReadyCount: 0,
            activeCount: 0,
            activePercent: nil,
            playerIsBuffering: true,
            playerBufferPercent: 42
        )

        #expect(summary == "buffering 42%")
    }

    @Test func prebufferProgressSummaryKeepsCurrentBufferingSeparateFromDownloads() {
        let summary = PrebufferProgressPolicy.statusSummary(
            previousReadyCount: 1,
            nextReadyCount: 1,
            activeCount: 1,
            activePercent: 35,
            playerIsBuffering: true,
            playerBufferPercent: 12
        )

        #expect(summary == "1 prev available • 1 next available • 1 downloading 35% • buffering 12%")
    }

    @Test func prebufferProgressBuildsDownloadingRowsForActiveQueueItems() {
        let songs = [makeSong(id: "previous"), makeSong(id: "current"), makeSong(id: "next")]
        let statuses = PrebufferProgressPolicy.downloadStatuses(
            for: songs,
            activeKeys: ["current-key", "next-key"],
            progressByKey: [
                "current-key": 0.42,
                "next-key": 0.003
            ],
            keyForSong: { "\($0.id)-key" }
        )

        #expect(statuses.map { $0.song.id } == ["current", "next"])
        #expect(statuses.map(\.progressPercent) == [42, 1])
    }

    @Test func prebufferProgressRowsIncludePreviousAndUpcomingDownloadsOnce() {
        let songs = [
            makeSong(id: "previous"),
            makeSong(id: "next"),
            makeSong(id: "next")
        ]
        let statuses = PrebufferProgressPolicy.downloadStatuses(
            for: songs,
            activeKeys: ["previous-key", "current-key", "next-key"],
            progressByKey: [
                "previous-key": 0.2,
                "current-key": 0.5,
                "next-key": 0.8
            ],
            keyForSong: { "\($0.id)-key" }
        )

        #expect(statuses.map { $0.song.id } == ["previous", "next"])
        #expect(statuses.map(\.progressPercent) == [20, 80])
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

    @Test @MainActor func syncDelegateEventSubmitterWaitsForLateReentrantSubmissions() async {
        let submitter = SyncDelegateEventSubmitter(label: "WRhythm.Tests.SyncDelegateSubmitterLateReentrant")
        var values: [Int] = []
        let reentrantValue = 1_000

        for value in 0..<220 {
            submitter.enqueue {
                values.append(value)
                if value == 219 {
                    submitter.enqueue {
                        values.append(reentrantValue)
                    }
                }
            }
        }

        await submitter.waitForIdle()

        #expect(values == Array(0..<220) + [reentrantValue])
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

    @Test(arguments: [
        ("iphone", "mac"),
        ("mac", "iphone")
    ])
    func pausedOwnerSessionAppliesAndDisplaysPausedSymmetrically(ownerDeviceID: String, observerDeviceID: String) throws {
        let now = Date()
        let playingSession = makeSession(
            id: "\(ownerDeviceID)-session",
            outputDeviceID: ownerDeviceID,
            isPlaying: true,
            position: 30,
            revision: 8,
            updatedAt: now.addingTimeInterval(-1),
            updatedByDeviceID: ownerDeviceID
        )
        let pausedSession = makeSession(
            id: "\(ownerDeviceID)-session",
            outputDeviceID: ownerDeviceID,
            isPlaying: false,
            position: 31,
            revision: 9,
            updatedAt: now,
            updatedByDeviceID: ownerDeviceID
        )

        #expect(PlaybackSessionSyncPolicy.shouldApply(pausedSession, over: playingSession, now: now) == true)

        let snapshot = try #require(PlaybackSessionSnapshotPolicy.snapshot(
            from: pausedSession,
            deviceName: observerDeviceID,
            platform: observerDeviceID,
            now: now.addingTimeInterval(5)
        ))

        #expect(snapshot.id == ownerDeviceID)
        #expect(snapshot.isPlaying == false)
        #expect(snapshot.currentTime == 31)
    }

    @Test(arguments: [
        ("iphone", "mac"),
        ("mac", "iphone")
    ])
    func stalePlayingTelemetryCannotOverrideNewerPausedOwnerSession(ownerDeviceID: String, observerDeviceID: String) {
        let now = Date()
        let pausedSession = makeSession(
            id: "\(ownerDeviceID)-session",
            outputDeviceID: ownerDeviceID,
            isPlaying: false,
            position: 42,
            revision: 9,
            updatedAt: now,
            updatedByDeviceID: ownerDeviceID
        )
        let delayedPlayingSession = makeSession(
            id: "\(ownerDeviceID)-session",
            outputDeviceID: ownerDeviceID,
            isPlaying: true,
            position: 41,
            revision: 8,
            updatedAt: now.addingTimeInterval(0.5),
            updatedByDeviceID: ownerDeviceID
        )

        #expect(observerDeviceID != ownerDeviceID)
        #expect(PlaybackSessionSyncPolicy.shouldApply(delayedPlayingSession, over: pausedSession, now: now.addingTimeInterval(0.5)) == false)
    }

    @Test func credentialImportRejectsPayloadIssuedBeforeLocalLogout() {
        let logoutTime = Date()
        let staleCredentialIssuedAt = logoutTime.addingTimeInterval(-1)

        #expect(CredentialSyncPolicy.shouldImport(
            incomingIssuedAt: staleCredentialIssuedAt,
            localClearedAt: logoutTime,
            credentialSyncAuthorizedAt: .distantPast
        ) == false)
    }

    @Test func credentialImportAcceptsPayloadIssuedAfterLocalLogout() {
        let logoutTime = Date()
        let freshCredentialIssuedAt = logoutTime.addingTimeInterval(1)

        #expect(CredentialSyncPolicy.shouldImport(
            incomingIssuedAt: freshCredentialIssuedAt,
            localClearedAt: logoutTime,
            credentialSyncAuthorizedAt: .distantPast
        ) == true)
    }

    @Test func credentialImportAcceptsOlderPayloadAfterCredentialSyncOptIn() {
        let logoutTime = Date()
        let olderCredentialIssuedAt = logoutTime.addingTimeInterval(-1)
        let credentialSyncAuthorizedAt = logoutTime.addingTimeInterval(1)

        #expect(CredentialSyncPolicy.shouldImport(
            incomingIssuedAt: olderCredentialIssuedAt,
            localClearedAt: logoutTime,
            credentialSyncAuthorizedAt: credentialSyncAuthorizedAt
        ) == true)
    }

    @Test func credentialImportRejectsOlderPayloadWhenSyncOptInPredatesLogout() {
        let logoutTime = Date()
        let olderCredentialIssuedAt = logoutTime.addingTimeInterval(-1)
        let oldCredentialSyncAuthorizedAt = logoutTime.addingTimeInterval(-2)

        #expect(CredentialSyncPolicy.shouldImport(
            incomingIssuedAt: olderCredentialIssuedAt,
            localClearedAt: logoutTime,
            credentialSyncAuthorizedAt: oldCredentialSyncAuthorizedAt
        ) == false)
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

    @Test func watchInfoPlistDeclaresIndependentAppAndSyncDiscovery() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WRhythm-Watch-App-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])

        #expect(plist["WKRunsIndependentlyOfCompanionApp"] as? Bool == true)
        #expect(plist["WKCompanionAppBundleIdentifier"] as? String == "com.restivollc.wrhythm")

        let bonjourServices = try #require(plist["NSBonjourServices"] as? [String])
        #expect(bonjourServices.contains("_wrhythm-sync._tcp"))

        let localNetworkUsageDescription = try #require(plist["NSLocalNetworkUsageDescription"] as? String)
        #expect(localNetworkUsageDescription.isEmpty == false)
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
    @Test func openSubsonicExtensionsDetectsSonicSimilarity() throws {
        let payload = """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "openSubsonicExtensions": [
              { "name": "template", "versions": [1] },
              { "name": "sonicSimilarity", "versions": [1] }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(
            SubsonicResponse<OpenSubsonicExtensionsResponse>.self,
            from: Data(payload.utf8)
        )

        let extensions = try #require(response.subsonicResponse.openSubsonicExtensions)
        #expect(OpenSubsonicExtensionPolicy.supportsSonicSimilarity(extensions))
    }

    @MainActor
    @Test func sonicMatchesResponseDecodesTopLevelSonicMatchEntries() throws {
        let payload = """
        {
          "status": "ok",
          "version": "1.16.1",
          "sonicMatch": [
            {
              "entry": {
                "id": "song-1",
                "title": "First Track",
                "album": "Album",
                "albumId": "album-1",
                "artist": "Artist",
                "artistId": "artist-1",
                "duration": 180
              },
              "similarity": 0.95
            },
            {
              "entry": {
                "id": "song-2",
                "title": "Second Track",
                "album": "Album",
                "albumId": "album-1",
                "artist": "Artist",
                "artistId": "artist-1",
                "duration": 181
              },
              "similarity": 0.82
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(SonicMatchesResponse.self, from: Data(payload.utf8))

        #expect(response.songs.map(\.id) == ["song-1", "song-2"])
    }

    @MainActor
    @Test func audioMuseAlchemyProbeTreatsUnauthorizedAsEndpointPresent() {
        #expect(AudioMuseAlchemySupportPolicy.endpointExists(statusCode: 200))
        #expect(AudioMuseAlchemySupportPolicy.endpointExists(statusCode: 401))
        #expect(!AudioMuseAlchemySupportPolicy.endpointExists(statusCode: 404))
        #expect(!AudioMuseAlchemySupportPolicy.endpointExists(statusCode: 500))
    }

    @MainActor
    @Test func audioMuseAlchemyResponseMapsResultsToPlayableSongs() throws {
        let payload = """
        {
          "results": [
            {
              "item_id": "song-1",
              "title": "Alchemy Track",
              "author": "AudioMuse Artist"
            },
            {
              "id": "song-2",
              "name": "Fallback Name",
              "artist": "Fallback Artist",
              "album": "Fallback Album"
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(AudioMuseAlchemyResponse.self, from: Data(payload.utf8))

        #expect(response.songs.map(\.id) == ["song-1", "song-2"])
        #expect(response.songs.map(\.title) == ["Alchemy Track", "Fallback Name"])
        #expect(response.songs.map(\.artist) == ["AudioMuse Artist", "Fallback Artist"])
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

    @Test func availableTracksSummaryCoversEmptyReadyDownloadingAndMixedStates() {
        #expect(AvailableTracksPresentationPolicy.summary(
            previousReadyCount: 0,
            nextReadyCount: 0,
            downloadingCount: 0
        ) == "No tracks ready")
        #expect(AvailableTracksPresentationPolicy.summary(
            previousReadyCount: 3,
            nextReadyCount: 0,
            downloadingCount: 0
        ) == "3 prev avail | 0 next avail")
        #expect(AvailableTracksPresentationPolicy.summary(
            previousReadyCount: 0,
            nextReadyCount: 4,
            downloadingCount: 2
        ) == "0 prev avail | 4 next avail | 2 downloading")
        #expect(AvailableTracksPresentationPolicy.summary(
            previousReadyCount: 7,
            nextReadyCount: 1,
            downloadingCount: 1
        ) == "7 prev avail | 1 next avail | 1 downloading")
    }

    @Test func queuePresentationProtectsCurrentTrackAndRejectsInvalidIndexes() {
        #expect(QueuePresentationPolicy.canRemove(index: 0, currentIndex: 1, queueCount: 3) == true)
        #expect(QueuePresentationPolicy.canRemove(index: 1, currentIndex: 1, queueCount: 3) == false)
        #expect(QueuePresentationPolicy.canRemove(index: -1, currentIndex: 1, queueCount: 3) == false)
        #expect(QueuePresentationPolicy.canRemove(index: 3, currentIndex: 1, queueCount: 3) == false)
    }

    @Test func queuePresentationUsesSharedMutationsOnlyWhenSharedSessionExists() {
        #expect(QueuePresentationPolicy.mutationTarget(hasSharedSession: true) == .shared)
        #expect(QueuePresentationPolicy.mutationTarget(hasSharedSession: false) == .local)
        #expect(QueuePresentationPolicy.sectionTitle(hasSharedSession: true, remoteQueueMatchesLocal: false, localTitle: "This Device Queue") == "Shared Queue")
        #expect(QueuePresentationPolicy.sectionTitle(hasSharedSession: false, remoteQueueMatchesLocal: true, localTitle: "This Device Queue") == "Shared Queue")
        #expect(QueuePresentationPolicy.sectionTitle(hasSharedSession: false, remoteQueueMatchesLocal: false, localTitle: "This Device Queue") == "This Device Queue")
    }

    @Test func queuePresentationSummaryClampsDisplayedIndex() {
        #expect(QueuePresentationPolicy.summary(queueCount: 0, currentIndex: 10) == "Nothing queued")
        #expect(QueuePresentationPolicy.summary(queueCount: 5, currentIndex: -2) == "Track 1 of 5")
        #expect(QueuePresentationPolicy.summary(queueCount: 5, currentIndex: 20) == "Track 5 of 5")
        #expect(QueuePresentationPolicy.summary(queueCount: 5, currentIndex: 2) == "Track 3 of 5")
    }

    @Test func prebufferAheadSettingAllowsLargeValuesAndClampsOnlyAtBounds() {
        #expect(PrebufferSettingsPolicy.sanitizeAheadCount(-10) == 1)
        #expect(PrebufferSettingsPolicy.sanitizeAheadCount(1) == 1)
        #expect(PrebufferSettingsPolicy.sanitizeAheadCount(20) == 20)
        #expect(PrebufferSettingsPolicy.sanitizeAheadCount(75) == 75)
        #expect(PrebufferSettingsPolicy.sanitizeAheadCount(100) == 100)
        #expect(PrebufferSettingsPolicy.sanitizeAheadCount(101) == 100)
    }

    @Test func previousPrebufferSettingAllowsLargeValuesAndZero() {
        #expect(PrebufferSettingsPolicy.sanitizePreviousCount(-1) == 0)
        #expect(PrebufferSettingsPolicy.sanitizePreviousCount(0) == 0)
        #expect(PrebufferSettingsPolicy.sanitizePreviousCount(20) == 20)
        #expect(PrebufferSettingsPolicy.sanitizePreviousCount(80) == 80)
        #expect(PrebufferSettingsPolicy.sanitizePreviousCount(100) == 100)
        #expect(PrebufferSettingsPolicy.sanitizePreviousCount(120) == 100)
    }

    @Test func concurrentDownloadSliderRoundTripsUnlimitedSentinel() {
        #expect(ConcurrentDownloadSettingsPolicy.sliderValue(for: 1) == 1)
        #expect(ConcurrentDownloadSettingsPolicy.sliderValue(for: 8) == 8)
        #expect(ConcurrentDownloadSettingsPolicy.sliderValue(for: 999) == 17)
        #expect(ConcurrentDownloadSettingsPolicy.maxConcurrentDownloads(forSliderValue: 1) == 1)
        #expect(ConcurrentDownloadSettingsPolicy.maxConcurrentDownloads(forSliderValue: 16) == 16)
        #expect(ConcurrentDownloadSettingsPolicy.maxConcurrentDownloads(forSliderValue: 17) == 999)
        #expect(ConcurrentDownloadSettingsPolicy.maxConcurrentDownloads(forSliderValue: 18) == 999)
    }

    @Test func downloadQualitySettingsRoundTripOriginalAndLossyValues() {
        for quality in AudioQuality.allCases {
            #expect(AudioQuality.savedQuality(from: quality.rawValue) == quality)
        }

        #expect(AudioQuality.allCases.contains(.original))
        #expect(AudioQuality.savedQuality(from: 0) == .original)
        #expect(AudioQuality.savedQuality(from: 320) == .max)
        #expect(AudioQuality.savedQuality(from: 999) == .medium)
    }

    @Test func playlistGenerationTopsUpShortSameArtistResultsToRequestedCount() {
        let source = makeSong(id: "cryoshell-source", title: "Creeping in My Soul", artist: "Cryoshell")
        let similarSongs = (0..<10).map { makeSong(id: "cryoshell-\($0)", title: "Cryoshell \($0)", artist: "Cryoshell") }
        let fallbackSongs = (0..<150).map { makeSong(id: "fallback-\($0)", title: "Fallback \($0)", artist: "Mixed") }

        let queue = PlaylistGenerationPolicy.queue(
            sourceSong: source,
            primarySongs: similarSongs,
            fallbackSongs: fallbackSongs,
            requestedCount: 120
        )

        #expect(queue.count == 120)
        #expect(queue.first?.id == source.id)
        #expect(Set(queue.map(\.id)).count == 120)
        #expect(queue.filter { $0.artist == "Cryoshell" }.count == 11)
    }

    @Test func playlistGenerationWarnsWhenSimilarityReturnsOnlyOneAlbum() throws {
        let warning = try #require(PlaylistGenerationPolicy.shortResultWarning(
            similarCount: 11,
            requestedCount: 130,
            finalCount: 130,
            fallbackCount: 119
        ))

        #expect(warning.message == "Only 11 similar songs found")
        #expect(warning.details.contains("Requested 130"))
        #expect(warning.details.contains("returned 11 similar songs"))
        #expect(warning.details.contains("Added 119 fallback songs"))
    }

    @Test func playlistGenerationWarningNamesTheSimilaritySource() throws {
        let sonicWarning = try #require(PlaylistGenerationPolicy.shortResultWarning(
            similarCount: 11,
            requestedCount: 130,
            finalCount: 130,
            fallbackCount: 119,
            similarDescription: "sonic-similar tracks"
        ))
        let artistWarning = try #require(PlaylistGenerationPolicy.shortResultWarning(
            similarCount: 11,
            requestedCount: 130,
            finalCount: 130,
            fallbackCount: 119,
            similarDescription: "artist-similar songs"
        ))

        #expect(sonicWarning.message == "Only 11 sonic-similar tracks found")
        #expect(sonicWarning.details.contains("returned 11 sonic-similar tracks"))
        #expect(artistWarning.message == "Only 11 artist-similar songs found")
        #expect(artistWarning.details.contains("returned 11 artist-similar songs"))
    }

    @Test func playlistGenerationCapsOverfullSimilarityResultsToRequestedCount() {
        let source = makeSong(id: "source")
        let similarSongs = (0..<160).map { makeSong(id: "similar-\($0)") }

        let queue = PlaylistGenerationPolicy.queue(
            sourceSong: source,
            primarySongs: similarSongs,
            fallbackSongs: [],
            requestedCount: 100
        )

        #expect(queue.count == 100)
        #expect(queue.first?.id == source.id)
        #expect(queue.last?.id == "similar-98")
    }

    @Test func searchRetryPolicyRetriesTransientTransportFailuresOnly() {
        #expect(SearchRetryPolicy.isRetryable(URLError(.timedOut)))
        #expect(SearchRetryPolicy.isRetryable(URLError(.networkConnectionLost)))
        #expect(SearchRetryPolicy.isRetryable(URLError(.cannotConnectToHost)))
        #expect(!SearchRetryPolicy.isRetryable(URLError(.badServerResponse)))
        #expect(!SearchRetryPolicy.isRetryable(NavidromeError.authenticationFailed))
    }

    @Test(arguments: [0x1A2B3C4D, 0xBEEFF00D, 0xC0FFEE])
    func seededPlaybackSessionSyncFuzzMaintainsOrderingInvariants(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        for step in 0..<160 {
            let existing = randomSession(seed: seed, step: step, generator: &generator, now: now, allowStale: false)
            let incoming = randomSession(seed: seed, step: step + 10_000, generator: &generator, now: now, allowStale: true)
            let shouldApply = PlaybackSessionSyncPolicy.shouldApply(incoming, over: existing, now: now)

            if PlaybackSessionSyncPolicy.isStale(incoming, current: existing, now: now) {
                #expect(shouldApply == false)
            }

            if incoming.id == existing.id,
               incoming.updatedByDeviceID == existing.updatedByDeviceID,
               incoming.revision < existing.revision {
                #expect(shouldApply == false)
            }

            if incoming.id == existing.id,
               incoming.updatedByDeviceID == existing.updatedByDeviceID,
               incoming.revision == existing.revision,
               incoming.updatedAt < existing.updatedAt {
                #expect(shouldApply == false)
            }

            if incoming.id != existing.id, incoming.updatedAt <= existing.updatedAt {
                #expect(shouldApply == false)
            }

            if shouldApply {
                #expect(PlaybackSessionSyncPolicy.isStale(incoming, current: existing, now: now) == false)
                if incoming.id == existing.id {
                    #expect(incoming.revision > existing.revision || incoming.updatedAt > existing.updatedAt || incoming.updatedByDeviceID > existing.updatedByDeviceID)
                } else {
                    #expect(incoming.updatedAt > existing.updatedAt)
                }
            }
        }
    }

    @Test(arguments: [0xA11CE, 0x12345678, 0xFEEDFACE])
    func seededCommandAcknowledgmentFuzzRejectsNonAcknowledgingUpdates(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let now = Date(timeIntervalSince1970: 1_770_100_000)
        let songs = (0..<5).map { makeSong(id: "song-\($0)") }

        for iteration in 0..<140 {
            let action = randomPlaybackAction(generator: &generator)
            let expectedIndex = generator.int(in: 0..<songs.count)
            let expectedTime = TimeInterval(generator.int(in: 0..<150))
            let expectedVolume = Double(generator.int(in: 0..<100)) / 100
            let acknowledgingSession = sessionAcknowledging(
                action: action,
                songs: songs,
                expectedIndex: expectedIndex,
                expectedTime: expectedTime,
                expectedVolume: expectedVolume,
                now: now
            )
            let nonAcknowledgingSession = sessionNotAcknowledging(
                action: action,
                songs: songs,
                expectedIndex: expectedIndex,
                expectedTime: expectedTime,
                expectedVolume: expectedVolume,
                now: now
            )

            let acknowledging = PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
                acknowledgingSession,
                action: action,
                expectedSongs: songs,
                expectedIndex: expectedIndex,
                expectedTime: expectedTime,
                expectedVolume: expectedVolume,
                now: now
            )
            let notAcknowledging = PendingPlaybackSessionAcknowledgmentPolicy.shouldAcceptAcknowledgingSession(
                nonAcknowledgingSession,
                action: action,
                expectedSongs: songs,
                expectedIndex: expectedIndex,
                expectedTime: expectedTime,
                expectedVolume: expectedVolume,
                now: now
            )

            #expect(acknowledging == true, "seed \(seed) iteration \(iteration) action \(action) should acknowledge the expected session")
            #expect(notAcknowledging == false, "seed \(seed) iteration \(iteration) action \(action) unexpectedly acknowledged generated negative session")
            #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
                hasPendingCommandForDevice: true,
                isAcknowledgingPendingCommand: acknowledging
            ) == acknowledging)
            #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
                hasPendingCommandForDevice: true,
                isAcknowledgingPendingCommand: notAcknowledging
            ) == false)
            #expect(PendingPlaybackUpdatePolicy.shouldApplyUpdate(
                hasPendingCommandForDevice: false,
                isAcknowledgingPendingCommand: false
            ) == true)
        }
    }

    @Test(arguments: [0x515151, 0xDEADBEEF, 0xABCD1234])
    func seededPrebufferSchedulingFuzzMaintainsWindowAndSlotInvariants(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)

        for _ in 0..<180 {
            let queueCount = generator.int(in: 0..<80)
            let queueKeys = (0..<queueCount).map { "song-\($0)" }
            let currentIndex = queueCount == 0 ? generator.int(in: -5..<5) : generator.int(in: -3..<(queueCount + 3))
            let aheadCount = generator.int(in: 0..<30)
            let keepPreviousCount = generator.int(in: 0..<30)
            let activeKeys = randomSubset(of: queueKeys + ["external-active"], maxCount: 8, generator: &generator)
            let preparedKeys = randomSubset(of: queueKeys + ["external-prepared"], maxCount: 12, generator: &generator)
            let failedKeys = randomSubset(of: queueKeys + ["external-failed"], maxCount: 6, generator: &generator)
            let maxConcurrentTasks = generator.int(in: 0..<8)
            let currentKey = queueKeys.indices.contains(currentIndex) ? queueKeys[currentIndex] : nil
            let upcomingKeys = PrebufferSchedulingPolicy.upcomingKeys(
                queueKeys: queueKeys,
                currentIndex: currentIndex,
                aheadCount: aheadCount
            )
            let previousKeys = PrebufferSchedulingPolicy.previousKeys(
                queueKeys: queueKeys,
                currentIndex: currentIndex,
                keepCount: keepPreviousCount
            )
            let candidates = PrebufferSchedulingPolicy.orderedCandidateKeys(
                currentKey: currentKey,
                upcomingKeys: upcomingKeys,
                previousKeys: previousKeys
            )
            let scheduled = PrebufferSchedulingPolicy.keysToSchedule(
                candidateKeys: candidates,
                activeKeys: activeKeys,
                preparedKeys: preparedKeys,
                failedKeys: failedKeys,
                maxConcurrentTasks: maxConcurrentTasks
            )
            let availableSlots = max(0, maxConcurrentTasks - activeKeys.count)

            #expect(Set(scheduled).isSubset(of: Set(candidates)))
            #expect(Set(scheduled).isDisjoint(with: activeKeys))
            #expect(Set(scheduled).isDisjoint(with: preparedKeys))
            #expect(Set(scheduled).isDisjoint(with: failedKeys))
            #expect(scheduled.count <= availableSlots)
            #expect(previousKeys.allSatisfy { candidates.contains($0) })
            #expect(upcomingKeys.count <= aheadCount)
            #expect(previousKeys.count <= keepPreviousCount)
            let desiredKeys = PrebufferSchedulingPolicy.desiredKeys(
                currentKey: currentKey,
                upcomingKeys: upcomingKeys,
                previousKeys: previousKeys
            )
            #expect(desiredKeys.isSuperset(of: Set(upcomingKeys)))
            #expect(desiredKeys.isSuperset(of: Set(previousKeys)))
        }
    }

    @MainActor
    @Test(arguments: [0x2468ACE0, 0x13579BDF])
    func seededSyncDelegateSubmitterFuzzEventuallyDrainsWithoutDroppingEvents(seed: UInt64) async {
        var generator = SeededGenerator(seed: seed)
        let submitter = SyncDelegateEventSubmitter(label: "WRhythm.Tests.SeededSubmitter.\(seed)")
        var values: [Int] = []
        var expectedValues: [Int] = []
        var expectedReentrantValues: [Int] = []

        for value in 0..<220 {
            expectedValues.append(value)
            let shouldEnqueueReentrant = generator.bool(probabilityPercent: 18)
            if shouldEnqueueReentrant {
                let reentrantValue = 1_000 + value
                expectedReentrantValues.append(reentrantValue)
                submitter.enqueue {
                    values.append(value)
                    submitter.enqueue {
                        values.append(reentrantValue)
                    }
                }
            } else {
                submitter.enqueue {
                    values.append(value)
                }
            }
        }

        await submitter.waitForIdle()

        expectedValues.append(contentsOf: expectedReentrantValues)
        #expect(values == expectedValues)
        #expect(Set(values).count == values.count)
    }

    @Test(arguments: [0x5C0BB1E, 0xCAFEF00D, 0xFACE])
    func seededScrobbleProgressFuzzCountsOnlyAudibleProgressAndSubmitsAtMostOnce(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        var tracker = ScrobbleProgressTracker()
        let start = Date(timeIntervalSince1970: 1_770_200_000)
        let duration = TimeInterval(generator.int(in: 60..<720))
        var now = start
        var position: TimeInterval = 0
        var expectedListened: TimeInterval = 0
        var submissionCount = 0

        _ = tracker.start(songID: "song-\(seed)", currentTime: position, now: now)

        for _ in 0..<180 {
            let previousPosition = position
            let previousNow = now
            now = now.addingTimeInterval(TimeInterval(generator.int(in: 0..<6)))
            let isPlaying = generator.bool(probabilityPercent: 62)

            switch generator.int(in: 0..<7) {
            case 0:
                position = max(0, position - TimeInterval(generator.int(in: 0..<20)))
            case 1:
                position = min(duration, position + TimeInterval(generator.int(in: 15..<80)))
            case 2:
                break
            default:
                position = min(duration, position + (isPlaying ? TimeInterval(generator.int(in: 0..<6)) : 0))
            }

            if isPlaying {
                expectedListened += min(
                    max(0, now.timeIntervalSince(previousNow)),
                    max(0, position - previousPosition)
                )
            }

            let event = tracker.update(
                songID: "song-\(seed)",
                currentTime: position,
                duration: duration,
                isPlaying: isPlaying,
                now: now
            )
            if event == .submission(songID: "song-\(seed)") {
                submissionCount += 1
                #expect(expectedListened >= ScrobbleProgressTracker.submissionThreshold(for: duration))
            }

            #expect(tracker.listenedTime <= expectedListened)
            #expect(submissionCount <= 1)
        }
    }

    @Test func threeDeviceHarnessRelaysWatchPlaybackThroughIPhoneToMac() {
        var harness = ThreeDeviceSyncHarness(songs: (0..<4).map { makeSong(id: "scenario-\($0)") })
        var generator = SeededGenerator(seed: 0xA77E57)

        harness.play(on: .watch)
        harness.drainRandomly(generator: &generator)

        #expect(harness.convergenceFailures().isEmpty)
        #expect(harness.session(on: .mac)?.outputDeviceID == ScenarioDevice.watch.rawValue)
        #expect(harness.session(on: .mac)?.isPlaying == true)
        #expect(harness.session(on: .iphone)?.outputDeviceID == ScenarioDevice.watch.rawValue)

        harness.pause(on: .watch)
        harness.drainRandomly(generator: &generator)

        #expect(harness.convergenceFailures().isEmpty)
        #expect(harness.session(on: .mac)?.outputDeviceID == ScenarioDevice.watch.rawValue)
        #expect(harness.session(on: .mac)?.isPlaying == false)
        #expect(harness.session(on: .iphone)?.isPlaying == false)
    }

    @Test func asyncTransportIntegrationRelaysDelayedWatchPlaybackThroughIPhoneToMac() async {
        let harness = AsyncThreeDeviceSyncIntegrationHarness(
            songs: (0..<5).map { makeSong(id: "async-relay-\($0)") },
            seed: 0xA11CE,
            dropProbabilityPercent: 0
        )

        await harness.play(on: .watch)
        await harness.drain()

        var convergenceFailures = await harness.convergenceFailures()
        var macSession = await harness.session(on: .mac)
        var iphoneSession = await harness.session(on: .iphone)
        #expect(convergenceFailures.isEmpty)
        #expect(macSession?.outputDeviceID == ScenarioDevice.watch.rawValue)
        #expect(macSession?.isPlaying == true)
        #expect(iphoneSession?.outputDeviceID == ScenarioDevice.watch.rawValue)

        await harness.disconnect(.watch)
        await harness.drain()

        macSession = await harness.session(on: .mac)
        iphoneSession = await harness.session(on: .iphone)
        #expect(macSession?.isPlaying == false)
        #expect(iphoneSession?.isPlaying == false)

        await harness.reconnect(.watch, reliableBootstrap: true)
        await harness.drain()

        convergenceFailures = await harness.convergenceFailures()
        macSession = await harness.session(on: .mac)
        #expect(convergenceFailures.isEmpty)
        #expect(macSession?.outputDeviceID == ScenarioDevice.watch.rawValue)
        #expect(macSession?.isPlaying == true)
    }

    @Test func asyncTransportIntegrationDelayedOlderSessionCannotOverwriteNewerOwner() async {
        let harness = AsyncThreeDeviceSyncIntegrationHarness(
            songs: (0..<6).map { makeSong(id: "async-stale-owner-\($0)") },
            seed: 0x57A1E,
            dropProbabilityPercent: 0,
            duplicateProbabilityPercent: 35,
            maxDelayTicks: 18
        )

        await harness.play(on: .watch)
        await harness.drain(limit: 1)
        await harness.next(on: .mac)
        await harness.drain()

        let convergenceFailures = await harness.convergenceFailures()
        let macSession = await harness.session(on: .mac)
        let iphoneSession = await harness.session(on: .iphone)
        let watchSession = await harness.session(on: .watch)
        #expect(convergenceFailures.isEmpty)
        #expect(macSession?.outputDeviceID == ScenarioDevice.mac.rawValue)
        #expect(macSession?.currentIndex == 1)
        #expect(iphoneSession?.outputDeviceID == ScenarioDevice.mac.rawValue)
        #expect(watchSession?.outputDeviceID == ScenarioDevice.mac.rawValue)
    }

    @Test func asyncTransportIntegrationSimultaneousOwnerRaceConvergesToLatestRevision() async {
        let harness = AsyncThreeDeviceSyncIntegrationHarness(
            songs: (0..<8).map { makeSong(id: "async-owner-race-\($0)") },
            seed: 0x0B5E55ED,
            dropProbabilityPercent: 0,
            duplicateProbabilityPercent: 45,
            maxDelayTicks: 24
        )

        await harness.play(on: .watch)
        await harness.seek(on: .iphone, position: 42)
        await harness.next(on: .mac)
        await harness.drain()

        let convergenceFailures = await harness.convergenceFailures()
        let macSession = await harness.session(on: .mac)
        let iphoneSession = await harness.session(on: .iphone)
        let watchSession = await harness.session(on: .watch)
        #expect(convergenceFailures.isEmpty)
        #expect(macSession?.outputDeviceID == ScenarioDevice.mac.rawValue)
        #expect(macSession?.currentIndex == 1)
        #expect(iphoneSession?.outputDeviceID == ScenarioDevice.mac.rawValue)
        #expect(watchSession?.outputDeviceID == ScenarioDevice.mac.rawValue)
    }

    @Test func asyncTransportIntegrationMoveHereWithLowerLocalRevisionClaimsOutput() async {
        let harness = AsyncThreeDeviceSyncIntegrationHarness(
            songs: (0..<8).map { makeSong(id: "async-move-here-\($0)") },
            seed: 0x0BADCAFE,
            dropProbabilityPercent: 0,
            duplicateProbabilityPercent: 40,
            maxDelayTicks: 18
        )

        for _ in 0..<24 {
            await harness.play(on: .mac)
            await harness.drain()
        }

        let iphoneBeforeMove = await harness.session(on: .iphone)
        #expect(iphoneBeforeMove?.outputDeviceID == ScenarioDevice.mac.rawValue)

        await harness.play(on: .iphone)
        await harness.drain()

        var convergenceFailures = await harness.convergenceFailures()
        var macSession = await harness.session(on: .mac)
        var iphoneSession = await harness.session(on: .iphone)
        var watchSession = await harness.session(on: .watch)
        #expect(convergenceFailures.isEmpty)
        #expect(macSession?.outputDeviceID == ScenarioDevice.iphone.rawValue)
        #expect(iphoneSession?.outputDeviceID == ScenarioDevice.iphone.rawValue)
        #expect(watchSession?.outputDeviceID == ScenarioDevice.iphone.rawValue)
        #expect(macSession?.isPlaying == true)

        await harness.reconnect(.mac, reliableBootstrap: true)
        await harness.drain()

        convergenceFailures = await harness.convergenceFailures()
        macSession = await harness.session(on: .mac)
        iphoneSession = await harness.session(on: .iphone)
        watchSession = await harness.session(on: .watch)
        #expect(convergenceFailures.isEmpty)
        #expect(macSession?.outputDeviceID == ScenarioDevice.iphone.rawValue)
        #expect(iphoneSession?.outputDeviceID == ScenarioDevice.iphone.rawValue)
        #expect(watchSession?.outputDeviceID == ScenarioDevice.iphone.rawValue)
    }

    @Test func asyncTransportIntegrationBridgeReconnectResyncsSeparatedComponents() async {
        let harness = AsyncThreeDeviceSyncIntegrationHarness(
            songs: (0..<7).map { makeSong(id: "async-bridge-reconnect-\($0)") },
            seed: 0xB21D6E,
            dropProbabilityPercent: 0,
            duplicateProbabilityPercent: 30,
            maxDelayTicks: 14
        )

        await harness.play(on: .watch)
        await harness.drain()
        await harness.disconnect(.iphone)
        await harness.play(on: .mac)
        await harness.next(on: .watch)
        await harness.drain()

        var macSession = await harness.session(on: .mac)
        var watchSession = await harness.session(on: .watch)
        #expect(macSession?.outputDeviceID == ScenarioDevice.mac.rawValue)
        #expect(watchSession?.outputDeviceID == ScenarioDevice.watch.rawValue)

        await harness.reconnect(.iphone, reliableBootstrap: true)
        await harness.drain()

        let convergenceFailures = await harness.convergenceFailures()
        macSession = await harness.session(on: .mac)
        watchSession = await harness.session(on: .watch)
        let iphoneSession = await harness.session(on: .iphone)
        let outputDeviceIDs = Set([
            macSession?.outputDeviceID,
            iphoneSession?.outputDeviceID,
            watchSession?.outputDeviceID
        ].compactMap { $0 })
        #expect(convergenceFailures.isEmpty)
        #expect(outputDeviceIDs.count == 1)
        #expect(outputDeviceIDs.isSubset(of: [ScenarioDevice.mac.rawValue, ScenarioDevice.watch.rawValue]))
        #expect(macSession?.isPlaying == true)
        #expect(iphoneSession?.isPlaying == true)
        #expect(watchSession?.isPlaying == true)
    }

    @Test(arguments: [0xA5A5_0001, 0xA5A5_0002, 0xA5A5_0003, 0xA5A5_0004])
    func seededAsyncTransportIntegrationFuzzConvergesAfterReliableResync(seed: UInt64) async {
        let harness = AsyncThreeDeviceSyncIntegrationHarness(
            songs: (0..<11).map { makeSong(id: "async-fuzz-\(seed)-\($0)") },
            seed: seed
        )

        await harness.runRandomScenario(steps: 260)
        await harness.reconnectAllReliably()
        await harness.drain()

        let pendingEnvelopeCount = await harness.pendingEnvelopeCount
        let convergenceFailures = await harness.convergenceFailures()
        let duplicateProcessingFailures = await harness.duplicateProcessingFailures()
        #expect(pendingEnvelopeCount == 0, "seed \(seed): pending envelopes did not drain")
        #expect(convergenceFailures.isEmpty, "seed \(seed): \(convergenceFailures.joined(separator: "; "))")
        #expect(duplicateProcessingFailures.isEmpty, "seed \(seed): \(duplicateProcessingFailures.joined(separator: "; "))")
    }

    @Test(arguments: [
        0x7E51_0001, 0x7E51_0002, 0x7E51_0003, 0x7E51_0004,
        0x7E51_0005, 0x7E51_0006, 0x7E51_0007, 0x7E51_0008,
        0x7E51_0009, 0x7E51_000A, 0x7E51_000B, 0x7E51_000C
    ])
    func seededAsyncTransportIntegrationSoakConvergesAfterLossyRelays(seed: UInt64) async {
        let harness = AsyncThreeDeviceSyncIntegrationHarness(
            songs: (0..<19).map { makeSong(id: "async-soak-\(seed)-\($0)") },
            seed: seed,
            dropProbabilityPercent: 14,
            duplicateProbabilityPercent: 32,
            maxDelayTicks: 32
        )

        await harness.runRandomScenario(steps: 700)
        await harness.reconnectAllReliably()
        await harness.drain()

        let pendingEnvelopeCount = await harness.pendingEnvelopeCount
        let convergenceFailures = await harness.convergenceFailures()
        let duplicateProcessingFailures = await harness.duplicateProcessingFailures()
        #expect(pendingEnvelopeCount == 0, "seed \(seed): pending envelopes did not drain")
        #expect(convergenceFailures.isEmpty, "seed \(seed): \(convergenceFailures.joined(separator: "; "))")
        #expect(duplicateProcessingFailures.isEmpty, "seed \(seed): \(duplicateProcessingFailures.joined(separator: "; "))")
    }

    @Test(arguments: [0x5157A7E, 0xBADC0FFE, 0xC001D00D, 0x5EED1234])
    func seededThreeDevicePlaybackScenarioFuzzConvergesAcrossRelays(seed: UInt64) {
        runThreeDevicePlaybackScenarioFuzz(seed: seed, steps: 220, songCount: 7)
    }

    @Test func threeDevicePlaybackScenarioSoakConvergesAcrossRelays() {
        for seed in Self.threeDeviceScenarioSoakSeeds(count: 128) {
            runThreeDevicePlaybackScenarioFuzz(seed: seed, steps: 1_500, songCount: 31)
        }
    }

    private func runThreeDevicePlaybackScenarioFuzz(seed: UInt64, steps: Int, songCount: Int) {
        var generator = SeededGenerator(seed: seed)
        var harness = ThreeDeviceSyncHarness(songs: (0..<songCount).map { makeSong(id: "seed-\(seed)-song-\($0)") })

        for step in 0..<steps {
            let device = ScenarioDevice.allCases[generator.int(in: 0..<ScenarioDevice.allCases.count)]

            switch generator.int(in: 0..<13) {
            case 0:
                harness.disconnect(device)
            case 1:
                harness.reconnect(device)
            case 2:
                harness.pause(on: device)
            case 3:
                harness.seek(on: device, position: TimeInterval(generator.int(in: 0..<150)))
            case 4:
                harness.next(on: device)
            case 5:
                harness.previous(on: device)
            case 6:
                harness.disconnect(device)
                harness.reconnect(device)
            default:
                harness.play(on: device)
            }

            if generator.bool(probabilityPercent: 33) {
                harness.enqueueDuplicateOfRandomPendingEnvelope(generator: &generator)
            }

            if generator.bool(probabilityPercent: 8) {
                harness.enqueueDuplicateOfRandomPendingEnvelope(generator: &generator)
            }

            if step.isMultiple(of: 4) || generator.bool(probabilityPercent: 35) {
                harness.drainRandomly(generator: &generator, limit: generator.int(in: 1..<12))
            }

            if step.isMultiple(of: 11) {
                harness.drainRandomly(generator: &generator)
                #expect(harness.pendingEnvelopeCount == 0, "seed \(seed) step \(step): pending envelopes did not drain")
                #expect(harness.duplicateProcessingFailures().isEmpty, "seed \(seed) step \(step): \(harness.duplicateProcessingFailures().joined(separator: "; "))")
            }
        }

        harness.reconnect(.iphone)
        harness.reconnect(.mac)
        harness.reconnect(.watch)
        harness.drainRandomly(generator: &generator)

        #expect(harness.pendingEnvelopeCount == 0, "seed \(seed): pending envelopes did not drain")
        #expect(harness.convergenceFailures().isEmpty, "seed \(seed): \(harness.convergenceFailures().joined(separator: "; "))")
        #expect(harness.duplicateProcessingFailures().isEmpty, "seed \(seed): \(harness.duplicateProcessingFailures().joined(separator: "; "))")
    }

    private static func threeDeviceScenarioSoakSeeds(count: Int) -> [UInt64] {
        (0..<count).map { index in
            0xD15E_A5E0_0000_0001 &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        }
    }

    private struct SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func int(in range: Range<Int>) -> Int {
            guard range.lowerBound < range.upperBound else { return range.lowerBound }
            let width = UInt64(range.upperBound - range.lowerBound)
            return range.lowerBound + Int(next() % width)
        }

        mutating func bool(probabilityPercent: Int = 50) -> Bool {
            int(in: 0..<100) < probabilityPercent
        }
    }

    private func randomSession(
        seed: UInt64,
        step: Int,
        generator: inout SeededGenerator,
        now: Date,
        allowStale: Bool
    ) -> PlaybackSession {
        let deviceIDs = ["iphone", "mac", "watch"]
        let sessionID = generator.bool(probabilityPercent: 55)
            ? "shared-session-\(generator.int(in: 0..<3))"
            : "\(deviceIDs[generator.int(in: 0..<deviceIDs.count)])-session"
        let queueCount = generator.int(in: 1..<5)
        let songs = (0..<queueCount).map { makeSong(id: "seed-\(seed)-step-\(step)-song-\($0)") }
        let currentIndex = generator.int(in: 0..<queueCount)
        let timestampOffset = allowStale ? generator.int(in: -50..<16) : generator.int(in: -20..<6)

        return makeSession(
            id: sessionID,
            songs: songs,
            currentIndex: currentIndex,
            outputDeviceID: deviceIDs[generator.int(in: 0..<deviceIDs.count)],
            isPlaying: generator.bool(),
            position: TimeInterval(generator.int(in: 0..<240)),
            volume: Double(generator.int(in: 0..<101)) / 100,
            revision: generator.int(in: 0..<20),
            updatedAt: now.addingTimeInterval(TimeInterval(timestampOffset)),
            updatedByDeviceID: deviceIDs[generator.int(in: 0..<deviceIDs.count)]
        )
    }

    private func randomPlaybackAction(generator: inout SeededGenerator) -> PlaybackSyncCommandAction {
        let actions: [PlaybackSyncCommandAction] = [
            .play,
            .pause,
            .next,
            .previous,
            .seek,
            .setVolume,
            .playQueue,
            .enqueue,
            .syncQueue,
            .stop
        ]
        return actions[generator.int(in: 0..<actions.count)]
    }

    private func sessionAcknowledging(
        action: PlaybackSyncCommandAction,
        songs: [Song],
        expectedIndex: Int,
        expectedTime: TimeInterval,
        expectedVolume: Double,
        now: Date
    ) -> PlaybackSession {
        switch action {
        case .play:
            return makeSession(songs: songs, currentIndex: expectedIndex, isPlaying: true, updatedAt: now)
        case .pause:
            return makeSession(songs: songs, currentIndex: expectedIndex, isPlaying: false, updatedAt: now)
        case .seek:
            return makeSession(songs: songs, currentIndex: expectedIndex, isPlaying: false, position: expectedTime, updatedAt: now)
        case .setVolume:
            return makeSession(songs: songs, currentIndex: expectedIndex, volume: expectedVolume, updatedAt: now)
        case .next, .previous:
            return makeSession(songs: songs, currentIndex: expectedIndex, updatedAt: now)
        case .playQueue, .syncQueue:
            return makeSession(songs: songs, currentIndex: expectedIndex, updatedAt: now)
        case .enqueue:
            return makeSession(songs: [makeSong(id: "prefix")] + songs + [makeSong(id: "suffix")], currentIndex: 0, updatedAt: now)
        case .stop:
            return makeSession(songs: [], currentIndex: 0, isPlaying: false, updatedAt: now)
        case .toggle:
            return makeSession(songs: songs, currentIndex: expectedIndex, updatedAt: now)
        }
    }

    private func sessionNotAcknowledging(
        action: PlaybackSyncCommandAction,
        songs: [Song],
        expectedIndex: Int,
        expectedTime: TimeInterval,
        expectedVolume: Double,
        now: Date
    ) -> PlaybackSession {
        let wrongIndex = (expectedIndex + 1) % max(songs.count, 1)
        switch action {
        case .play:
            return makeSession(songs: songs, currentIndex: expectedIndex, isPlaying: false, updatedAt: now)
        case .pause:
            return makeSession(songs: songs, currentIndex: expectedIndex, isPlaying: true, updatedAt: now)
        case .seek:
            return makeSession(songs: songs, currentIndex: expectedIndex, isPlaying: false, position: expectedTime + PlaybackCommandSyncPolicy.seekAcknowledgmentTolerance + 1, updatedAt: now)
        case .setVolume:
            let wrongVolume = expectedVolume > 0.5 ? expectedVolume - 0.25 : expectedVolume + 0.25
            return makeSession(songs: songs, currentIndex: expectedIndex, volume: wrongVolume, updatedAt: now)
        case .next, .previous:
            return makeSession(songs: songs, currentIndex: wrongIndex, updatedAt: now)
        case .playQueue, .syncQueue:
            return makeSession(songs: songs.reversed(), currentIndex: wrongIndex, updatedAt: now)
        case .enqueue:
            return makeSession(songs: [makeSong(id: "not-enqueued")], currentIndex: 0, updatedAt: now)
        case .stop:
            return makeSession(songs: songs, currentIndex: expectedIndex, isPlaying: true, updatedAt: now)
        case .toggle:
            return makeSession(songs: songs, currentIndex: expectedIndex, updatedAt: now)
        }
    }

    private func randomSubset(
        of keys: [String],
        maxCount: Int,
        generator: inout SeededGenerator
    ) -> Set<String> {
        var selected = Set<String>()
        for key in keys where selected.count < maxCount && generator.bool(probabilityPercent: 22) {
            selected.insert(key)
        }
        return selected
    }

    private enum ScenarioDevice: String, CaseIterable {
        case mac
        case iphone
        case watch
    }

    private struct ScenarioEnvelope {
        let id: String
        let session: PlaybackSession
        let origin: ScenarioDevice
        let sender: ScenarioDevice
        let receiver: ScenarioDevice
    }

    private struct ScenarioNode {
        let id: ScenarioDevice
        var isConnected = true
        var sharedSession: PlaybackSession?
        var localSession: PlaybackSession?
        var processedEnvelopeIDs = Set<String>()
        var processedEnvelopeOrder: [String] = []
    }

    private struct SessionSignature: Equatable, CustomStringConvertible {
        let id: String
        let revision: Int
        let queueIDs: [String]
        let currentIndex: Int
        let position: Int
        let isPlaying: Bool
        let outputDeviceID: String
        let updatedAt: TimeInterval
        let updatedByDeviceID: String

        init?(_ session: PlaybackSession?) {
            guard let session else { return nil }
            self.id = session.id
            self.revision = session.revision
            self.queueIDs = session.queue.map(\.id)
            self.currentIndex = session.currentIndex
            self.position = Int(session.position.rounded())
            self.isPlaying = session.isPlaying
            self.outputDeviceID = session.outputDeviceID
            self.updatedAt = session.updatedAt.timeIntervalSince1970
            self.updatedByDeviceID = session.updatedByDeviceID
        }

        var description: String {
            "\(outputDeviceID) rev=\(revision) idx=\(currentIndex) pos=\(position) playing=\(isPlaying) by=\(updatedByDeviceID)"
        }
    }

    private struct ThreeDeviceSyncHarness {
        private(set) var nodes: [ScenarioDevice: ScenarioNode]
        private var pendingEnvelopes: [ScenarioEnvelope] = []
        private var now = Date(timeIntervalSince1970: 1_780_000_000)
        private var revisions: [ScenarioDevice: Int]
        private var envelopeSequence = 0
        private let songs: [Song]

        init(songs: [Song]) {
            self.songs = songs
            self.nodes = Dictionary(uniqueKeysWithValues: ScenarioDevice.allCases.map { ($0, ScenarioNode(id: $0)) })
            self.revisions = Dictionary(uniqueKeysWithValues: ScenarioDevice.allCases.map { ($0, 0) })
        }

        var pendingEnvelopeCount: Int {
            pendingEnvelopes.count
        }

        func session(on device: ScenarioDevice) -> PlaybackSession? {
            nodes[device]?.sharedSession
        }

        mutating func play(on device: ScenarioDevice) {
            publishLocalSession(from: device, isPlaying: true)
        }

        mutating func pause(on device: ScenarioDevice) {
            publishLocalSession(from: device, isPlaying: false)
        }

        mutating func seek(on device: ScenarioDevice, position: TimeInterval) {
            let local = nodes[device]?.localSession ?? nodes[device]?.sharedSession
            publishLocalSession(
                from: device,
                currentIndex: local?.currentIndex ?? 0,
                position: position,
                isPlaying: local?.isPlaying ?? true
            )
        }

        mutating func next(on device: ScenarioDevice) {
            let local = nodes[device]?.localSession ?? nodes[device]?.sharedSession
            let currentIndex = local?.currentIndex ?? 0
            publishLocalSession(
                from: device,
                currentIndex: (currentIndex + 1) % max(songs.count, 1),
                position: 0,
                isPlaying: local?.isPlaying ?? true
            )
        }

        mutating func previous(on device: ScenarioDevice) {
            let local = nodes[device]?.localSession ?? nodes[device]?.sharedSession
            let currentIndex = local?.currentIndex ?? 0
            publishLocalSession(
                from: device,
                currentIndex: (currentIndex - 1 + max(songs.count, 1)) % max(songs.count, 1),
                position: 0,
                isPlaying: local?.isPlaying ?? true
            )
        }

        mutating func disconnect(_ device: ScenarioDevice) {
            advanceTime()
            nodes[device]?.isConnected = false

            for observer in ScenarioDevice.allCases where observer != device && (nodes[observer]?.isConnected == true) {
                guard let pauseSession = ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
                    disconnectedDeviceID: device.rawValue,
                    currentSession: nodes[observer]?.sharedSession,
                    localDeviceID: observer.rawValue,
                    disconnectedAt: now
                ) else {
                    continue
                }
                publishExistingSession(pauseSession, from: observer)
            }
        }

        mutating func reconnect(_ device: ScenarioDevice) {
            advanceTime()
            nodes[device]?.isConnected = true

            publishReconnectBootstrap(from: device)
            for neighbor in neighbors(of: device) {
                publishReconnectBootstrap(from: neighbor)
            }
        }

        mutating func enqueueDuplicateOfRandomPendingEnvelope(generator: inout SeededGenerator) {
            guard !pendingEnvelopes.isEmpty else { return }
            pendingEnvelopes.append(pendingEnvelopes[generator.int(in: 0..<pendingEnvelopes.count)])
        }

        mutating func drainRandomly(generator: inout SeededGenerator, limit: Int = 1_000) {
            var delivered = 0
            while !pendingEnvelopes.isEmpty && delivered < limit {
                let index = generator.int(in: 0..<pendingEnvelopes.count)
                let envelope = pendingEnvelopes.remove(at: index)
                deliver(envelope)
                delivered += 1
            }
        }

        func convergenceFailures() -> [String] {
            connectedComponents().flatMap { component -> [String] in
                let signatures = component.map { ($0, SessionSignature(nodes[$0]?.sharedSession)) }
                let uniqueSignatures = Set(signatures.map { String(describing: $0.1) })
                guard uniqueSignatures.count > 1 else { return [] }
                return ["component \(component.map(\.rawValue).joined(separator: ",")) diverged: \(signatures.map { "\($0.0.rawValue)=\(String(describing: $0.1))" }.joined(separator: ", "))"]
            }
        }

        func duplicateProcessingFailures() -> [String] {
            nodes.values.compactMap { node in
                node.processedEnvelopeIDs.count == node.processedEnvelopeOrder.count
                    ? nil
                    : "\(node.id.rawValue) processed duplicate envelope"
            }
        }

        private mutating func publishLocalSession(
            from device: ScenarioDevice,
            currentIndex: Int = 0,
            position: TimeInterval = 0,
            isPlaying: Bool
        ) {
            advanceTime()
            let session = PlaybackSession(
                id: "scenario-shared-playback",
                revision: nextRevision(for: device),
                queue: songs,
                currentIndex: min(max(currentIndex, 0), max(songs.count - 1, 0)),
                position: position,
                isPlaying: isPlaying,
                volume: 0.8,
                outputDeviceID: device.rawValue,
                updatedAt: now,
                updatedByDeviceID: device.rawValue
            )
            nodes[device]?.localSession = session
            publishExistingSession(session, from: device)
        }

        private mutating func publishReconnectBootstrap(from device: ScenarioDevice) {
            guard nodes[device]?.isConnected == true else { return }

            if let localSession = nodes[device]?.localSession,
               SyncStateRefreshPublicationPolicy.shouldPublishLocalPlayback(
                   sharedOutputDeviceID: nodes[device]?.sharedSession?.outputDeviceID,
                   localDeviceID: device.rawValue,
                   hasLocalPlayback: !localSession.queue.isEmpty,
                   isLocalPlaying: localSession.isPlaying,
                   localUpdatedAt: localSession.updatedAt,
                   sharedUpdatedAt: nodes[device]?.sharedSession?.updatedAt
               ) {
                publishRefreshedSession(localSession, from: device)
                return
            }

            if let sharedSession = nodes[device]?.sharedSession,
               SyncStateRefreshPublicationPolicy.shouldRebroadcastSharedPlayback(
                   sharedOutputDeviceID: sharedSession.outputDeviceID,
                   localDeviceID: device.rawValue
               ) {
                publishExistingSession(sharedSession, from: device)
            }
        }

        private mutating func publishRefreshedSession(_ session: PlaybackSession, from device: ScenarioDevice) {
            let revision = nextRevision(for: device)
            let refreshed = copySession(
                session,
                revision: revision,
                updatedAt: now,
                updatedByDeviceID: device.rawValue
            )
            publishExistingSession(refreshed, from: device)
        }

        private mutating func publishExistingSession(_ session: PlaybackSession, from device: ScenarioDevice) {
            let envelopeID = nextEnvelopeID(origin: device)
            apply(session, to: device, envelopeID: envelopeID)

            guard nodes[device]?.isConnected == true else { return }
            for neighbor in neighbors(of: device) {
                pendingEnvelopes.append(ScenarioEnvelope(id: envelopeID, session: session, origin: device, sender: device, receiver: neighbor))
            }
        }

        private mutating func deliver(_ envelope: ScenarioEnvelope) {
            guard neighbors(of: envelope.sender).contains(envelope.receiver) else { return }
            guard markProcessed(envelope.id, on: envelope.receiver) else { return }
            apply(envelope.session, to: envelope.receiver, envelopeID: envelope.id)

            if envelope.receiver == .iphone {
                for relayTarget in neighbors(of: .iphone) where relayTarget != envelope.sender {
                    pendingEnvelopes.append(ScenarioEnvelope(
                        id: envelope.id,
                        session: envelope.session,
                        origin: envelope.origin,
                        sender: .iphone,
                        receiver: relayTarget
                    ))
                }
            }
        }

        private mutating func apply(_ session: PlaybackSession, to device: ScenarioDevice, envelopeID: String) {
            _ = markProcessed(envelopeID, on: device)
            let existing = nodes[device]?.sharedSession
            if PlaybackSessionSyncPolicy.shouldApply(session, over: existing, now: now) {
                nodes[device]?.sharedSession = session
            }
        }

        private mutating func markProcessed(_ envelopeID: String, on device: ScenarioDevice) -> Bool {
            guard var node = nodes[device] else { return false }
            guard SyncDuplicatePolicy.shouldProcess(envelopeID: envelopeID, processedEnvelopeIDs: node.processedEnvelopeIDs) else {
                return false
            }
            node.processedEnvelopeIDs.insert(envelopeID)
            node.processedEnvelopeOrder.append(envelopeID)
            node.processedEnvelopeOrder = SyncDuplicatePolicy.trimmedEnvelopeIDOrder(node.processedEnvelopeOrder)
            node.processedEnvelopeIDs = Set(node.processedEnvelopeOrder)
            nodes[device] = node
            return true
        }

        private func neighbors(of device: ScenarioDevice) -> [ScenarioDevice] {
            guard nodes[device]?.isConnected == true else { return [] }
            switch device {
            case .mac:
                return nodes[.iphone]?.isConnected == true ? [.iphone] : []
            case .iphone:
                return [.mac, .watch].filter { nodes[$0]?.isConnected == true }
            case .watch:
                return nodes[.iphone]?.isConnected == true ? [.iphone] : []
            }
        }

        private func connectedComponents() -> [[ScenarioDevice]] {
            var unvisited = Set(ScenarioDevice.allCases.filter { nodes[$0]?.isConnected == true })
            var components: [[ScenarioDevice]] = []

            while let start = unvisited.first {
                var stack = [start]
                var component: [ScenarioDevice] = []
                unvisited.remove(start)

                while let device = stack.popLast() {
                    component.append(device)
                    for neighbor in neighbors(of: device) where unvisited.contains(neighbor) {
                        unvisited.remove(neighbor)
                        stack.append(neighbor)
                    }
                }

                components.append(component)
            }

            return components
        }

        private mutating func advanceTime() {
            now = now.addingTimeInterval(0.25)
        }

        private mutating func nextRevision(for device: ScenarioDevice) -> Int {
            let revision = (revisions[device] ?? 0) + 1
            revisions[device] = revision
            return revision
        }

        private mutating func nextEnvelopeID(origin: ScenarioDevice) -> String {
            envelopeSequence += 1
            return "\(origin.rawValue)-\(envelopeSequence)"
        }

        private func copySession(
            _ session: PlaybackSession,
            revision: Int,
            updatedAt: Date,
            updatedByDeviceID: String
        ) -> PlaybackSession {
            PlaybackSession(
                id: session.id,
                revision: revision,
                queue: session.queue,
                currentIndex: session.currentIndex,
                position: session.estimatedPosition(at: updatedAt),
                isPlaying: session.isPlaying,
                volume: session.volume,
                outputDeviceID: session.outputDeviceID,
                updatedAt: updatedAt,
                updatedByDeviceID: updatedByDeviceID
            )
        }
    }

    private struct AsyncTransportEnvelope: Sendable {
        let id: String
        let session: PlaybackSession
        let origin: ScenarioDevice
        let sender: ScenarioDevice
        let receiver: ScenarioDevice
    }

    private struct AsyncTransportDelivery: Sendable {
        let dueTick: Int
        let envelope: AsyncTransportEnvelope
        let reliable: Bool
    }

    private actor AsyncSyncIntegrationNode {
        let id: ScenarioDevice
        private var isConnected = true
        private var sharedSession: PlaybackSession?
        private var localSession: PlaybackSession?
        private var processedEnvelopeIDs = Set<String>()
        private var processedEnvelopeOrder: [String] = []

        init(id: ScenarioDevice) {
            self.id = id
        }

        func setConnected(_ connected: Bool) {
            isConnected = connected
        }

        func connected() -> Bool {
            isConnected
        }

        func session() -> PlaybackSession? {
            sharedSession
        }

        func duplicateProcessingFailure() -> String? {
            processedEnvelopeIDs.count == processedEnvelopeOrder.count
                ? nil
                : "\(id.rawValue) processed duplicate envelope"
        }

        func publishLocalSession(
            songs: [Song],
            currentIndex: Int,
            position: TimeInterval,
            isPlaying: Bool,
            revision: Int,
            now: Date,
            envelopeID: String,
            neighbors: [ScenarioDevice]
        ) -> [AsyncTransportEnvelope] {
            let session = PlaybackSession(
                id: "scenario-shared-playback",
                revision: revision,
                queue: songs,
                currentIndex: min(max(currentIndex, 0), max(songs.count - 1, 0)),
                position: position,
                isPlaying: isPlaying,
                volume: 0.8,
                outputDeviceID: id.rawValue,
                updatedAt: now,
                updatedByDeviceID: id.rawValue
            )
            localSession = session
            return publishExistingSession(session, now: now, envelopeID: envelopeID, neighbors: neighbors)
        }

        func publishReconnectBootstrap(
            revision: Int,
            now: Date,
            envelopeID: String,
            neighbors: [ScenarioDevice]
        ) -> [AsyncTransportEnvelope] {
            guard isConnected else { return [] }

            if let localSession,
               SyncStateRefreshPublicationPolicy.shouldPublishLocalPlayback(
                   sharedOutputDeviceID: sharedSession?.outputDeviceID,
                   localDeviceID: id.rawValue,
                   hasLocalPlayback: !localSession.queue.isEmpty,
                   isLocalPlaying: localSession.isPlaying,
                   localUpdatedAt: localSession.updatedAt,
                   sharedUpdatedAt: sharedSession?.updatedAt
               ) {
                return publishRefreshedSession(
                    localSession,
                    revision: revision,
                    now: now,
                    envelopeID: envelopeID,
                    neighbors: neighbors
                )
            }

            if let sharedSession,
               SyncStateRefreshPublicationPolicy.shouldRebroadcastSharedPlayback(
                   sharedOutputDeviceID: sharedSession.outputDeviceID,
                   localDeviceID: id.rawValue
               ) {
                return publishExistingSession(sharedSession, now: now, envelopeID: envelopeID, neighbors: neighbors)
            }

            return []
        }

        func publishConnectivityPauseIfNeeded(
            disconnectedDeviceID: ScenarioDevice,
            revision: Int,
            now: Date,
            envelopeID: String,
            neighbors: [ScenarioDevice]
        ) -> [AsyncTransportEnvelope] {
            guard let pauseSession = ConnectivityLossPlaybackPolicy.sessionAfterDisconnectedOutput(
                disconnectedDeviceID: disconnectedDeviceID.rawValue,
                currentSession: sharedSession,
                localDeviceID: id.rawValue,
                disconnectedAt: now
            ) else {
                return []
            }

            let refreshedPause = copySession(
                pauseSession,
                revision: revision,
                updatedAt: now,
                updatedByDeviceID: id.rawValue
            )
            return publishExistingSession(refreshedPause, now: now, envelopeID: envelopeID, neighbors: neighbors)
        }

        func receive(
            _ envelope: AsyncTransportEnvelope,
            now: Date,
            relayTargets: [ScenarioDevice]
        ) -> [AsyncTransportEnvelope] {
            guard isConnected else { return [] }
            guard markProcessed(envelope.id) else { return [] }
            apply(envelope.session, now: now)

            guard id == .iphone else { return [] }
            return relayTargets.map {
                AsyncTransportEnvelope(
                    id: envelope.id,
                    session: envelope.session,
                    origin: envelope.origin,
                    sender: .iphone,
                    receiver: $0
                )
            }
        }

        private func publishRefreshedSession(
            _ session: PlaybackSession,
            revision: Int,
            now: Date,
            envelopeID: String,
            neighbors: [ScenarioDevice]
        ) -> [AsyncTransportEnvelope] {
            let refreshed = copySession(session, revision: revision, updatedAt: now, updatedByDeviceID: id.rawValue)
            return publishExistingSession(refreshed, now: now, envelopeID: envelopeID, neighbors: neighbors)
        }

        private func publishExistingSession(
            _ session: PlaybackSession,
            now: Date,
            envelopeID: String,
            neighbors: [ScenarioDevice]
        ) -> [AsyncTransportEnvelope] {
            apply(session, now: now)
            guard isConnected else { return [] }
            return neighbors.map {
                AsyncTransportEnvelope(id: envelopeID, session: session, origin: id, sender: id, receiver: $0)
            }
        }

        private func apply(_ session: PlaybackSession, now: Date) {
            if PlaybackSessionSyncPolicy.shouldApply(session, over: sharedSession, now: now) {
                sharedSession = session
            }
        }

        private func markProcessed(_ envelopeID: String) -> Bool {
            guard SyncDuplicatePolicy.shouldProcess(envelopeID: envelopeID, processedEnvelopeIDs: processedEnvelopeIDs) else {
                return false
            }
            processedEnvelopeIDs.insert(envelopeID)
            processedEnvelopeOrder.append(envelopeID)
            processedEnvelopeOrder = SyncDuplicatePolicy.trimmedEnvelopeIDOrder(processedEnvelopeOrder)
            processedEnvelopeIDs = Set(processedEnvelopeOrder)
            return true
        }

        private func copySession(
            _ session: PlaybackSession,
            revision: Int,
            updatedAt: Date,
            updatedByDeviceID: String
        ) -> PlaybackSession {
            PlaybackSession(
                id: session.id,
                revision: revision,
                queue: session.queue,
                currentIndex: session.currentIndex,
                position: session.estimatedPosition(at: updatedAt),
                isPlaying: session.isPlaying,
                volume: session.volume,
                outputDeviceID: session.outputDeviceID,
                updatedAt: updatedAt,
                updatedByDeviceID: updatedByDeviceID
            )
        }
    }

    private actor AsyncThreeDeviceSyncIntegrationHarness {
        private let nodes: [ScenarioDevice: AsyncSyncIntegrationNode]
        private let songs: [Song]
        private var pendingDeliveries: [AsyncTransportDelivery] = []
        private var generator: SeededGenerator
        private var tick = 0
        private var now = Date(timeIntervalSince1970: 1_790_000_000)
        private var revisions: [ScenarioDevice: Int]
        private var envelopeSequence = 0
        private let dropProbabilityPercent: Int
        private let duplicateProbabilityPercent: Int
        private let maxDelayTicks: Int

        init(
            songs: [Song],
            seed: UInt64,
            dropProbabilityPercent: Int = 8,
            duplicateProbabilityPercent: Int = 18,
            maxDelayTicks: Int = 7
        ) {
            self.songs = songs
            self.generator = SeededGenerator(seed: seed)
            self.dropProbabilityPercent = dropProbabilityPercent
            self.duplicateProbabilityPercent = duplicateProbabilityPercent
            self.maxDelayTicks = max(1, maxDelayTicks)
            self.nodes = Dictionary(uniqueKeysWithValues: ScenarioDevice.allCases.map {
                ($0, AsyncSyncIntegrationNode(id: $0))
            })
            self.revisions = Dictionary(uniqueKeysWithValues: ScenarioDevice.allCases.map { ($0, 0) })
        }

        var pendingEnvelopeCount: Int {
            pendingDeliveries.count
        }

        func session(on device: ScenarioDevice) async -> PlaybackSession? {
            await nodes[device]?.session()
        }

        func play(on device: ScenarioDevice) async {
            await publishLocalSession(from: device, isPlaying: true)
        }

        func pause(on device: ScenarioDevice) async {
            await publishLocalSession(from: device, isPlaying: false)
        }

        func seek(on device: ScenarioDevice, position: TimeInterval) async {
            let local = await nodes[device]?.session()
            await publishLocalSession(
                from: device,
                currentIndex: local?.currentIndex ?? 0,
                position: position,
                isPlaying: local?.isPlaying ?? true
            )
        }

        func next(on device: ScenarioDevice) async {
            let local = await nodes[device]?.session()
            let currentIndex = local?.currentIndex ?? 0
            await publishLocalSession(
                from: device,
                currentIndex: (currentIndex + 1) % max(songs.count, 1),
                position: 0,
                isPlaying: local?.isPlaying ?? true
            )
        }

        func previous(on device: ScenarioDevice) async {
            let local = await nodes[device]?.session()
            let currentIndex = local?.currentIndex ?? 0
            await publishLocalSession(
                from: device,
                currentIndex: (currentIndex - 1 + max(songs.count, 1)) % max(songs.count, 1),
                position: 0,
                isPlaying: local?.isPlaying ?? true
            )
        }

        func disconnect(_ device: ScenarioDevice) async {
            advanceTime()
            await nodes[device]?.setConnected(false)
            for observer in ScenarioDevice.allCases where observer != device {
                guard await isConnected(observer) else { continue }
                let envelopes = await nodes[observer]?.publishConnectivityPauseIfNeeded(
                    disconnectedDeviceID: device,
                    revision: nextRevision(for: observer),
                    now: now,
                    envelopeID: nextEnvelopeID(origin: observer),
                    neighbors: await neighbors(of: observer)
                ) ?? []
                schedule(envelopes)
            }
        }

        func reconnect(_ device: ScenarioDevice, reliableBootstrap: Bool = false) async {
            advanceTime()
            await nodes[device]?.setConnected(true)

            for neighbor in await neighbors(of: device) {
                await publishReconnectBootstrap(from: neighbor, reliable: reliableBootstrap)
            }
            await publishReconnectBootstrap(from: device, reliable: reliableBootstrap)
        }

        func reconnectAllReliably() async {
            for device in ScenarioDevice.allCases {
                await reconnect(device, reliableBootstrap: true)
            }
        }

        func runRandomScenario(steps: Int) async {
            for step in 0..<steps {
                let device = ScenarioDevice.allCases[generator.int(in: 0..<ScenarioDevice.allCases.count)]

                switch generator.int(in: 0..<13) {
                case 0:
                    await disconnect(device)
                case 1:
                    await reconnect(device)
                case 2:
                    await pause(on: device)
                case 3:
                    await seek(on: device, position: TimeInterval(generator.int(in: 0..<150)))
                case 4:
                    await next(on: device)
                case 5:
                    await previous(on: device)
                case 6:
                    await disconnect(device)
                    await reconnect(device)
                default:
                    await play(on: device)
                }

                if generator.bool(probabilityPercent: 42) {
                    duplicateRandomPendingDelivery()
                }

                if step.isMultiple(of: 3) || generator.bool(probabilityPercent: 40) {
                    await drain(limit: generator.int(in: 1..<16))
                }
            }
        }

        func drain(limit: Int = 10_000) async {
            var delivered = 0
            while !pendingDeliveries.isEmpty && delivered < limit {
                tick += max(1, generator.int(in: 0..<4))
                if pendingDeliveries.allSatisfy({ $0.dueTick > tick }) {
                    tick = pendingDeliveries.map(\.dueTick).min() ?? tick
                }

                let dueIndexes = pendingDeliveries.indices.filter { pendingDeliveries[$0].dueTick <= tick }
                guard !dueIndexes.isEmpty else { continue }

                let index = dueIndexes[generator.int(in: 0..<dueIndexes.count)]
                let delivery = pendingDeliveries.remove(at: index)
                await deliver(delivery.envelope, reliable: delivery.reliable)
                delivered += 1
            }
        }

        func convergenceFailures() async -> [String] {
            var failures: [String] = []
            for component in await connectedComponents() {
                var signatures: [(ScenarioDevice, SessionSignature?)] = []
                for device in component {
                    signatures.append((device, SessionSignature(await nodes[device]?.session())))
                }
                let uniqueSignatures = Set(signatures.map { String(describing: $0.1) })
                if uniqueSignatures.count > 1 {
                    failures.append("component \(component.map(\.rawValue).joined(separator: ",")) diverged: \(signatures.map { "\($0.0.rawValue)=\(String(describing: $0.1))" }.joined(separator: ", "))")
                }
            }
            return failures
        }

        func duplicateProcessingFailures() async -> [String] {
            var failures: [String] = []
            for device in ScenarioDevice.allCases {
                if let failure = await nodes[device]?.duplicateProcessingFailure() {
                    failures.append(failure)
                }
            }
            return failures
        }

        private func publishLocalSession(
            from device: ScenarioDevice,
            currentIndex: Int = 0,
            position: TimeInterval = 0,
            isPlaying: Bool
        ) async {
            advanceTime()
            let envelopes = await nodes[device]?.publishLocalSession(
                songs: songs,
                currentIndex: currentIndex,
                position: position,
                isPlaying: isPlaying,
                revision: nextRevision(for: device),
                now: now,
                envelopeID: nextEnvelopeID(origin: device),
                neighbors: await neighbors(of: device)
            ) ?? []
            schedule(envelopes)
        }

        private func publishReconnectBootstrap(from device: ScenarioDevice, reliable: Bool) async {
            let envelopes = await nodes[device]?.publishReconnectBootstrap(
                revision: nextRevision(for: device),
                now: now,
                envelopeID: nextEnvelopeID(origin: device),
                neighbors: await neighbors(of: device)
            ) ?? []
            schedule(envelopes, reliable: reliable)
        }

        private func deliver(_ envelope: AsyncTransportEnvelope, reliable: Bool) async {
            guard await canDeliver(envelope) else { return }
            let relayTargets = envelope.receiver == .iphone
                ? await neighbors(of: .iphone).filter { $0 != envelope.sender }
                : []
            let relayEnvelopes = await nodes[envelope.receiver]?.receive(
                envelope,
                now: now,
                relayTargets: relayTargets
            ) ?? []
            schedule(relayEnvelopes, reliable: reliable)
        }

        private func schedule(_ envelopes: [AsyncTransportEnvelope], reliable: Bool = false) {
            for envelope in envelopes {
                if !reliable && generator.bool(probabilityPercent: dropProbabilityPercent) {
                    continue
                }

                let duplicateCount = !reliable && generator.bool(probabilityPercent: duplicateProbabilityPercent) ? 2 : 1
                for _ in 0..<duplicateCount {
                    pendingDeliveries.append(AsyncTransportDelivery(
                        dueTick: tick + generator.int(in: 0..<maxDelayTicks),
                        envelope: envelope,
                        reliable: reliable
                    ))
                }
            }
        }

        private func duplicateRandomPendingDelivery() {
            guard !pendingDeliveries.isEmpty else { return }
            let delivery = pendingDeliveries[generator.int(in: 0..<pendingDeliveries.count)]
            pendingDeliveries.append(AsyncTransportDelivery(
                dueTick: tick + generator.int(in: 0..<maxDelayTicks),
                envelope: delivery.envelope,
                reliable: delivery.reliable
            ))
        }

        private func canDeliver(_ envelope: AsyncTransportEnvelope) async -> Bool {
            guard await isConnected(envelope.sender), await isConnected(envelope.receiver) else { return false }
            return await neighbors(of: envelope.sender).contains(envelope.receiver)
        }

        private func neighbors(of device: ScenarioDevice) async -> [ScenarioDevice] {
            guard await isConnected(device) else { return [] }
            switch device {
            case .mac:
                return await isConnected(.iphone) ? [.iphone] : []
            case .iphone:
                var neighbors: [ScenarioDevice] = []
                if await isConnected(.mac) {
                    neighbors.append(.mac)
                }
                if await isConnected(.watch) {
                    neighbors.append(.watch)
                }
                return neighbors
            case .watch:
                return await isConnected(.iphone) ? [.iphone] : []
            }
        }

        private func connectedComponents() async -> [[ScenarioDevice]] {
            var connectedDevices = Set<ScenarioDevice>()
            for device in ScenarioDevice.allCases where await isConnected(device) {
                connectedDevices.insert(device)
            }
            var unvisited = connectedDevices
            var components: [[ScenarioDevice]] = []

            while let start = unvisited.first {
                var stack = [start]
                var component: [ScenarioDevice] = []
                unvisited.remove(start)

                while let device = stack.popLast() {
                    component.append(device)
                    for neighbor in await neighbors(of: device) where unvisited.contains(neighbor) {
                        unvisited.remove(neighbor)
                        stack.append(neighbor)
                    }
                }

                components.append(component)
            }

            return components
        }

        private func isConnected(_ device: ScenarioDevice) async -> Bool {
            await nodes[device]?.connected() == true
        }

        private func advanceTime() {
            now = now.addingTimeInterval(0.25)
        }

        private func nextRevision(for device: ScenarioDevice) -> Int {
            let revision = (revisions[device] ?? 0) + 1
            revisions[device] = revision
            return revision
        }

        private func nextEnvelopeID(origin: ScenarioDevice) -> String {
            envelopeSequence += 1
            return "\(origin.rawValue)-async-\(envelopeSequence)"
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

    private func makeSong(id: String, title: String? = nil, artist: String = "Artist") -> Song {
        Song(
            id: id,
            title: title ?? "Track \(id)",
            album: "Album",
            albumId: "album-1",
            artist: artist,
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
