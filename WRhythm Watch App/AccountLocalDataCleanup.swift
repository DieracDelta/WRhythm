//
//  AccountLocalDataCleanup.swift
//  WRhythm Watch App
//

import Foundation

enum AccountLocalDataCleanupDomain: CaseIterable, Hashable, Sendable {
    case audioPlayback
    case prebufferCache
    case downloadsAndMetadata
    case libraryData
    case recentlyPlayed
    case searchResults
    case sharedPlaybackSession
    case imageCache
    case serverCapabilityCache
}

enum AccountLocalDataCleanupReason: Sendable {
    case logout
    case accountChanged
}

struct AccountIdentityPolicy: Sendable {
    static func shouldClearLocalData(
        existingBaseURL: String,
        existingUsername: String,
        incomingBaseURL: String,
        incomingUsername: String
    ) -> Bool {
        let existingBaseURL = normalizedBaseURL(existingBaseURL)
        let incomingBaseURL = normalizedBaseURL(incomingBaseURL)
        let existingUsername = existingUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingUsername = incomingUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !existingBaseURL.isEmpty, !existingUsername.isEmpty else { return false }
        return existingBaseURL != incomingBaseURL || existingUsername != incomingUsername
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct AccountLocalDataCleanupPlan: Sendable {
    static let accountBoundDomains: Set<AccountLocalDataCleanupDomain> = Set(AccountLocalDataCleanupDomain.allCases)
}

extension Notification.Name {
    static let wrhythmAccountLocalDataDidReset = Notification.Name("wrhythmAccountLocalDataDidReset")
}

@MainActor
enum AccountLocalDataCleaner {
    static func clearAll(reason: AccountLocalDataCleanupReason) {
        print("🧹 Clearing account-bound local data: \(reason)")

        AudioPlayer.shared.clearAccountBoundPlaybackState()
        DownloadManager.shared.deleteAllUserData()
        RecentlyPlayedStore.shared.clear()
        SearchResultDiskCache.clear()
        DeviceSyncManager.shared.clearAccountBoundPlaybackState()
        ImageCache.shared.clearAll()
        clearServerCapabilityCache()

        NotificationCenter.default.post(name: .wrhythmAccountLocalDataDidReset, object: nil)
    }

    private static func clearServerCapabilityCache() {
        let keys = [
            "server_supports_transcoding",
            "server_supports_sonic_similarity",
            "server_supports_audiomuse_alchemy"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
