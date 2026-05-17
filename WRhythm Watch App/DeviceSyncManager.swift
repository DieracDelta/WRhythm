//
//  DeviceSyncManager.swift
//  WRhythm
//
//  Coordinates optional playback and credential sync across nearby WRhythm devices.
//

import Combine
import Foundation

#if os(iOS) || os(watchOS)
import WatchConnectivity
#endif

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

#if os(iOS) || os(macOS)
import MultipeerConnectivity
#endif

struct SyncedCredentials: Codable {
    let baseURL: String
    let username: String
    let password: String
}

struct PlaybackSnapshot: Codable, Identifiable {
    let id: String
    let deviceName: String
    let platform: String
    let song: Song?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let queue: [Song]
    let currentIndex: Int
    let updatedAt: Date
}

struct PlaybackSession: Codable, Identifiable {
    let id: String
    let revision: Int
    let queue: [Song]
    let currentIndex: Int
    let position: TimeInterval
    let isPlaying: Bool
    let outputDeviceID: String
    let updatedAt: Date
    let updatedByDeviceID: String

    var currentSong: Song? {
        guard !queue.isEmpty, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var estimatedPosition: TimeInterval {
        let basePosition = position.isFinite ? position : 0
        let advancedPosition = isPlaying ? basePosition + max(0, Date().timeIntervalSince(updatedAt)) : basePosition
        let clampedPosition = max(0, advancedPosition)

        guard let duration = currentSong?.duration, duration > 0 else {
            return clampedPosition
        }
        return min(clampedPosition, TimeInterval(duration))
    }
}

extension PlaybackSnapshot {
    var estimatedCurrentTime: TimeInterval {
        let baseTime = currentTime.isFinite ? currentTime : 0
        let advancedTime = isPlaying ? baseTime + max(0, Date().timeIntervalSince(updatedAt)) : baseTime
        let clampedTime = max(0, advancedTime)

        guard duration.isFinite, duration > 0 else {
            return clampedTime
        }
        return min(clampedTime, duration)
    }
}

struct PlaybackTargetDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: String
    let isLocal: Bool

    var displayName: String {
        isLocal ? "This \(platform)" : "\(name) (\(platform))"
    }

    var iconName: String {
        switch platform {
        case "Mac": return "desktopcomputer"
        case "iPhone": return "iphone"
        case "Apple Watch": return "applewatch"
        default: return "speaker.wave.2"
        }
    }
}

private struct SyncPeerInfo: Codable {
    let id: String
    let name: String
    let platform: String
    let syncModeEnabled: Bool
    let credentialSyncEnabled: Bool
    let hasCredentials: Bool
}

private struct PlaybackCommand: Codable {
    enum Action: String, Codable {
        case play
        case pause
        case toggle
        case next
        case previous
        case seek
        case playQueue
        case enqueue
        case syncQueue
        case stop
    }

    let action: Action
    let commandID: String?
    let songs: [Song]?
    let startingIndex: Int?
    let time: TimeInterval?

    init(action: Action, commandID: String? = nil, songs: [Song]?, startingIndex: Int?, time: TimeInterval?) {
        self.action = action
        self.commandID = commandID
        self.songs = songs
        self.startingIndex = startingIndex
        self.time = time
    }

    func withCommandID() -> PlaybackCommand {
        PlaybackCommand(
            action: action,
            commandID: commandID ?? UUID().uuidString,
            songs: songs,
            startingIndex: startingIndex,
            time: time
        )
    }
}

private struct SyncEnvelope: Codable {
    enum Kind: String, Codable {
        case hello
        case playbackState
        case playbackSession
        case playbackCommand
        case credentials
    }

    let kind: Kind
    let sender: SyncPeerInfo
    let playback: PlaybackSnapshot?
    let playbackSession: PlaybackSession?
    let command: PlaybackCommand?
    let credentials: SyncedCredentials?
    let targetDeviceID: String?

    init(
        kind: Kind,
        sender: SyncPeerInfo,
        playback: PlaybackSnapshot?,
        playbackSession: PlaybackSession? = nil,
        command: PlaybackCommand?,
        credentials: SyncedCredentials?,
        targetDeviceID: String?
    ) {
        self.kind = kind
        self.sender = sender
        self.playback = playback
        self.playbackSession = playbackSession
        self.command = command
        self.credentials = credentials
        self.targetDeviceID = targetDeviceID
    }
}

final class DeviceSyncManager: NSObject, ObservableObject {
    static let shared = DeviceSyncManager()

    @Published var syncModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncModeEnabled, forKey: Self.syncModeKey)
            if syncModeEnabled {
                UserDefaults.standard.set(false, forKey: Self.offlineModeKey)
            }
            configureTransports()
            broadcastHello()
            broadcastPlaybackState(force: true)
        }
    }

    @Published var credentialSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(credentialSyncEnabled, forKey: Self.credentialSyncKey)
            configureTransports()
            broadcastHello()
        }
    }

    @Published private(set) var remotePlayback: PlaybackSnapshot?
    @Published private(set) var sharedSession: PlaybackSession?
    @Published private(set) var connectedDeviceNames: [String] = []
    @Published var selectedPlaybackTargetID: String {
        didSet {
            UserDefaults.standard.set(selectedPlaybackTargetID, forKey: Self.playbackTargetKey)
        }
    }

    private static let syncModeKey = "syncMode"
    private static let credentialSyncKey = "credentialSyncMode"
    private static let offlineModeKey = "offlineMode"
    private static let playbackTargetKey = "playbackTargetDeviceID"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let localDeviceID: String
    private let localDeviceName: String
    private let platformName: String
    private var cancellables = Set<AnyCancellable>()
    private var lastPlaybackBroadcast = Date.distantPast
    private var isApplyingRemoteCommand = false
    private var peerInfos: [String: SyncPeerInfo] = [:]
    private var pendingTargetedCommands: [String: PlaybackCommand] = [:]
    private var processedCommandIDs = Set<String>()
    private var processedCommandIDOrder: [String] = []
    private let sharedSessionID: String

#if os(iOS) || os(watchOS)
    private var watchSession: WCSession?
#endif

#if os(iOS) || os(macOS)
    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peerDisplayNames: [MCPeerID: String] = [:]
    private var multipeerDeviceIDs = Set<String>()
    private var deviceIDsByPeerDisplayName: [String: String] = [:]
#endif

    private override init() {
        if let savedID = UserDefaults.standard.string(forKey: "deviceSyncDeviceID") {
            localDeviceID = savedID
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "deviceSyncDeviceID")
            localDeviceID = newID
        }
        if let savedSessionID = UserDefaults.standard.string(forKey: "deviceSyncSessionID") {
            sharedSessionID = savedSessionID
        } else {
            let newSessionID = UUID().uuidString
            UserDefaults.standard.set(newSessionID, forKey: "deviceSyncSessionID")
            sharedSessionID = newSessionID
        }

#if os(watchOS)
        localDeviceName = WKInterfaceDevice.current().name
        platformName = "Apple Watch"
#elseif os(iOS)
        localDeviceName = UIDevice.current.name
        platformName = "iPhone"
#elseif os(macOS)
        localDeviceName = Host.current().localizedName ?? "WRhythm"
        platformName = "Mac"
#else
        localDeviceName = ProcessInfo.processInfo.processName
        platformName = "Apple Device"
#endif

        if UserDefaults.standard.object(forKey: Self.syncModeKey) == nil {
            syncModeEnabled = true
            UserDefaults.standard.set(true, forKey: Self.syncModeKey)
            UserDefaults.standard.set(false, forKey: Self.offlineModeKey)
        } else {
            syncModeEnabled = UserDefaults.standard.bool(forKey: Self.syncModeKey)
        }
        if UserDefaults.standard.object(forKey: Self.credentialSyncKey) == nil {
            credentialSyncEnabled = true
            UserDefaults.standard.set(true, forKey: Self.credentialSyncKey)
        } else {
            credentialSyncEnabled = UserDefaults.standard.bool(forKey: Self.credentialSyncKey)
        }
        if UserDefaults.standard.bool(forKey: Self.syncModeKey) {
            UserDefaults.standard.set(false, forKey: Self.offlineModeKey)
        }
        // Playback output is a live route, not durable app state. Persisting another
        // device's UUID across launches leaves SwiftUI pickers bound to missing tags.
        selectedPlaybackTargetID = localDeviceID
        UserDefaults.standard.set(localDeviceID, forKey: Self.playbackTargetKey)

#if os(iOS) || os(macOS)
        peerID = MCPeerID(displayName: "\(localDeviceName)-\(localDeviceID.prefix(4))")
#endif

        super.init()

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        observePlayback()
        configureTransports()
    }

    var hasActiveRemotePlayback: Bool {
        guard syncModeEnabled, let remotePlayback else { return false }
        return remotePlayback.isPlaying || remotePlayback.song != nil
    }

    var isLocalPlaybackOutput: Bool {
        guard syncModeEnabled, let sharedSession else { return true }
        return sharedSession.outputDeviceID == localDeviceID
    }

    var activeSharedPlayback: PlaybackSnapshot? {
        guard syncModeEnabled,
              let sharedSession,
              let song = sharedSession.currentSong,
              sharedSession.outputDeviceID != localDeviceID else {
            return nil
        }

        let outputPeer = peerInfo(for: sharedSession.outputDeviceID)
        return PlaybackSnapshot(
            id: sharedSession.outputDeviceID,
            deviceName: outputPeer?.name ?? remotePlayback?.deviceName ?? "Remote Device",
            platform: outputPeer?.platform ?? remotePlayback?.platform ?? "Device",
            song: song,
            isPlaying: sharedSession.isPlaying,
            currentTime: sharedSession.position,
            duration: TimeInterval(song.duration ?? 0),
            queue: sharedSession.queue,
            currentIndex: sharedSession.currentIndex,
            updatedAt: sharedSession.updatedAt
        )
    }

    var sharedQueue: [Song] {
        sharedSession?.queue ?? []
    }

    var sharedQueueCurrentIndex: Int {
        guard let sharedSession else { return 0 }
        return min(max(sharedSession.currentIndex, 0), max(sharedSession.queue.count - 1, 0))
    }

    var availablePlaybackTargets: [PlaybackTargetDevice] {
        var targets = [
            PlaybackTargetDevice(id: localDeviceID, name: localDeviceName, platform: platformName, isLocal: true)
        ]

        let peers = peerInfos.values
            .filter { $0.syncModeEnabled }
            .filter { isPeerSelectable($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        targets.append(contentsOf: peers.map {
            PlaybackTargetDevice(id: $0.id, name: $0.name, platform: $0.platform, isLocal: false)
        })

        if let remotePlayback,
           remotePlayback.id != localDeviceID,
           Date().timeIntervalSince(remotePlayback.updatedAt) < 20,
           !targets.contains(where: { $0.id == remotePlayback.id }) {
            targets.append(PlaybackTargetDevice(
                id: remotePlayback.id,
                name: remotePlayback.deviceName,
                platform: remotePlayback.platform,
                isLocal: false
            ))
        }

        return targets
    }

    private func isPeerSelectable(_ peer: SyncPeerInfo) -> Bool {
#if os(iOS) || os(macOS)
        if multipeerDeviceIDs.contains(peer.id) {
            return true
        }

        // WatchConnectivity targets do not have Multipeer IDs.
        return peer.platform == "Apple Watch"
#else
        return true
#endif
    }

    private func peerInfo(for deviceID: String) -> SyncPeerInfo? {
        if deviceID == localDeviceID {
            return localPeerInfo()
        }
        return peerInfos[deviceID]
    }

    var selectedPlaybackTargetName: String {
        availablePlaybackTargets.first(where: { $0.id == validSelectedPlaybackTargetID })?.displayName ?? "This \(platformName)"
    }

    var validSelectedPlaybackTargetID: String {
        availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }) ? selectedPlaybackTargetID : localDeviceID
    }

    func validateSelectedPlaybackTarget() {
        if selectedPlaybackTargetID != validSelectedPlaybackTargetID {
            selectedPlaybackTargetID = localDeviceID
        }
    }

    private func nextSessionRevision() -> Int {
        (sharedSession?.revision ?? 0) + 1
    }

    private func makeSession(
        queue: [Song],
        currentIndex: Int,
        position: TimeInterval,
        isPlaying: Bool,
        outputDeviceID: String,
        revision: Int? = nil
    ) -> PlaybackSession {
        PlaybackSession(
            id: sharedSession?.id ?? sharedSessionID,
            revision: revision ?? nextSessionRevision(),
            queue: queue,
            currentIndex: min(max(currentIndex, 0), max(queue.count - 1, 0)),
            position: max(0, position.isFinite ? position : 0),
            isPlaying: isPlaying,
            outputDeviceID: outputDeviceID,
            updatedAt: Date(),
            updatedByDeviceID: localDeviceID
        )
    }

    private func publishSharedSession(_ session: PlaybackSession, applyLocally: Bool = true) {
        guard syncModeEnabled else { return }
        applySharedSession(session, applyLocally: applyLocally)
        _ = sendEnvelope(.init(
            kind: .playbackSession,
            sender: localPeerInfo(),
            playback: nil,
            playbackSession: session,
            command: nil,
            credentials: nil,
            targetDeviceID: nil
        ))
    }

    private func applySharedSession(_ session: PlaybackSession, applyLocally: Bool) {
        if let existing = sharedSession {
            if session.revision < existing.revision {
                return
            }
            if session.revision == existing.revision,
               session.updatedByDeviceID <= existing.updatedByDeviceID {
                return
            }
        }

        sharedSession = session
        selectedPlaybackTargetID = session.outputDeviceID

        if applyLocally {
            reconcileLocalPlayback(with: session)
        }
    }

    private func reconcileLocalPlayback(with session: PlaybackSession) {
        guard syncModeEnabled else { return }
        let player = AudioPlayer.shared

        if session.outputDeviceID == localDeviceID {
            guard let song = session.currentSong else {
                if player.currentSong != nil {
                    player.stop()
                }
                return
            }

            let queueMatches = player.queue.map(\.id) == session.queue.map(\.id)
            let currentMatches = player.currentSong?.id == song.id && player.currentIndex == session.currentIndex

            if currentMatches {
                if !queueMatches {
                    player.queue = session.queue
                    player.currentIndex = session.currentIndex
                }
                let drift = abs(player.currentTime - session.estimatedPosition)
                if drift > 3 {
                    player.seek(to: session.estimatedPosition)
                }
                if session.isPlaying, !player.isPlaying {
                    player.play()
                } else if !session.isPlaying, player.isPlaying {
                    player.pause()
                }
            } else {
                isApplyingRemoteCommand = true
                player.playQueue(session.queue, startingAt: session.currentIndex)
                player.seek(to: session.estimatedPosition)
                if !session.isPlaying {
                    player.pause()
                }
                isApplyingRemoteCommand = false
            }
        } else if player.isPlaying {
            player.pause()
        }
    }

    func routePlaybackRequestToConnectedDevice(_ songs: [Song], startingAt index: Int, shuffled: Bool = false) -> Bool {
        validateSelectedPlaybackTarget()
        guard syncModeEnabled,
              selectedPlaybackTargetID != localDeviceID,
              availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }),
              !isApplyingRemoteCommand else {
            return false
        }

        var outgoingSongs = songs
        var outgoingIndex = index
        if shuffled {
            outgoingSongs.shuffle()
            outgoingIndex = 0
        }

        publishSharedSession(makeSession(
            queue: outgoingSongs,
            currentIndex: outgoingIndex,
            position: 0,
            isPlaying: true,
            outputDeviceID: selectedPlaybackTargetID
        ))
        return true
    }

    func routeEnqueueRequestToConnectedDevice(_ songs: [Song]) -> Bool {
        validateSelectedPlaybackTarget()
        guard syncModeEnabled,
              selectedPlaybackTargetID != localDeviceID,
              availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }),
              !isApplyingRemoteCommand,
              !songs.isEmpty else {
            return false
        }

        let player = AudioPlayer.shared
        let baseQueue: [Song]
        let currentIndex: Int

        if let sharedSession, sharedSession.outputDeviceID == selectedPlaybackTargetID {
            baseQueue = sharedSession.queue
            currentIndex = min(sharedSession.currentIndex, max(baseQueue.count - 1, 0))
        } else if let remotePlayback, remotePlayback.id == selectedPlaybackTargetID {
            baseQueue = remotePlayback.queue.isEmpty ? remotePlayback.song.map { [$0] } ?? [] : remotePlayback.queue
            currentIndex = min(remotePlayback.currentIndex, max(baseQueue.count - 1, 0))
        } else {
            baseQueue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
            currentIndex = min(player.currentIndex, max(baseQueue.count - 1, 0))
        }

        let sharedQueue = baseQueue + songs
        publishSharedSession(makeSession(
            queue: sharedQueue,
            currentIndex: currentIndex,
            position: sharedSession?.outputDeviceID == selectedPlaybackTargetID ? sharedSession?.estimatedPosition ?? 0 : player.currentTime,
            isPlaying: sharedSession?.outputDeviceID == selectedPlaybackTargetID ? sharedSession?.isPlaying ?? false : player.isPlaying,
            outputDeviceID: selectedPlaybackTargetID
        ))
        return true
    }

    func enqueueOnConnectedDevices(_ songs: [Song]) {
        guard syncModeEnabled, !songs.isEmpty else { return }
        _ = sendCommand(.init(action: .enqueue, songs: songs, startingIndex: nil, time: nil), targetDeviceID: selectedRemotePlaybackTargetID)
    }

    func sendPlayPause(targetDeviceID: String? = nil) {
        _ = sendCommand(.init(action: .toggle, songs: nil, startingIndex: nil, time: nil), targetDeviceID: targetDeviceID ?? selectedRemotePlaybackTargetID)
    }

    func sendNext(targetDeviceID: String? = nil) {
        _ = sendCommand(.init(action: .next, songs: nil, startingIndex: nil, time: nil), targetDeviceID: targetDeviceID ?? selectedRemotePlaybackTargetID)
    }

    func sendPrevious(targetDeviceID: String? = nil) {
        _ = sendCommand(.init(action: .previous, songs: nil, startingIndex: nil, time: nil), targetDeviceID: targetDeviceID ?? selectedRemotePlaybackTargetID)
    }

    func sendSeek(to time: TimeInterval, targetDeviceID: String? = nil) {
        _ = sendCommand(.init(action: .seek, songs: nil, startingIndex: nil, time: time), targetDeviceID: targetDeviceID ?? selectedRemotePlaybackTargetID)
    }

    func playRemoteQueueItem(_ playback: PlaybackSnapshot, at index: Int) {
        guard syncModeEnabled, playback.id != localDeviceID else { return }
        let queue = playback.queue.isEmpty ? playback.song.map { [$0] } ?? [] : playback.queue
        guard !queue.isEmpty else { return }
        let safeIndex = min(max(index, 0), queue.count - 1)
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: safeIndex,
            position: 0,
            isPlaying: true,
            outputDeviceID: playback.id
        ))
    }

    func playSharedQueueItem(at index: Int) {
        guard syncModeEnabled, let sharedSession, !sharedSession.queue.isEmpty else { return }
        let safeIndex = min(max(index, 0), sharedSession.queue.count - 1)
        publishSharedSession(makeSession(
            queue: sharedSession.queue,
            currentIndex: safeIndex,
            position: 0,
            isPlaying: true,
            outputDeviceID: sharedSession.outputDeviceID
        ))

    }

    func takeOverRemotePlayback() {
        guard syncModeEnabled, let remotePlayback, let song = remotePlayback.song else { return }
        selectedPlaybackTargetID = localDeviceID
        let queue = remotePlayback.queue.isEmpty ? [song] : remotePlayback.queue
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: remotePlayback.currentIndex,
            position: remotePlayback.estimatedCurrentTime,
            isPlaying: remotePlayback.isPlaying,
            outputDeviceID: localDeviceID
        ))
    }

    func selectPlaybackTarget(_ targetID: String) {
        guard syncModeEnabled else {
            selectedPlaybackTargetID = localDeviceID
            return
        }

        selectedPlaybackTargetID = targetID

        if targetID == localDeviceID {
            if let sharedPlayback = activeSharedPlayback, sharedPlayback.song != nil {
                let queue = sharedPlayback.queue.isEmpty ? sharedPlayback.song.map { [$0] } ?? [] : sharedPlayback.queue
                guard !queue.isEmpty else { return }
                publishSharedSession(makeSession(
                    queue: queue,
                    currentIndex: sharedPlayback.currentIndex,
                    position: sharedPlayback.estimatedCurrentTime,
                    isPlaying: sharedPlayback.isPlaying,
                    outputDeviceID: localDeviceID
                ))
            } else if let remotePlayback, remotePlayback.song != nil, AudioPlayer.shared.currentSong == nil {
                takeOverRemotePlayback()
            }
            return
        }

        guard availablePlaybackTargets.contains(where: { $0.id == targetID }) else {
            selectedPlaybackTargetID = localDeviceID
            return
        }

        if let sharedSession, !sharedSession.queue.isEmpty {
            publishSharedSession(makeSession(
                queue: sharedSession.queue,
                currentIndex: sharedSession.currentIndex,
                position: sharedSession.estimatedPosition,
                isPlaying: sharedSession.isPlaying,
                outputDeviceID: targetID
            ))
            return
        }

        let player = AudioPlayer.shared
        guard let currentSong = player.currentSong else { return }
        let queue = player.queue.isEmpty ? [currentSong] : player.queue
        let index = min(player.currentIndex, queue.count - 1)
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: index,
            position: player.currentTime,
            isPlaying: player.isPlaying,
            outputDeviceID: targetID
        ))
    }

    func broadcastLocalQueueAsShared() {
        guard syncModeEnabled, !isApplyingRemoteCommand else { return }
        guard sharedSession?.outputDeviceID == nil || sharedSession?.outputDeviceID == localDeviceID else { return }
        let player = AudioPlayer.shared
        let queue = player.queue.isEmpty ? player.currentSong.map { [$0] } ?? [] : player.queue
        guard !queue.isEmpty else { return }
        publishSharedSession(makeSession(
            queue: queue,
            currentIndex: min(player.currentIndex, queue.count - 1),
            position: player.currentTime,
            isPlaying: player.isPlaying,
            outputDeviceID: localDeviceID
        ), applyLocally: false)
    }

    func credentialsDidChange() {
        broadcastHello()
        maybeSendCredentialsToInterestedPeers()
    }

    func requestCredentialSyncNow() {
        guard credentialSyncEnabled else { return }
        configureTransports()
        broadcastHello()
        maybeSendCredentialsToInterestedPeers()
    }

    private func observePlayback() {
        let player = AudioPlayer.shared

        Publishers.CombineLatest4(player.$currentSong, player.$isPlaying, player.$queue, player.$currentIndex)
            .sink { [weak self] _, _, _, _ in
                self?.broadcastPlaybackState()
            }
            .store(in: &cancellables)

        player.$currentTime
            .removeDuplicates { abs($0 - $1) < 5 }
            .sink { [weak self] _ in
                self?.broadcastPlaybackState()
            }
            .store(in: &cancellables)
    }

    private func configureTransports() {
        let shouldConnect = syncModeEnabled || credentialSyncEnabled

#if os(iOS)
        if shouldConnect, WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            if session.activationState == .notActivated {
                session.activate()
            }
            watchSession = session
        } else {
            watchSession = nil
        }
#elseif os(watchOS)
        if shouldConnect, WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            watchSession = session
        } else {
            watchSession = nil
        }
#endif

#if os(iOS) || os(macOS)
        if shouldConnect {
            if session == nil {
                let newSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
                newSession.delegate = self
                session = newSession
            }
            if advertiser == nil {
                advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["deviceID": localDeviceID], serviceType: "wrhythm-sync")
                advertiser?.delegate = self
                advertiser?.startAdvertisingPeer()
                print("📡 Sync advertiser started as \(peerID.displayName)")
            }
            if browser == nil {
                browser = MCNearbyServiceBrowser(peer: peerID, serviceType: "wrhythm-sync")
                browser?.delegate = self
                browser?.startBrowsingForPeers()
                print("🔎 Sync browser started as \(peerID.displayName)")
            }
        } else {
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
            session?.disconnect()
            advertiser = nil
            browser = nil
            session = nil
            peerDisplayNames.removeAll()
            connectedDeviceNames = []
            remotePlayback = nil
            sharedSession = nil
        }
#endif
    }

    private func localPeerInfo() -> SyncPeerInfo {
        SyncPeerInfo(
            id: localDeviceID,
            name: localDeviceName,
            platform: platformName,
            syncModeEnabled: syncModeEnabled,
            credentialSyncEnabled: credentialSyncEnabled,
            hasCredentials: NavidromeAPI.shared.hasCredentials
        )
    }

    private func localPlaybackSnapshot() -> PlaybackSnapshot {
        let player = AudioPlayer.shared
        return PlaybackSnapshot(
            id: localDeviceID,
            deviceName: localDeviceName,
            platform: platformName,
            song: player.currentSong,
            isPlaying: player.isPlaying,
            currentTime: player.currentTime,
            duration: player.duration,
            queue: player.queue,
            currentIndex: player.currentIndex,
            updatedAt: Date()
        )
    }

    private func broadcastHello() {
        _ = sendEnvelope(.init(kind: .hello, sender: localPeerInfo(), playback: nil, command: nil, credentials: nil, targetDeviceID: nil))
        if let sharedSession {
            _ = sendEnvelope(.init(
                kind: .playbackSession,
                sender: localPeerInfo(),
                playback: nil,
                playbackSession: sharedSession,
                command: nil,
                credentials: nil,
                targetDeviceID: nil
            ))
        }
    }

    private func broadcastPlaybackState(force: Bool = false) {
        guard syncModeEnabled else { return }
        guard !isApplyingRemoteCommand else { return }
        guard sharedSession?.outputDeviceID == nil || sharedSession?.outputDeviceID == localDeviceID else { return }
        guard force || Date().timeIntervalSince(lastPlaybackBroadcast) > 1.5 else { return }
        lastPlaybackBroadcast = Date()
        _ = sendEnvelope(.init(kind: .playbackState, sender: localPeerInfo(), playback: localPlaybackSnapshot(), command: nil, credentials: nil, targetDeviceID: nil))
    }

    private func maybeSendCredentialsToInterestedPeers() {
        guard credentialSyncEnabled, let credentials = NavidromeAPI.shared.exportCredentialsForSync() else { return }
        _ = sendEnvelope(.init(kind: .credentials, sender: localPeerInfo(), playback: nil, command: nil, credentials: credentials, targetDeviceID: nil))
    }

    private var selectedRemotePlaybackTargetID: String? {
        validateSelectedPlaybackTarget()
        guard selectedPlaybackTargetID != localDeviceID,
              availablePlaybackTargets.contains(where: { $0.id == selectedPlaybackTargetID }) else {
            return nil
        }
        return selectedPlaybackTargetID
    }

    private func shouldProcessCommand(_ command: PlaybackCommand) -> Bool {
        guard let commandID = command.commandID else { return true }
        guard !processedCommandIDs.contains(commandID) else { return false }

        processedCommandIDs.insert(commandID)
        processedCommandIDOrder.append(commandID)
        if processedCommandIDOrder.count > 200 {
            let expiredCount = processedCommandIDOrder.count - 200
            let expired = Array(processedCommandIDOrder.prefix(expiredCount))
            processedCommandIDOrder.removeFirst(expiredCount)
            expired.forEach { processedCommandIDs.remove($0) }
        }
        return true
    }

    @discardableResult
    private func sendCommand(_ command: PlaybackCommand, targetDeviceID: String? = nil) -> Bool {
        guard syncModeEnabled else { return false }
        let command = command.withCommandID()
        if let targetDeviceID {
            pendingTargetedCommands[targetDeviceID] = command
        }
        let sent = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), playback: nil, command: command, credentials: nil, targetDeviceID: targetDeviceID))
        if sent, let targetDeviceID {
            pendingTargetedCommands.removeValue(forKey: targetDeviceID)
        } else if let targetDeviceID {
            retryPendingCommand(for: targetDeviceID)
        }
        return sent
    }

    @discardableResult
    private func sendEnvelope(_ envelope: SyncEnvelope) -> Bool {
        guard let data = try? encoder.encode(envelope) else { return false }
        var didSend = false

#if os(iOS) || os(watchOS)
        if let watchSession {
            if watchSession.activationState == .activated, watchSession.isReachable {
                watchSession.sendMessageData(data, replyHandler: nil, errorHandler: nil)
                didSend = true
            } else if canQueueWatchConnectivityPayload(watchSession) {
                watchSession.transferUserInfo(["payload": data])
                didSend = true
            }
        }
#endif

#if os(iOS) || os(macOS)
        if let session, !session.connectedPeers.isEmpty {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                didSend = true
            } catch {
                print("❌ Failed to send sync envelope: \(error)")
            }
        }
#endif
        return didSend
    }

    private func handleEnvelopeData(_ data: Data, fromPeerDisplayName peerDisplayName: String? = nil) {
        guard let envelope = try? decoder.decode(SyncEnvelope.self, from: data) else { return }
        guard envelope.sender.id != localDeviceID else { return }

        peerInfos[envelope.sender.id] = envelope.sender
#if os(iOS) || os(macOS)
        if let peerDisplayName {
            multipeerDeviceIDs.insert(envelope.sender.id)
            deviceIDsByPeerDisplayName[peerDisplayName] = envelope.sender.id
        }
#endif
        connectedDeviceNames = Array(Set(peerInfos.values.map(\.name))).sorted()
        flushPendingCommand(for: envelope.sender.id)

        switch envelope.kind {
        case .hello:
            if credentialSyncEnabled,
               envelope.sender.credentialSyncEnabled,
               !envelope.sender.hasCredentials,
               let credentials = NavidromeAPI.shared.exportCredentialsForSync() {
                _ = sendEnvelope(.init(kind: .credentials, sender: localPeerInfo(), playback: nil, command: nil, credentials: credentials, targetDeviceID: nil))
            }

        case .playbackState:
            guard syncModeEnabled, envelope.sender.syncModeEnabled, let playback = envelope.playback else { return }
            remotePlayback = playback
            if sharedSession == nil,
               playback.isPlaying,
               !AudioPlayer.shared.isPlaying {
                selectedPlaybackTargetID = playback.id
            }
            if playback.song != nil {
                pendingTargetedCommands.removeValue(forKey: playback.id)
            }

        case .playbackSession:
            guard syncModeEnabled,
                  envelope.sender.syncModeEnabled,
                  let session = envelope.playbackSession else { return }
            applySharedSession(session, applyLocally: true)

        case .playbackCommand:
            guard syncModeEnabled, envelope.sender.syncModeEnabled, let command = envelope.command else { return }
            guard shouldProcessCommand(command) else { return }
            if command.action == .syncQueue {
                guard let ownerDeviceID = envelope.targetDeviceID, ownerDeviceID != localDeviceID else { return }
                guard let songs = command.songs, !songs.isEmpty else { return }
                applySharedSession(makeSession(
                    queue: songs,
                    currentIndex: min(command.startingIndex ?? 0, songs.count - 1),
                    position: command.time ?? 0,
                    isPlaying: sharedSession?.isPlaying ?? false,
                    outputDeviceID: ownerDeviceID,
                    revision: nextSessionRevision()
                ), applyLocally: true)
                return
            }

            if let targetDeviceID = envelope.targetDeviceID, targetDeviceID != localDeviceID {
                return
            }
            apply(command)

        case .credentials:
            guard credentialSyncEnabled, envelope.sender.credentialSyncEnabled, let credentials = envelope.credentials else { return }
            if NavidromeAPI.shared.importCredentialsIfMissing(credentials) {
                broadcastHello()
            }
        }
    }

    private func apply(_ command: PlaybackCommand) {
        let player = AudioPlayer.shared
        isApplyingRemoteCommand = true
        defer {
            isApplyingRemoteCommand = false
            if command.action != .syncQueue {
                broadcastLocalQueueAsShared()
                broadcastPlaybackState(force: true)
            }
        }

        switch command.action {
        case .play:
            player.play()
        case .pause:
            player.pause()
        case .toggle:
            player.togglePlayPause()
        case .next:
            player.next()
        case .previous:
            player.previous()
        case .seek:
            player.seek(to: command.time ?? 0)
        case .playQueue:
            guard let songs = command.songs, !songs.isEmpty else { return }
            selectedPlaybackTargetID = localDeviceID
            player.playQueue(songs, startingAt: min(command.startingIndex ?? 0, songs.count - 1))
            if let time = command.time, time > 0 {
                player.seek(to: time)
            }
        case .enqueue:
            guard let songs = command.songs, !songs.isEmpty else { return }
            player.enqueue(songs)
        case .syncQueue:
            guard let songs = command.songs, !songs.isEmpty else { return }
            let ownerDeviceID = sharedSession?.outputDeviceID ?? selectedPlaybackTargetID
            publishSharedSession(makeSession(
                queue: songs,
                currentIndex: min(command.startingIndex ?? 0, songs.count - 1),
                position: command.time ?? 0,
                isPlaying: sharedSession?.isPlaying ?? false,
                outputDeviceID: ownerDeviceID
            ))
        case .stop:
            player.stop()
        }
    }

    private func broadcastSharedQueue(ownerDeviceID: String, songs: [Song], currentIndex: Int, currentTime: TimeInterval) {
        guard syncModeEnabled, !songs.isEmpty else { return }
        publishSharedSession(makeSession(
            queue: songs,
            currentIndex: currentIndex,
            position: currentTime,
            isPlaying: sharedSession?.isPlaying ?? false,
            outputDeviceID: ownerDeviceID
        ))
        let command = PlaybackCommand(
            action: .syncQueue,
            songs: songs,
            startingIndex: min(currentIndex, songs.count - 1),
            time: currentTime
        )
        _ = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), playback: nil, command: command, credentials: nil, targetDeviceID: ownerDeviceID))
    }

    private func mirrorSharedQueue(songs: [Song], currentIndex: Int, currentTime: TimeInterval) {
        guard !songs.isEmpty else { return }
        let previousValue = isApplyingRemoteCommand
        isApplyingRemoteCommand = true
        AudioPlayer.shared.mirrorQueueWithoutPlayback(songs, currentIndex: currentIndex, currentTime: currentTime)
        isApplyingRemoteCommand = previousValue
    }

    private func flushPendingCommand(for deviceID: String) {
        guard let command = pendingTargetedCommands[deviceID] else { return }
        let sent = sendEnvelope(.init(kind: .playbackCommand, sender: localPeerInfo(), playback: nil, command: command, credentials: nil, targetDeviceID: deviceID))
        if sent {
            pendingTargetedCommands.removeValue(forKey: deviceID)
        } else {
            retryPendingCommand(for: deviceID)
        }
    }

    private func retryPendingCommand(for deviceID: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard self.pendingTargetedCommands[deviceID] != nil else { return }
            self.flushPendingCommand(for: deviceID)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.pendingTargetedCommands.removeValue(forKey: deviceID)
        }
    }

#if os(iOS) || os(watchOS)
    private func canQueueWatchConnectivityPayload(_ session: WCSession) -> Bool {
#if os(iOS)
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
#else
        return session.activationState == .activated
#endif
    }
#endif

#if os(iOS) || os(macOS)
    private func removeMultipeerPeer(_ peerID: MCPeerID) {
        peerDisplayNames.removeValue(forKey: peerID)

        if let deviceID = deviceIDsByPeerDisplayName.removeValue(forKey: peerID.displayName) {
            multipeerDeviceIDs.remove(deviceID)
            peerInfos.removeValue(forKey: deviceID)
            pendingTargetedCommands.removeValue(forKey: deviceID)
            if remotePlayback?.id == deviceID {
                remotePlayback = nil
            }

            if selectedPlaybackTargetID == deviceID {
                selectedPlaybackTargetID = localDeviceID
            }
        }

        connectedDeviceNames = Array(Set(peerInfos.values.map(\.name))).sorted()
    }
#endif
}

#if os(iOS) || os(watchOS)
extension DeviceSyncManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            DeviceSyncManager.shared.broadcastHello()
            DeviceSyncManager.shared.broadcastPlaybackState(force: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            DeviceSyncManager.shared.handleEnvelopeData(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        Task { @MainActor in
            DeviceSyncManager.shared.handleEnvelopeData(data)
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
#endif

#if os(iOS) || os(macOS)
extension DeviceSyncManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            let manager = DeviceSyncManager.shared
            switch state {
            case .connected:
                manager.peerDisplayNames[peerID] = peerID.displayName
                manager.connectedDeviceNames = Array(Set(manager.peerDisplayNames.values)).sorted()
                print("✅ Sync peer connected: \(peerID.displayName)")
                manager.broadcastHello()
                manager.broadcastPlaybackState(force: true)
                manager.maybeSendCredentialsToInterestedPeers()
            case .notConnected:
                print("⚠️ Sync peer disconnected: \(peerID.displayName)")
                manager.removeMultipeerPeer(peerID)
            case .connecting:
                print("🔄 Sync peer connecting: \(peerID.displayName)")
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            DeviceSyncManager.shared.handleEnvelopeData(data, fromPeerDisplayName: peerID.displayName)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension DeviceSyncManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            let manager = DeviceSyncManager.shared
            let shouldAccept = (manager.syncModeEnabled || manager.credentialSyncEnabled) && manager.session != nil
            print("\(shouldAccept ? "📨" : "🚫") Sync invitation from \(peerID.displayName)")
            invitationHandler(shouldAccept, manager.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Sync advertiser failed: \(error)")
    }
}

extension DeviceSyncManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            let manager = DeviceSyncManager.shared
            guard manager.syncModeEnabled || manager.credentialSyncEnabled else { return }
            guard let session = manager.session else { return }

            // Avoid dueling invitations. The lexically smaller peer initiates.
            guard manager.peerID.displayName < peerID.displayName else {
                print("👀 Sync peer found, waiting for invite: \(peerID.displayName)")
                return
            }

            print("📨 Sync peer found, inviting: \(peerID.displayName)")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            let manager = DeviceSyncManager.shared
            print("⚠️ Sync peer lost: \(peerID.displayName)")
            manager.removeMultipeerPeer(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Sync browser failed: \(error)")
    }
}
#endif
