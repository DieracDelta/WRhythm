//
//  WRhythm_Watch_AppTests.swift
//  WRhythm Watch AppTests
//
//  Created by Justin Restivo on 12/23/25.
//

import Testing
@testable import WRhythm_Watch_App

@MainActor
struct WRhythm_Watch_AppTests {

    @Test func testDownloadManagerInitialization() async throws {
        let downloadManager = DownloadManager.shared
        let downloadedCount = downloadManager.downloadedSongs.count
        let maxConcurrentDownloads = downloadManager.maxConcurrentDownloads

        #expect(downloadedCount >= 0)
        #expect(maxConcurrentDownloads > 0)
    }

    @Test func testAudioPlayerInitialization() async throws {
        let player = AudioPlayer.shared
        let volume = player.volume
        let repeatMode = player.repeatMode

        #expect(volume >= 0 && volume <= 1)
        #expect([AudioPlayer.RepeatMode.off, .all, .one].contains(repeatMode))
    }

    @Test func testDownloadCountCalculation() async throws {
        let downloadManager = DownloadManager.shared
        let totalPending = downloadManager.getTotalPendingDownloads()
        let active = downloadManager.getActiveDownloadCount()
        let queued = downloadManager.getQueuedDownloadCount()

        #expect(totalPending == active + queued)
    }

    @Test func testSessionCountTracking() async throws {
        let downloadManager = DownloadManager.shared
        let initialTotal = downloadManager.sessionTotalCount
        let initialCompleted = downloadManager.sessionCompletedCount

        #expect(initialCompleted <= initialTotal)
    }

}
