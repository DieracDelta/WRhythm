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
    static let userDefaultsKey = "songRenderWindowLimit"
    static let unlimitedSentinel = 0
    static let minimumLimit = 20
    static let defaultLimit = 250

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
}
