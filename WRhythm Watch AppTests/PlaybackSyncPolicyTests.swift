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
        song: Song? = nil,
        queue: [Song]? = nil,
        currentTime: TimeInterval = 10,
        updatedAt: Date
    ) -> PlaybackSnapshot {
        let resolvedSong = song ?? makeSong(id: "song-1")
        let resolvedQueue = queue ?? [resolvedSong]

        return PlaybackSnapshot(
            id: "device-1",
            deviceName: "Mac",
            platform: "Mac",
            song: resolvedSong,
            isPlaying: true,
            isBuffering: false,
            prebufferedTrackCount: 3,
            volume: 0.8,
            currentTime: currentTime,
            duration: 180,
            queue: resolvedQueue,
            currentIndex: 0,
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
