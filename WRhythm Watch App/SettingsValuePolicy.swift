import Foundation

struct PrebufferSettingsPolicy: Sendable {
    static let minAheadCount = 1
    static let minPreviousCount = 0
    static let maxRetainedTrackCount = 100

    static func sanitizeAheadCount(_ value: Int) -> Int {
        min(max(value, minAheadCount), maxRetainedTrackCount)
    }

    static func sanitizePreviousCount(_ value: Int) -> Int {
        min(max(value, minPreviousCount), maxRetainedTrackCount)
    }
}

struct ConcurrentDownloadSettingsPolicy: Sendable {
    static let unlimitedSentinel = 999
    static let sliderUnlimitedValue = 17

    static func sliderValue(for maxConcurrentDownloads: Int) -> Double {
        maxConcurrentDownloads == unlimitedSentinel ? Double(sliderUnlimitedValue) : Double(maxConcurrentDownloads)
    }

    static func maxConcurrentDownloads(forSliderValue value: Double) -> Int {
        value >= Double(sliderUnlimitedValue) ? unlimitedSentinel : Int(value)
    }
}

struct SongRenderWindowPolicy: Sendable {
    enum RenderMode: Sendable {
        case slidingWindow
        case fullRangeLoaded
    }

    struct RenderSlot: Identifiable, Equatable, Sendable {
        let index: Int
        let isLoaded: Bool

        var id: Int { index }
    }

    static let userDefaultsKey = "songRenderWindowLimit"
    static let unlimitedSentinel = 0
    static let minimumLimit = 20
    static let defaultLimit = 250
    static let hiddenSpacerSentinelRows = 1
    static let defaultPageSize = 25
    static let defaultRetainedPageRadius = 1

    static func sanitizeLimit(_ value: Int) -> Int {
        value == unlimitedSentinel ? unlimitedSentinel : max(value, minimumLimit)
    }

    static func effectiveLimit(_ storedValue: Int) -> Int? {
        let sanitized = sanitizeLimit(storedValue)
        return sanitized == unlimitedSentinel ? nil : sanitized
    }

    static func displayText(for storedValue: Int) -> String {
        guard let limit = effectiveLimit(storedValue) else { return "Unlimited" }
        return "\(limit)"
    }

    static func visibleRange(totalCount: Int, anchorIndex: Int, storedLimit: Int) -> Range<Int> {
        guard totalCount > 0 else { return 0..<0 }
        guard let limit = effectiveLimit(storedLimit), totalCount > limit else {
            return 0..<totalCount
        }

        let clampedAnchor = min(max(anchorIndex, 0), totalCount - 1)
        let proposedLowerBound = clampedAnchor - (limit / 2)
        let lowerBound = min(max(proposedLowerBound, 0), totalCount - limit)
        return lowerBound..<(lowerBound + limit)
    }

    static func renderRange(
        totalCount: Int,
        anchorIndex: Int,
        storedLimit: Int,
        renderMode: RenderMode = .slidingWindow
    ) -> Range<Int> {
        switch renderMode {
        case .slidingWindow:
            return visibleRange(totalCount: totalCount, anchorIndex: anchorIndex, storedLimit: storedLimit)
        case .fullRangeLoaded:
            return totalCount > 0 ? 0..<totalCount : 0..<0
        }
    }

    static func hiddenSpacerRows(hiddenRows: Int, storedLimit: Int) -> Int {
        guard hiddenRows > 0, effectiveLimit(storedLimit) != nil else { return 0 }
        return min(hiddenRows, hiddenSpacerSentinelRows)
    }

    static func resetToken(scope: String, sortIdentifier: String, query: String = "") -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(scope)|\(sortIdentifier)|\(normalizedQuery)"
    }

    static func trackSearchResetToken(mode: String, query: String) -> String {
        resetToken(scope: "tracks:\(mode)", sortIdentifier: "title", query: query)
    }

    static func searchResultGroupResetToken(mode: String, kind: String, query: String) -> String {
        resetToken(scope: "search:\(mode):\(kind)", sortIdentifier: "title", query: query)
    }

    static func artistAlbumResetToken(artistId: String, mode: String) -> String {
        resetToken(scope: "artist:\(artistId):albums", sortIdentifier: mode)
    }

    static func playlistGenQueueResetToken(songIds: [String]) -> String {
        resetToken(scope: "playlist-gen:queue", sortIdentifier: songIds.joined(separator: ","))
    }

    static func downloadedRadioPlaylistsResetToken(playlistIds: [String]) -> String {
        resetToken(scope: "playlist-gen:downloaded", sortIdentifier: playlistIds.joined(separator: ","))
    }

    static func availableTracksResetToken(songIds: [String]) -> String {
        resetToken(scope: "available-tracks:ready", sortIdentifier: songIds.joined(separator: ","))
    }

    static func prebufferDownloadStatusesResetToken(statusIds: [String]) -> String {
        resetToken(scope: "available-tracks:downloading", sortIdentifier: statusIds.joined(separator: ","))
    }

    static func downloadedAlbumSectionsResetToken(albumSectionIds: [String], query: String) -> String {
        resetToken(scope: "downloads:albums", sortIdentifier: albumSectionIds.joined(separator: ","), query: query)
    }

    static func downloadedAlbumSongsResetToken(albumSectionId: String, songIds: [String]) -> String {
        resetToken(scope: "downloads:album:\(albumSectionId)", sortIdentifier: songIds.joined(separator: ","))
    }

    static func activeDownloadIdsResetToken(songIds: [String]) -> String {
        resetToken(scope: "downloads:active", sortIdentifier: songIds.sorted().joined(separator: ","))
    }

    static func queuedDownloadIdsResetToken(songIds: [String]) -> String {
        resetToken(scope: "downloads:queued", sortIdentifier: songIds.joined(separator: ","))
    }

    static func failedDownloadIdsResetToken(songIds: [String]) -> String {
        resetToken(scope: "downloads:failed", sortIdentifier: songIds.joined(separator: ","))
    }

    static func sidebarQueueResetToken(songIds: [String], currentIndex: Int) -> String {
        resetToken(scope: "mac-sidebar:queue:\(currentIndex)", sortIdentifier: songIds.joined(separator: ","))
    }

    static func clampedAnchorIndexHint(_ hint: Int, totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        return min(max(hint, 0), totalCount - 1)
    }

    static func anchorAfterTopSpacerAppears(visibleRange: Range<Int>, storedLimit: Int) -> Int {
        guard let limit = effectiveLimit(storedLimit), visibleRange.lowerBound > 0 else { return 0 }
        return max(0, visibleRange.lowerBound - max(1, limit / 2))
    }

    static func anchorAfterBottomSpacerAppears(visibleRange: Range<Int>, totalCount: Int, storedLimit: Int) -> Int {
        guard let limit = effectiveLimit(storedLimit), visibleRange.upperBound < totalCount else {
            return max(0, totalCount - 1)
        }
        return min(max(0, totalCount - 1), visibleRange.upperBound + max(1, limit / 2))
    }

    static func pageIndex(forRow row: Int, pageSize: Int) -> Int {
        guard pageSize > 0 else { return 0 }
        return max(0, row) / pageSize
    }

    static func pageRange(pageIndex: Int, totalCount: Int, pageSize: Int) -> Range<Int> {
        guard totalCount > 0, pageSize > 0 else { return 0..<0 }
        let lowerBound = min(max(0, pageIndex * pageSize), totalCount)
        let upperBound = min(totalCount, lowerBound + pageSize)
        return lowerBound..<upperBound
    }

    static func visiblePageIndices(
        totalCount: Int,
        anchorIndex: Int,
        storedLimit: Int,
        pageSize: Int = defaultPageSize,
        retainedPageRadius: Int = defaultRetainedPageRadius
    ) -> Set<Int> {
        guard totalCount > 0, pageSize > 0 else { return [] }
        let range = visibleRange(totalCount: totalCount, anchorIndex: anchorIndex, storedLimit: storedLimit)
        guard !range.isEmpty else { return [] }

        let firstPage = pageIndex(forRow: range.lowerBound, pageSize: pageSize)
        let lastPage = pageIndex(forRow: max(range.lowerBound, range.upperBound - 1), pageSize: pageSize)
        return Set(firstPage...lastPage)
    }

    static func retainedPageIndices(
        visiblePageIndices: Set<Int>,
        totalCount: Int,
        pageSize: Int = defaultPageSize,
        retainedPageRadius: Int = defaultRetainedPageRadius
    ) -> Set<Int> {
        guard totalCount > 0, pageSize > 0, !visiblePageIndices.isEmpty else { return [] }

        let maxPage = pageIndex(forRow: totalCount - 1, pageSize: pageSize)
        let radius = max(0, retainedPageRadius)
        var retained: Set<Int> = []

        for page in visiblePageIndices {
            let lowerBound = max(0, page - radius)
            let upperBound = min(maxPage, page + radius)
            retained.formUnion(lowerBound...upperBound)
        }

        return retained
    }

    static func pagesToLoad(
        totalCount: Int,
        anchorIndex: Int,
        storedLimit: Int,
        pageSize: Int = defaultPageSize,
        loadedPageIndices: Set<Int>
    ) -> [Int] {
        let visiblePages = visiblePageIndices(
            totalCount: totalCount,
            anchorIndex: anchorIndex,
            storedLimit: storedLimit,
            pageSize: pageSize
        )
        return visiblePages.subtracting(loadedPageIndices).sorted()
    }

    static func loadedPageIndicesAfterEviction(
        loadedPageIndices: Set<Int>,
        totalCount: Int,
        anchorIndex: Int,
        storedLimit: Int,
        pageSize: Int = defaultPageSize,
        retainedPageRadius: Int = defaultRetainedPageRadius
    ) -> Set<Int> {
        let visiblePages = visiblePageIndices(
            totalCount: totalCount,
            anchorIndex: anchorIndex,
            storedLimit: storedLimit,
            pageSize: pageSize,
            retainedPageRadius: retainedPageRadius
        )
        let retainedPages = retainedPageIndices(
            visiblePageIndices: visiblePages,
            totalCount: totalCount,
            pageSize: pageSize,
            retainedPageRadius: retainedPageRadius
        )
        return loadedPageIndices.intersection(retainedPages)
    }

    static func renderSlots(
        totalCount: Int,
        anchorIndex: Int,
        storedLimit: Int,
        pageSize: Int = defaultPageSize,
        loadedPageIndices: Set<Int>,
        renderMode: RenderMode = .slidingWindow
    ) -> [RenderSlot] {
        let range = renderRange(
            totalCount: totalCount,
            anchorIndex: anchorIndex,
            storedLimit: storedLimit,
            renderMode: renderMode
        )
        guard !range.isEmpty else { return [] }

        return range.map { index in
            switch renderMode {
            case .slidingWindow:
                RenderSlot(index: index, isLoaded: loadedPageIndices.contains(pageIndex(forRow: index, pageSize: pageSize)))
            case .fullRangeLoaded:
                RenderSlot(index: index, isLoaded: true)
            }
        }
    }
}
