//
//  WRhythmApp.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

@main
struct WRhythm_Watch_AppApp: App {
    @StateObject private var libraryDataManager = LibraryDataManager()
    @StateObject private var deviceSyncManager = DeviceSyncManager.shared
    @AppStorage("darkModeEnabled") private var darkModeEnabled = true

    init() {
        WRhythmFont.registerIfNeeded()
#if DEBUG
        Task { @MainActor in
            SyncLiveHarness.shared.startIfNeeded()
        }
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryDataManager)
                .environmentObject(deviceSyncManager)
                .tint(WRhythmTheme.accent)
                .accentColor(WRhythmTheme.accent)
                .preferredColorScheme(darkModeEnabled ? .dark : .light)
#if DEBUG
                .task {
                    SyncLiveHarness.shared.startIfNeeded()
                }
                .onOpenURL { url in
                    SyncLiveHarness.shared.handle(url)
                }
#endif
        }
#if os(macOS)
        .commands {
            PlaybackKeyboardCommands()
        }
#endif
    }
}

#if os(macOS)
struct PlaybackKeyboardCommands: Commands {
    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play/Pause") {
                PlaybackKeyboardActions.togglePlayback()
            }
            .keyboardShortcut("p", modifiers: [])

            Button("Favorite Current Song") {
                PlaybackKeyboardActions.toggleFavoriteCurrentSong()
            }
            .keyboardShortcut("f", modifiers: [])

            Divider()

            Button("Previous Track") {
                PlaybackKeyboardActions.previousTrack()
            }
            .keyboardShortcut("h", modifiers: [])

            Button("Volume Down") {
                PlaybackKeyboardActions.adjustVolume(by: -0.05)
            }
            .keyboardShortcut("j", modifiers: [])

            Button("Volume Up") {
                PlaybackKeyboardActions.adjustVolume(by: 0.05)
            }
            .keyboardShortcut("k", modifiers: [])

            Button("Next Track") {
                PlaybackKeyboardActions.nextTrack()
            }
            .keyboardShortcut("l", modifiers: [])
        }
    }
}
#endif

enum PlaybackKeyboardActions {
    @MainActor
    static func togglePlayback() {
        DeviceSyncManager.shared.toggleSelectedPlaybackTarget()
    }

    @MainActor
    static func setPlaying(_ isPlaying: Bool) {
        let manager = DeviceSyncManager.shared
        manager.validateSelectedPlaybackTarget()
        manager.setPlaying(isPlaying, targetDeviceID: manager.validSelectedPlaybackTargetID)
    }

    @MainActor
    static func setLocalPlaying(_ isPlaying: Bool) {
        let manager = DeviceSyncManager.shared
        manager.setPlaying(isPlaying, targetDeviceID: manager.localPlaybackTargetID)
    }

    @MainActor
    static func toggleLocalPlayback() {
        let manager = DeviceSyncManager.shared
        manager.setPlaying(!AudioPlayer.shared.isPlaying, targetDeviceID: manager.localPlaybackTargetID)
    }

    @MainActor
    static func toggleFavoriteCurrentSong() {
        guard let song = activeSongForSelectedTarget() else { return }
        TrackActions.toggleFavorite(song)
    }

    @MainActor
    static func previousTrack() {
        let manager = DeviceSyncManager.shared
        if isSelectedTargetLocal {
            AudioPlayer.shared.previous()
        } else {
            manager.sendPrevious(targetDeviceID: manager.validSelectedPlaybackTargetID)
        }
    }

    @MainActor
    static func nextTrack() {
        let manager = DeviceSyncManager.shared
        if isSelectedTargetLocal {
            AudioPlayer.shared.next()
        } else {
            manager.sendNext(targetDeviceID: manager.validSelectedPlaybackTargetID)
        }
    }

    @MainActor
    static func adjustVolume(by delta: Double) {
        let manager = DeviceSyncManager.shared
        manager.validateSelectedPlaybackTarget()
        let targetID = manager.validSelectedPlaybackTargetID
        let volume = min(max(currentVolume(for: targetID) + delta, 0), 1)
        manager.setVolume(volume, targetDeviceID: targetID)
    }

    @MainActor
    private static var isSelectedTargetLocal: Bool {
        let manager = DeviceSyncManager.shared
        manager.validateSelectedPlaybackTarget()
        return manager.availablePlaybackTargets
            .first(where: { $0.id == manager.validSelectedPlaybackTargetID })?
            .isLocal ?? true
    }

    @MainActor
    private static func currentVolume(for targetID: String) -> Double {
        let manager = DeviceSyncManager.shared
        if manager.availablePlaybackTargets.first(where: { $0.id == targetID })?.isLocal ?? true {
            return AudioPlayer.shared.volume
        }
        if let sharedSession = manager.sharedSession,
           sharedSession.outputDeviceID == targetID,
           let volume = sharedSession.volume {
            return volume
        }
        return AudioPlayer.shared.volume
    }

    @MainActor
    private static func activeSongForSelectedTarget() -> Song? {
        let manager = DeviceSyncManager.shared
        manager.validateSelectedPlaybackTarget()
        let targetID = manager.validSelectedPlaybackTargetID

        if manager.availablePlaybackTargets.first(where: { $0.id == targetID })?.isLocal ?? true {
            return AudioPlayer.shared.currentSong
        }
        if let sharedPlayback = manager.activeSharedPlayback,
           sharedPlayback.id == targetID {
            return sharedPlayback.song
        }
        return AudioPlayer.shared.currentSong ?? manager.activeSharedPlayback?.song
    }
}
