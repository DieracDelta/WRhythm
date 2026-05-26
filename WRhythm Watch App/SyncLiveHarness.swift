#if DEBUG
import Combine
import Foundation

@MainActor
final class SyncLiveHarness {
    static let shared = SyncLiveHarness()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private var isStarted = false
    private var cancellables = Set<AnyCancellable>()
    private var statusTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    fileprivate var lastProcessedCommandID: String?
    fileprivate var lastProcessedCommand: String?

    private init() {}

    func startIfNeeded() {
        guard isEnabled, !isStarted else { return }
        isStarted = true

        DeviceSyncManager.shared.$sharedSession
            .sink { [weak self] _ in self?.writeStatus() }
            .store(in: &cancellables)
        DeviceSyncManager.shared.$connectedDeviceNames
            .sink { [weak self] _ in self?.writeStatus() }
            .store(in: &cancellables)
        AudioPlayer.shared.$isPlaying
            .sink { [weak self] _ in self?.writeStatus() }
            .store(in: &cancellables)

        statusTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.writeStatus()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        commandTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.processPendingCommand()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        writeStatus()
    }

    func handle(_ url: URL) {
        guard isEnabled, url.scheme == "wrhythm-harness" else { return }
        startIfNeeded()

        let command = url.host?.isEmpty == false
            ? url.host ?? ""
            : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value ?? ""
            } ?? [:]

        run(command: command, parameters: parameters)
        writeStatus()
    }

    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["WRHYTHM_SYNC_HARNESS"] == "1"
    }

    private var lastCommandID = 0
    private var lastError: String?

    private func run(command: String, parameters: [String: String]) {
        switch command {
        case "search":
            DeviceSyncManager.shared.searchForNearbyDevices()
        case "sync":
            DeviceSyncManager.shared.searchForNearbyDevices()
            DeviceSyncManager.shared.requestPlaybackSyncRefresh()
        case "publish":
            publish(parameters)
        case "play":
            mutateCurrentSession(parameters, isPlaying: true)
        case "pause":
            mutateCurrentSession(parameters, isPlaying: false)
        case "seek":
            mutateCurrentSession(parameters, position: parameters.double("position"))
        case "next":
            stepCurrentSession(delta: 1)
        case "previous":
            stepCurrentSession(delta: -1)
        case "applySession":
            applySession(parameters)
        case "receiveSession":
            receiveSession(parameters)
        case "ackSession":
            acknowledgeSession(parameters)
        case "setPeers":
            setPeers(parameters)
        case "remotePlay":
            DeviceSyncManager.shared.setPlaying(true, targetDeviceID: parameters["target"])
        case "remotePause":
            DeviceSyncManager.shared.setPlaying(false, targetDeviceID: parameters["target"])
        case "remoteNext":
            DeviceSyncManager.shared.sendNext(targetDeviceID: parameters["target"])
        case "remotePrevious":
            DeviceSyncManager.shared.sendPrevious(targetDeviceID: parameters["target"])
        case "remoteSeek":
            DeviceSyncManager.shared.sendSeek(to: parameters.double("position") ?? 0, targetDeviceID: parameters["target"])
        case "status":
            break
        default:
            lastError = "Unknown harness command: \(command)"
        }
    }

    private func processPendingCommand() {
        do {
            let url = try commandURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let command = try JSONDecoder().decode(HarnessCommand.self, from: data)
            guard command.id != lastProcessedCommandID else { return }
            lastProcessedCommandID = command.id
            lastProcessedCommand = command.command
            run(command: command.command, parameters: command.parameters)
            writeStatus()
        } catch {
            lastError = "Command polling failed: \(error.localizedDescription)"
            writeStatus()
        }
    }

    private func publish(_ parameters: [String: String]) {
        lastCommandID += 1
        let count = max(1, min(parameters.int("count") ?? 5, 200))
        let prefix = parameters["prefix"].flatMap { $0.isEmpty ? nil : $0 } ?? "harness"
        let queue = (0..<count).map {
            makeSong(id: "\(prefix)-\($0)", title: "Harness Track \($0 + 1)", duration: parameters.int("duration") ?? 300)
        }
        let output = outputDeviceID(from: parameters["output"])

        DeviceSyncManager.shared.harnessPublishPlayback(
            queue: queue,
            currentIndex: parameters.int("index") ?? 0,
            position: parameters.double("position") ?? 0,
            isPlaying: parameters.bool("playing") ?? true,
            outputDeviceID: output,
            revision: parameters.int("revision"),
            volume: parameters.double("volume")
        )
    }

    private func mutateCurrentSession(
        _ parameters: [String: String],
        isPlaying: Bool? = nil,
        position: TimeInterval? = nil
    ) {
        guard let session = DeviceSyncManager.shared.sharedSession, !session.queue.isEmpty else {
            lastError = "No shared session to mutate"
            return
        }

        DeviceSyncManager.shared.harnessPublishPlayback(
            queue: session.queue,
            currentIndex: session.currentIndex,
            position: position ?? parameters.double("position") ?? session.estimatedPosition,
            isPlaying: isPlaying ?? session.isPlaying,
            outputDeviceID: outputDeviceID(from: parameters["output"]) ?? session.outputDeviceID,
            volume: parameters.double("volume") ?? session.volume
        )
    }

    private func stepCurrentSession(delta: Int) {
        guard let session = DeviceSyncManager.shared.sharedSession, !session.queue.isEmpty else {
            lastError = "No shared session to step"
            return
        }

        let nextIndex = min(max(session.currentIndex + delta, 0), session.queue.count - 1)
        DeviceSyncManager.shared.harnessPublishPlayback(
            queue: session.queue,
            currentIndex: nextIndex,
            position: 0,
            isPlaying: session.isPlaying,
            outputDeviceID: session.outputDeviceID,
            volume: session.volume
        )
    }

    private func applySession(_ parameters: [String: String]) {
        if let session = decodeSession(parameters) {
            DeviceSyncManager.shared.harnessApplyPlaybackSession(session)
        }
    }

    private func receiveSession(_ parameters: [String: String]) {
        if let session = decodeSession(parameters) {
            DeviceSyncManager.shared.harnessReceivePlaybackSession(session)
        }
    }

    private func acknowledgeSession(_ parameters: [String: String]) {
        if let session = decodeSession(parameters) {
            DeviceSyncManager.shared.harnessAcknowledgePlaybackSession(session)
        }
    }

    private func decodeSession(_ parameters: [String: String]) -> PlaybackSession? {
        guard let encodedSession = parameters["session"],
              let data = Data(base64Encoded: encodedSession) else {
            lastError = "Missing or invalid encoded playback session"
            return nil
        }

        do {
            return try JSONDecoder.syncHarness.decode(PlaybackSession.self, from: data)
        } catch {
            lastError = "Failed to decode playback session: \(error.localizedDescription)"
            return nil
        }
    }

    private func setPeers(_ parameters: [String: String]) {
        guard let encodedPeers = parameters["peers"],
              let data = Data(base64Encoded: encodedPeers) else {
            lastError = "Missing or invalid encoded peers"
            return
        }

        do {
            let peers = try JSONDecoder().decode([HarnessPeer].self, from: data)
            DeviceSyncManager.shared.harnessSetKnownPeers(peers.map {
                (id: $0.id, name: $0.name, platform: $0.platform, syncModeEnabled: $0.syncModeEnabled)
            })
        } catch {
            lastError = "Failed to decode peers: \(error.localizedDescription)"
        }
    }

    private func outputDeviceID(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value == "local" {
            return DeviceSyncManager.shared.harnessLocalDeviceID
        }
        return value
    }

    private func makeSong(id: String, title: String, duration: Int) -> Song {
        Song(
            id: id,
            title: title,
            album: "Harness Album",
            albumId: "harness-album",
            artist: "Harness Artist",
            artistId: "harness-artist",
            track: nil,
            year: nil,
            genre: nil,
            coverArt: nil,
            size: nil,
            contentType: "audio/mpeg",
            suffix: "mp3",
            duration: duration,
            bitRate: 320,
            path: nil
        )
    }

    private func writeStatus() {
        guard isEnabled else { return }
        do {
            let data = try encoder.encode(HarnessStatus.capture(lastError: lastError))
            let url = try statusURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            print("⚠️ Sync harness failed to write status: \(error)")
        }
    }

    private func statusURL() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["WRHYTHM_SYNC_HARNESS_STATE_PATH"],
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return try harnessDirectoryURL().appendingPathComponent("state.json")
    }

    private func commandURL() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["WRHYTHM_SYNC_HARNESS_COMMAND_PATH"],
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return try harnessDirectoryURL().appendingPathComponent("command.json")
    }

    private func harnessDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL.appendingPathComponent("WRhythm/SyncHarness")
    }
}

private extension JSONDecoder {
    static let syncHarness: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct HarnessCommand: Codable {
    let id: String
    let command: String
    let parameters: [String: String]
}

private struct HarnessPeer: Codable {
    let id: String
    let name: String
    let platform: String
    let syncModeEnabled: Bool
}

private struct HarnessStatus: Codable {
    struct Session: Codable {
        let id: String
        let revision: Int
        let currentIndex: Int
        let currentSongID: String?
        let currentSongTitle: String?
        let position: TimeInterval
        let estimatedPosition: TimeInterval
        let isPlaying: Bool
        let outputDeviceID: String
        let updatedByDeviceID: String
        let updatedAt: Date
        let queueIDs: [String]
    }

    struct Player: Codable {
        let currentSongID: String?
        let currentIndex: Int
        let currentTime: TimeInterval
        let isPlaying: Bool
        let queueIDs: [String]
    }

    struct Target: Codable {
        let id: String
        let name: String
        let platform: String
        let isLocal: Bool
    }

    let capturedAt: Date
    let deviceID: String
    let deviceName: String
    let platform: String
    let connectedDeviceNames: [String]
    let peerIDs: [String]
    let peerSummaries: [String]
    let watchConnectivity: String
    let appDisplay: String
    let selectedPlaybackTargetID: String
    let validSelectedPlaybackTargetID: String
    let targets: [Target]
    let sharedSession: Session?
    let sharedSessionPayload: PlaybackSession?
    let player: Player
    let pendingCommandSummaries: [String]
    let lastProcessedCommandID: String?
    let lastProcessedCommand: String?
    let lastError: String?

    @MainActor
    static func capture(lastError: String?) -> HarnessStatus {
        let manager = DeviceSyncManager.shared
        let player = AudioPlayer.shared
        return HarnessStatus(
            capturedAt: Date(),
            deviceID: manager.harnessLocalDeviceID,
            deviceName: manager.harnessLocalDeviceName,
            platform: manager.harnessPlatformName,
            connectedDeviceNames: manager.connectedDeviceNames,
            peerIDs: manager.harnessPeerIDs,
            peerSummaries: manager.harnessPeerSummaries,
            watchConnectivity: manager.harnessWatchConnectivitySummary,
            appDisplay: manager.harnessAppDisplaySummary,
            selectedPlaybackTargetID: manager.selectedPlaybackTargetID,
            validSelectedPlaybackTargetID: manager.validSelectedPlaybackTargetID,
            targets: manager.availablePlaybackTargets.map {
                Target(id: $0.id, name: $0.name, platform: $0.platform, isLocal: $0.isLocal)
            },
            sharedSession: manager.sharedSession.map { session in
                Session(
                    id: session.id,
                    revision: session.revision,
                    currentIndex: session.currentIndex,
                    currentSongID: session.currentSong?.id,
                    currentSongTitle: session.currentSong?.title,
                    position: session.position,
                    estimatedPosition: session.estimatedPosition,
                    isPlaying: session.isPlaying,
                    outputDeviceID: session.outputDeviceID,
                    updatedByDeviceID: session.updatedByDeviceID,
                    updatedAt: session.updatedAt,
                    queueIDs: session.queue.map(\.id)
                )
            },
            sharedSessionPayload: manager.sharedSession,
            player: Player(
                currentSongID: player.currentSong?.id,
                currentIndex: player.currentIndex,
                currentTime: player.liveCurrentTime,
                isPlaying: player.isPlaying,
                queueIDs: player.queue.map(\.id)
            ),
            pendingCommandSummaries: manager.harnessPendingCommandSummaries,
            lastProcessedCommandID: SyncLiveHarness.shared.lastProcessedCommandID,
            lastProcessedCommand: SyncLiveHarness.shared.lastProcessedCommand,
            lastError: lastError
        )
    }
}

private extension Dictionary where Key == String, Value == String {
    func bool(_ key: String) -> Bool? {
        guard let value = self[key] else { return nil }
        switch value.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    func double(_ key: String) -> Double? {
        guard let value = self[key] else { return nil }
        return Double(value)
    }

    func int(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        return Int(value)
    }
}
#endif
