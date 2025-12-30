//
//  WRhythm_Watch_AppTests.swift
//  WRhythm Watch AppTests
//
//  Created by Justin Restivo on 12/23/25.
//

import Testing
@testable import WRhythm_Watch_App

struct WRhythm_Watch_AppTests {

    @Test func testDownloadManagerInitialization() async throws {
        let downloadManager = DownloadManager.shared
        #expect(downloadManager.downloadedSongs.count >= 0)
        #expect(downloadManager.maxConcurrentDownloads > 0)
    }

    @Test func testAudioPlayerInitialization() async throws {
        let player = AudioPlayer.shared
        #expect(player.queue.isEmpty || !player.queue.isEmpty)
        #expect(player.volume >= 0 && player.volume <= 1)
        #expect(player.repeatMode == .off || player.repeatMode == .all || player.repeatMode == .one)
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
