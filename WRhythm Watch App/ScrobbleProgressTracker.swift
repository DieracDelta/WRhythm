//
//  ScrobbleProgressTracker.swift
//  WRhythm Watch App
//

import Foundation

enum ScrobblePlaybackEvent: Equatable, Sendable {
    case nowPlaying(songID: String)
    case submission(songID: String)
}

struct ScrobbleProgressTracker: Sendable {
    private(set) var songID: String?
    private(set) var listenedTime: TimeInterval = 0
    private(set) var submissionSent = false

    private var lastPosition: TimeInterval?
    private var lastTickDate: Date?

    mutating func start(songID: String, currentTime: TimeInterval, now: Date) -> ScrobblePlaybackEvent {
        self.songID = songID
        self.listenedTime = 0
        self.submissionSent = false
        self.lastPosition = max(0, currentTime)
        self.lastTickDate = now
        return .nowPlaying(songID: songID)
    }

    mutating func reset() {
        songID = nil
        listenedTime = 0
        submissionSent = false
        lastPosition = nil
        lastTickDate = nil
    }

    mutating func update(
        songID: String,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        now: Date
    ) -> ScrobblePlaybackEvent? {
        guard self.songID == songID else {
            _ = start(songID: songID, currentTime: currentTime, now: now)
            return nil
        }

        let position = max(0, currentTime)
        defer {
            lastPosition = position
            lastTickDate = now
        }

        guard isPlaying else { return nil }
        guard let lastPosition, let lastTickDate else { return nil }

        let wallDelta = max(0, now.timeIntervalSince(lastTickDate))
        let positionDelta = max(0, position - lastPosition)
        let listenedDelta = min(wallDelta, positionDelta)
        listenedTime += listenedDelta

        guard !submissionSent else { return nil }
        guard listenedTime >= Self.submissionThreshold(for: duration) else { return nil }

        submissionSent = true
        return .submission(songID: songID)
    }

    static func submissionThreshold(for duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 240 }
        return min(duration * 0.5, 240)
    }
}

struct ScrobbleDispatchPolicy: Sendable {
    static func shouldTrack(
        scrobblingEnabled: Bool,
        offlineMode: Bool,
        hasCredentials: Bool,
        isPlaybackOwner: Bool
    ) -> Bool {
        scrobblingEnabled && !offlineMode && hasCredentials && isPlaybackOwner
    }
}
