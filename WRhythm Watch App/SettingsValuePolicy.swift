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
