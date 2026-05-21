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

    @Test func smallPlaybackClockDriftDoesNotRepublishNowPlaying() {
        let now = Date()
        let current = makeSnapshot(currentTime: 42, updatedAt: now)
        let drift = makeSnapshot(currentTime: 43.5, updatedAt: now.addingTimeInterval(0.5))

        #expect(PlaybackSyncPolicy.shouldPublishRemotePlayback(drift, current: current) == false)
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
        (.next, false),
        (.previous, false),
        (.playQueue, false),
        (.enqueue, false),
        (.syncQueue, false),
        (.stop, false)
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

    @Test func volumeCommandUsesToleranceForAcknowledgment() {
        let now = Date()
        let matchingVolume = makeSnapshot(volume: 0.51, updatedAt: now)
        let differentVolume = makeSnapshot(volume: 0.62, updatedAt: now)

        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .setVolume, expectedVolume: 0.5, by: matchingVolume) == true)
        #expect(PlaybackCommandSyncPolicy.isAcknowledged(action: .setVolume, expectedVolume: 0.5, by: differentVolume) == false)
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
