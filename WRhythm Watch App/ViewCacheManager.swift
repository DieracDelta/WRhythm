//
//  ViewCacheManager.swift
//  WRhythm Watch App
//
//  Created by Claude Code
//

import Foundation
import SwiftUI

enum CachedView: String, CaseIterable {
    case artists = "ArtistsView"
    case albums = "AlbumsView"
    case playlists = "PlaylistsView"
    case tracks = "TracksView"
    case favourites = "FavouritesView"
    case spontaneous = "SpontaneousMusicView"
    case nowPlaying = "NowPlayingView"
    case settings = "SettingsView"
}

class ViewCacheManager {
    static let shared = ViewCacheManager()

    // Track view access order (most recent first)
    private var viewAccessOrder: [CachedView] = []

    private init() {}

    func recordViewAccess(_ view: CachedView) {
        // Remove if already in list
        viewAccessOrder.removeAll { $0 == view }

        // Add to front (most recent)
        viewAccessOrder.insert(view, at: 0)

        // Only enforce limit if battery saver is active
        if BatterySaverManager.shared.isActive {
            enforceLimit()
        }
    }

    func shouldKeepCacheFor(_ view: CachedView) -> Bool {
        // If battery saver disabled, keep everything
        if !BatterySaverManager.shared.isActive {
            return true
        }

        // Keep if in recent N views
        let maxViews = BatterySaverManager.shared.maxCachedViews
        let recentViews = Array(viewAccessOrder.prefix(maxViews))
        return recentViews.contains(view)
    }

    private func enforceLimit() {
        let maxViews = BatterySaverManager.shared.maxCachedViews

        if viewAccessOrder.count > maxViews {
            let viewsToEvict = Array(viewAccessOrder.dropFirst(maxViews))

            for view in viewsToEvict {
                print("🗑️ Evicting view cache: \(view.rawValue)")
                NotificationCenter.default.post(
                    name: .evictViewCache,
                    object: nil,
                    userInfo: ["view": view]
                )
            }

            // Keep only recent views in the list
            viewAccessOrder = Array(viewAccessOrder.prefix(maxViews))
        }
    }

    func clearAllCaches() {
        print("🗑️ Clearing all view caches")
        viewAccessOrder.removeAll()
        NotificationCenter.default.post(name: .clearAllViewCaches, object: nil)
    }
}

extension Notification.Name {
    static let evictViewCache = Notification.Name("evictViewCache")
    static let clearAllViewCaches = Notification.Name("clearAllViewCaches")
}
