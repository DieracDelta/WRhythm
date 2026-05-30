//
//  WRhythm_Watch_AppTests.swift
//  WRhythm Watch AppTests
//
//  Created by Justin Restivo on 12/23/25.
//

import Testing
import Foundation
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

    @Test func queuedDownloadsAreVisibleWhenNothingIsActivelyTransferring() {
        #expect(ActiveDownloadsPresentationPolicy.showsEmptyState(activeCount: 0, queuedCount: 0))
        #expect(ActiveDownloadsPresentationPolicy.showsEmptyState(activeCount: 0, queuedCount: 3) == false)
        #expect(ActiveDownloadsPresentationPolicy.headerTitle(activeCount: 0, queuedCount: 3) == "3 queued")
    }

    @Test func failedDownloadsAreVisibleWhenNothingIsActivelyTransferring() {
        #expect(ActiveDownloadsPresentationPolicy.showsEmptyState(activeCount: 0, queuedCount: 0, failedCount: 2) == false)
        #expect(ActiveDownloadsPresentationPolicy.headerTitle(activeCount: 0, queuedCount: 0, failedCount: 2) == "2 failed")
        #expect(ActiveDownloadsPresentationPolicy.headerSubtitle(activeCount: 0, queuedCount: 0, failedCount: 2) == nil)
    }

    @Test func asyncActionsAreDisabledWhileRunningOrUnavailable() {
        #expect(AsyncActionPresentationPolicy.isDisabled(isRunning: true))
        #expect(AsyncActionPresentationPolicy.isDisabled(isRunning: false) == false)
        #expect(AsyncActionPresentationPolicy.isDisabled(isRunning: false, isExternallyBusy: true))
        #expect(AsyncActionPresentationPolicy.isDisabled(isRunning: false, isUnavailable: true))
    }

    @Test func asyncActionsDimWhenDisabled() {
        #expect(AsyncActionPresentationPolicy.opacity(isDisabled: true) == 0.55)
        #expect(AsyncActionPresentationPolicy.opacity(isDisabled: false) == 1)
    }

    @Test func playlistGenerationCannotStartWhileGeneratingOrMissingSelection() {
        #expect(PlaylistGenerationActionPolicy.canStart(isGenerating: false, hasRequiredSelection: true))
        #expect(PlaylistGenerationActionPolicy.canStart(isGenerating: true, hasRequiredSelection: true) == false)
        #expect(PlaylistGenerationActionPolicy.canStart(isGenerating: false, hasRequiredSelection: false) == false)
    }

    @Test func metricKitPayloadFilenamesAreStableAndTagged() {
        let date = Date(timeIntervalSince1970: 1_771_000_000.123)
        let filename = MetricKitPayloadFilePolicy.filename(prefix: "metrics", receivedAt: date, index: 2)

        #expect(filename.hasPrefix("metrics-"))
        #expect(filename.hasSuffix("-2.json"))
        #expect(filename.contains(":") == false)
        #expect(filename.contains("/") == false)
    }

    @Test func metricKitPayloadFilenameSanitizerRemovesExportHostileCharacters() {
        let filename = MetricKitPayloadFilePolicy.sanitizedFilename("metrics-2026-05-29T23:50:31.891Z-0.json")

        #expect(filename == "metrics-2026-05-29T23-50-31.891Z-0.json")
    }

}
