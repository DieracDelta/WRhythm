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
}
