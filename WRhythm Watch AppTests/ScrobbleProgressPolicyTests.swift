//
//  ScrobbleProgressPolicyTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing
@testable import WRhythm_Watch_App

@MainActor
struct ScrobbleProgressPolicyTests {
    @Test func playbackStartPublishesNowPlayingEvent() {
        var tracker = ScrobbleProgressTracker()

        let event = tracker.start(songID: "song-1", currentTime: 0, now: Date())

        #expect(event == .nowPlaying(songID: "song-1"))
        #expect(tracker.submissionSent == false)
    }

    @Test func scrobbleDispatchRequiresEnabledOnlineCredentialedPlaybackOwner() {
        #expect(ScrobbleDispatchPolicy.shouldTrack(
            scrobblingEnabled: true,
            offlineMode: false,
            hasCredentials: true,
            isPlaybackOwner: true
        ) == true)
        #expect(ScrobbleDispatchPolicy.shouldTrack(
            scrobblingEnabled: false,
            offlineMode: false,
            hasCredentials: true,
            isPlaybackOwner: true
        ) == false)
        #expect(ScrobbleDispatchPolicy.shouldTrack(
            scrobblingEnabled: true,
            offlineMode: true,
            hasCredentials: true,
            isPlaybackOwner: true
        ) == false)
        #expect(ScrobbleDispatchPolicy.shouldTrack(
            scrobblingEnabled: true,
            offlineMode: false,
            hasCredentials: false,
            isPlaybackOwner: true
        ) == false)
        #expect(ScrobbleDispatchPolicy.shouldTrack(
            scrobblingEnabled: true,
            offlineMode: false,
            hasCredentials: true,
            isPlaybackOwner: false
        ) == false)
    }

    @Test func submitsOnceAfterHalfOfShortTrackWasActuallyHeard() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)

        #expect(tracker.update(songID: "song-1", currentTime: 29, duration: 60, isPlaying: true, now: start.addingTimeInterval(29)) == nil)
        #expect(tracker.update(songID: "song-1", currentTime: 30, duration: 60, isPlaying: true, now: start.addingTimeInterval(30)) == .submission(songID: "song-1"))
        #expect(tracker.update(songID: "song-1", currentTime: 45, duration: 60, isPlaying: true, now: start.addingTimeInterval(45)) == nil)
    }

    @Test func submissionFailureDoesNotCreateDuplicateSubmissionEvents() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)

        let firstSubmission = tracker.update(
            songID: "song-1",
            currentTime: 30,
            duration: 60,
            isPlaying: true,
            now: start.addingTimeInterval(30)
        )
        let wouldBeRetryTick = tracker.update(
            songID: "song-1",
            currentTime: 45,
            duration: 60,
            isPlaying: true,
            now: start.addingTimeInterval(45)
        )

        #expect(firstSubmission == .submission(songID: "song-1"))
        #expect(wouldBeRetryTick == nil)
        #expect(tracker.submissionSent == true)
    }

    @Test func longTrackSubmitsAfterFourMinutesInsteadOfHalfDuration() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)

        #expect(tracker.update(songID: "song-1", currentTime: 239, duration: 1000, isPlaying: true, now: start.addingTimeInterval(239)) == nil)
        #expect(tracker.update(songID: "song-1", currentTime: 240, duration: 1000, isPlaying: true, now: start.addingTimeInterval(240)) == .submission(songID: "song-1"))
    }

    @Test func seekForwardDoesNotCountSkippedAudioAsListened() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)

        #expect(tracker.update(songID: "song-1", currentTime: 10, duration: 120, isPlaying: true, now: start.addingTimeInterval(10)) == nil)
        #expect(tracker.update(songID: "song-1", currentTime: 80, duration: 120, isPlaying: true, now: start.addingTimeInterval(11)) == nil)
        #expect(tracker.listenedTime == 11)
    }

    @Test func pausedGapDoesNotCountAsListenedTime() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)

        #expect(tracker.update(songID: "song-1", currentTime: 10, duration: 120, isPlaying: true, now: start.addingTimeInterval(10)) == nil)
        #expect(tracker.update(songID: "song-1", currentTime: 10, duration: 120, isPlaying: false, now: start.addingTimeInterval(70)) == nil)
        #expect(tracker.update(songID: "song-1", currentTime: 11, duration: 120, isPlaying: true, now: start.addingTimeInterval(71)) == nil)
        #expect(tracker.listenedTime == 11)
    }

    @Test func stalledPlaybackPositionDoesNotCountBufferingWallTime() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)

        #expect(tracker.update(songID: "song-1", currentTime: 10, duration: 120, isPlaying: true, now: start.addingTimeInterval(10)) == nil)
        #expect(tracker.update(songID: "song-1", currentTime: 10, duration: 120, isPlaying: true, now: start.addingTimeInterval(70)) == nil)
        #expect(tracker.listenedTime == 10)
    }

    @Test func unknownDurationUsesFourMinuteThreshold() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)

        #expect(ScrobbleProgressTracker.submissionThreshold(for: 0) == 240)
        #expect(ScrobbleProgressTracker.submissionThreshold(for: .infinity) == 240)
        #expect(tracker.update(songID: "song-1", currentTime: 239, duration: 0, isPlaying: true, now: start.addingTimeInterval(239)) == nil)
        #expect(tracker.update(songID: "song-1", currentTime: 240, duration: 0, isPlaying: true, now: start.addingTimeInterval(240)) == .submission(songID: "song-1"))
    }

    @Test func restartingSameSongCreatesNewNowPlayingWindowAndSubmissionState() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)
        #expect(tracker.update(songID: "song-1", currentTime: 30, duration: 60, isPlaying: true, now: start.addingTimeInterval(30)) == .submission(songID: "song-1"))

        #expect(tracker.start(songID: "song-1", currentTime: 0, now: start.addingTimeInterval(40)) == .nowPlaying(songID: "song-1"))
        #expect(tracker.submissionSent == false)
        #expect(tracker.listenedTime == 0)
        #expect(tracker.update(songID: "song-1", currentTime: 30, duration: 60, isPlaying: true, now: start.addingTimeInterval(70)) == .submission(songID: "song-1"))
    }

    @Test func changingSongsResetsSubmissionState() {
        var tracker = ScrobbleProgressTracker()
        let start = Date()
        _ = tracker.start(songID: "song-1", currentTime: 0, now: start)
        #expect(tracker.update(songID: "song-1", currentTime: 30, duration: 60, isPlaying: true, now: start.addingTimeInterval(30)) == .submission(songID: "song-1"))

        #expect(tracker.start(songID: "song-2", currentTime: 0, now: start.addingTimeInterval(40)) == .nowPlaying(songID: "song-2"))
        #expect(tracker.submissionSent == false)
        #expect(tracker.listenedTime == 0)
    }
}
