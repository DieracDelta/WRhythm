//
//  RadioPlaylistsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/24/25.
//

import SwiftUI

struct RadioPlaylistsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject private var api = NavidromeAPI.shared
    @AppStorage("experimentalAudioMuseFeaturesEnabled") private var experimentalAudioMuseFeaturesEnabled = false
    @State private var showingSonicTools = false
    @State private var audioMuseRadios: [AudioMuseRadioStation] = []
    @State private var audioMuseRadiosLoading = false
    @State private var audioMuseRadioError: String?

    private var sonicToolsCheckingSupport: Bool {
        api.sonicSimilaritySupported == nil ||
        (experimentalAudioMuseFeaturesEnabled && (api.audioMuseAlchemySupported == nil || api.audioMusePrivateSonicSupported == nil))
    }

    private var hasAdvancedGenerator: Bool {
        api.sonicSimilaritySupported == true ||
        AudioMuseFeatureVisibilityPolicy.isVisible(
            experimentalEnabled: experimentalAudioMuseFeaturesEnabled,
            supported: api.audioMusePrivateSonicSupported
        ) ||
        AudioMuseFeatureVisibilityPolicy.isVisible(
            experimentalEnabled: experimentalAudioMuseFeaturesEnabled,
            supported: api.audioMuseAlchemySupported
        )
    }

    var body: some View {
        Group {
            if player.playlistGenIsGenerating {
                playlistGenerationLoadingView
            } else if showingSonicTools {
                sonicToolsView
            } else if player.playlistGenQueue.isEmpty && downloadManager.radioPlaylists.isEmpty {
                emptyPlaylistGenView
            } else {
                List {
                    Section {
                        PlaylistGenModeToggle(
                            title: "Clear",
                            systemImage: "eraser",
                            action: {
                                showingSonicTools = true
                            }
                        )
                    }

                    if !player.playlistGenQueue.isEmpty {
                        Section("Current Playlist Gen") {
                            CurrentPlaylistGenSummary()

                            SlidingRenderWindowForEach(
                                player.playlistGenQueue,
                                estimatedRowHeight: 64,
                                resetToken: SongRenderWindowPolicy.playlistGenQueueResetToken(
                                    songIds: player.playlistGenQueue.map(\.id)
                                )
                            ) { index, song in
                                TrackRowView(
                                    song: song,
                                    player: player,
                                    downloadManager: downloadManager,
                                    offlineMode: false,
                                    selectionScopeSongs: player.playlistGenQueue
                                ) {
                                    player.playQueue(player.playlistGenQueue, startingAt: index, clearGeneratedPlaylist: false)
                                }
                            }
                        }
                    }

                    if !downloadManager.radioPlaylists.isEmpty {
                        Section("Downloaded Playlist Gen") {
                            SlidingRenderWindowForEach(
                                downloadManager.radioPlaylists,
                                estimatedRowHeight: 64,
                                resetToken: SongRenderWindowPolicy.downloadedRadioPlaylistsResetToken(
                                    playlistIds: downloadManager.radioPlaylists.map(\.id)
                                )
                            ) { _, radio in
                                RadioPlaylistRow(radio: radio)
                            }
                        }
                    }
                }
                .navigationTitle("Playlist Gen")
                .wrhythmListSurface()
            }
        }
        .task {
            if api.sonicSimilaritySupported == nil {
                _ = await api.checkSonicSimilaritySupport()
            }
            if experimentalAudioMuseFeaturesEnabled && api.audioMuseAlchemySupported == nil {
                _ = await api.checkAudioMuseAlchemySupport()
            }
            if experimentalAudioMuseFeaturesEnabled && api.audioMusePrivateSonicSupported == nil {
                _ = await api.checkAudioMuseFeatureSupport(.privateSonic)
            }
            if experimentalAudioMuseFeaturesEnabled && (api.audioMuseRadioSupported == nil || api.audioMuseMapSupported == nil) {
                await api.checkAudioMuseAdvancedPlaylistSupport()
                await refreshAudioMuseRadiosIfAvailable()
            }
        }
        .task(id: showingSonicTools) {
            if showingSonicTools {
                _ = await api.checkSonicSimilaritySupport()
                if experimentalAudioMuseFeaturesEnabled {
                    _ = await api.checkAudioMuseAlchemySupport()
                    await api.checkAudioMuseAdvancedPlaylistSupport()
                    await refreshAudioMuseRadiosIfAvailable()
                }
            }
        }
        .task(id: experimentalAudioMuseFeaturesEnabled) {
            guard experimentalAudioMuseFeaturesEnabled else { return }
            _ = await api.checkAudioMuseAlchemySupport()
            await api.checkAudioMuseAdvancedPlaylistSupport()
            await refreshAudioMuseRadiosIfAvailable()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = player.playlistGenErrorMessage {
                playlistGenerationErrorView(message: message, details: player.playlistGenErrorDetails)
                    .padding(.horizontal, WRhythmSpacing.md)
                    .padding(.bottom, WRhythmSpacing.sm)
            }
        }
    }

    @ViewBuilder
    private var emptyPlaylistGenView: some View {
#if os(iOS)
        WRhythmScreen {
            PhoneDetailHeader(title: "Playlist Gen")

            PhonePlaylistGenEmptyView()
                .padding(.top, WRhythmSpacing.lg)

            PlaylistGenModeToggle(
                title: "Open Sonic Tools",
                systemImage: "waveform.path.ecg",
                action: {
                    showingSonicTools = true
                }
            )
            .padding(.top, WRhythmSpacing.md)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
#else
        List {
            WRhythmEmptyState(
                systemImage: "music.note.list",
                title: "No Playlist Gen",
                message: "Start Playlist Gen from a song, album, artist, or playlist"
            )
            .listRowBackground(Color.clear)

            Section {
                PlaylistGenModeToggle(
                    title: "Open Sonic Tools",
                    systemImage: "waveform.path.ecg",
                    action: {
                        showingSonicTools = true
                    }
                )
            }
        }
        .navigationTitle("Playlist Gen")
        .wrhythmListSurface()
#endif
    }

    private var sonicToolsView: some View {
        List {
            Section {
                PlaylistGenModeToggle(
                    title: "Restore",
                    systemImage: "arrow.uturn.backward",
                    action: {
                        showingSonicTools = false
                    }
                )
            }

            Section("Advanced Playlist Gen") {
                if sonicToolsCheckingSupport {
                    WRhythmCard(padding: WRhythmSpacing.md) {
                        HStack(spacing: WRhythmSpacing.sm) {
                            ProgressView()
                            Text("Checking server support")
                                .font(WRhythmTypography.subhead)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else if hasAdvancedGenerator {
                    SonicPlaylistGeneratorView(
                        sonicSimilarityAvailable: api.sonicSimilaritySupported == true ||
                            AudioMuseFeatureVisibilityPolicy.isVisible(
                                experimentalEnabled: experimentalAudioMuseFeaturesEnabled,
                                supported: api.audioMusePrivateSonicSupported
                            ),
                        audioMuseAlchemyAvailable: AudioMuseFeatureVisibilityPolicy.isVisible(
                            experimentalEnabled: experimentalAudioMuseFeaturesEnabled,
                            supported: api.audioMuseAlchemySupported
                        ),
                        audioMuseRadioAvailable: AudioMuseFeatureVisibilityPolicy.isVisible(
                            experimentalEnabled: experimentalAudioMuseFeaturesEnabled,
                            supported: api.audioMuseRadioSupported
                        )
                    ) {
                        showingSonicTools = false
                    }
                    .listRowBackground(Color.clear)
                } else {
                    AdvancedPlaylistGenUnavailableView(
                        sonicSimilaritySupported: api.sonicSimilaritySupported == true,
                        audioMuseExperimentsEnabled: experimentalAudioMuseFeaturesEnabled,
                        audioMusePrivateSonicSupported: api.audioMusePrivateSonicSupported == true,
                        audioMuseAlchemySupported: api.audioMuseAlchemySupported == true
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if experimentalAudioMuseFeaturesEnabled {
                Section("AudioMuse Radio") {
                    if api.audioMuseRadioSupported == nil {
                        AudioMuseFeatureCheckingRow(label: "Checking radio support")
                            .listRowBackground(Color.clear)
                    } else if api.audioMuseRadioSupported == true {
                        AudioMuseRadioStationsView(
                            radios: audioMuseRadios,
                            isLoading: audioMuseRadiosLoading,
                            errorMessage: audioMuseRadioError,
                            refresh: {
                                Task { await refreshAudioMuseRadiosIfAvailable(force: true) }
                            },
                            play: { radio in
                                showingSonicTools = false
                                player.startAudioMuseRadioPlaylistGeneration(radio: radio)
                            },
                            delete: { radio in
                                Task { await deleteAudioMuseRadio(radio) }
                            }
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        AudioMuseFeatureUnavailableRow(title: "AudioMuse Radio", detail: "This server does not expose saved AI radio stations.")
                            .listRowBackground(Color.clear)
                    }
                }

#if !os(watchOS)
                Section("Music Map") {
                    if api.audioMuseMapSupported == nil {
                        AudioMuseFeatureCheckingRow(label: "Checking map support")
                            .listRowBackground(Color.clear)
                    } else if api.audioMuseMapSupported == true {
                        AudioMuseMapPlaylistBuilder()
                            .listRowBackground(Color.clear)
                    } else {
                        AudioMuseFeatureUnavailableRow(title: "Music Map", detail: "This server does not expose the AudioMuse map endpoints.")
                            .listRowBackground(Color.clear)
                    }
                }
#endif
            }
        }
        .navigationTitle("Playlist Gen")
        .wrhythmListSurface()
    }

    @MainActor
    private func refreshAudioMuseRadiosIfAvailable(force: Bool = false) async {
        guard experimentalAudioMuseFeaturesEnabled, api.audioMuseRadioSupported == true else {
            audioMuseRadios = []
            audioMuseRadioError = nil
            audioMuseRadiosLoading = false
            return
        }
        guard force || audioMuseRadios.isEmpty else { return }

        audioMuseRadiosLoading = true
        audioMuseRadioError = nil
        do {
            audioMuseRadios = try await api.getAudioMuseRadios()
        } catch {
            audioMuseRadios = []
            audioMuseRadioError = "Could not load radio stations"
        }
        audioMuseRadiosLoading = false
    }

    @MainActor
    private func deleteAudioMuseRadio(_ radio: AudioMuseRadioStation) async {
        do {
            try await api.deleteAudioMuseRadio(id: radio.id)
            audioMuseRadios.removeAll { $0.id == radio.id }
        } catch {
            audioMuseRadioError = "Could not delete \(radio.name)"
        }
    }

    private var playlistGenerationLoadingView: some View {
        List {
            WRhythmCard(padding: WRhythmSpacing.md) {
                VStack(spacing: WRhythmSpacing.sm) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Generating Playlist")
                        .font(WRhythmTypography.featureTitle)
                    if let title = player.playlistGenGeneratingTitle {
                        Text(title)
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button("Cancel", role: .cancel) {
                        player.cancelPlaylistGeneration()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Playlist Gen")
        .wrhythmListSurface()
    }

    private func playlistGenerationErrorView(message: String, details: String?) -> some View {
        VStack(spacing: 3) {
            Text(message)
                .font(WRhythmTypography.metadataEmphasis)
                .foregroundStyle(WRhythmTheme.danger)
            if let details {
                Text(details)
                    .font(WRhythmTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: WRhythmSpacing.sm) {
#if os(macOS) || os(iOS)
                Button("Copy Error") {
                    WRhythmClipboard.copy(
                        WRhythmErrorCopyPolicy.copyText(
                            title: message,
                            message: details
                        )
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(WRhythmTheme.accent)
                .accessibilityLabel("Copy Playlist Gen error")
#endif

                Button(action: player.dismissPlaylistGenError) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss Playlist Gen error")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
    }
}

struct CurrentPlaylistGenSummary: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        WRhythmCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                WRhythmCollectionRow(
                    title: player.playlistGenSourceTitle ?? "Current Playlist Gen",
                    subtitle: player.playlistGenSourceArtist,
                    detail: "\(player.playlistGenQueue.count) songs",
                    coverArtId: player.playlistGenQueue.first?.coverArt,
                    fallbackSystemImage: "music.note.list",
                    tint: WRhythmTheme.playlistGen
                )

                if let warning = player.playlistGenWarningMessage {
                    PlaylistGenWarningRow(
                        message: warning,
                        details: player.playlistGenWarningDetails
                    )
                }

                HStack(spacing: 8) {
                    Button(action: playCurrentPlaylist) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: downloadCurrentPlaylist) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        player.clearPlaylistGen()
                    }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear Playlist Gen")
                }
            }
        }
    }

    private func playCurrentPlaylist() {
        player.playQueue(player.playlistGenQueue, startingAt: 0, clearGeneratedPlaylist: false)
    }

    private func downloadCurrentPlaylist() {
        guard let sourceSong = player.playlistGenQueue.first else { return }

        for song in player.playlistGenQueue {
            downloadManager.downloadSong(song)
        }

        downloadManager.saveRadioPlaylist(sourceSong: sourceSong, songs: player.playlistGenQueue)
    }
}

private struct PlaylistGenWarningRow: View {
    let message: String
    let details: String?

    var body: some View {
        HStack(alignment: .top, spacing: WRhythmSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(WRhythmTheme.warning)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(WRhythmTypography.metadataEmphasis)
                if let details {
                    Text(details)
                        .font(WRhythmTypography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, WRhythmSpacing.sm)
        .padding(.vertical, WRhythmSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WRhythmTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius)
                .strokeBorder(WRhythmTheme.warning.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct AdvancedPlaylistGenUnavailableView: View {
    let sonicSimilaritySupported: Bool
    let audioMuseExperimentsEnabled: Bool
    let audioMusePrivateSonicSupported: Bool
    let audioMuseAlchemySupported: Bool

    private var bodyText: String {
        if audioMuseExperimentsEnabled {
            return "No advanced generator is available from this server right now."
        }
        return "OpenSubsonic support was not found. AudioMuse-AI probing is off."
    }

    var body: some View {
        WRhythmCard(padding: WRhythmSpacing.md, style: .glass) {
            VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                HStack(alignment: .center, spacing: WRhythmSpacing.sm) {
                    WRhythmIconBadge(
                        systemImage: "wand.and.stars",
                        tint: WRhythmTheme.playlistGen,
                        size: 38
                    )

                    VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                        Text("Advanced generators")
                            .font(WRhythmTypography.rowTitle)
                            .lineLimit(1)

                        Text(bodyText)
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: WRhythmSpacing.xs) {
                    AdvancedGeneratorStatusRow(
                        title: "OpenSubsonic sonicSimilarity",
                        isAvailable: sonicSimilaritySupported
                    )

                    AdvancedGeneratorStatusRow(
                        title: "AudioMuse-AI sonic wrappers",
                        isAvailable: audioMuseExperimentsEnabled && audioMusePrivateSonicSupported,
                        note: audioMuseExperimentsEnabled ? nil : "Enable in Settings"
                    )

                    AdvancedGeneratorStatusRow(
                        title: "AudioMuse-AI Alchemy",
                        isAvailable: audioMuseExperimentsEnabled && audioMuseAlchemySupported,
                        note: audioMuseExperimentsEnabled ? nil : "Enable in Settings"
                    )
                }
            }
        }
    }
}

private struct AdvancedGeneratorStatusRow: View {
    let title: String
    let isAvailable: Bool
    var note: String?

    var body: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isAvailable ? WRhythmTheme.success : .secondary)
                .imageScale(.medium)

            Text(title)
                .font(WRhythmTypography.metadata)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: WRhythmSpacing.sm)

            if let note {
                Text(note)
                    .font(WRhythmTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, WRhythmSpacing.sm)
        .padding(.vertical, WRhythmSpacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius))
    }
}

private struct AudioMuseFeatureCheckingRow: View {
    let label: String

    var body: some View {
        WRhythmCard(padding: WRhythmSpacing.md) {
            HStack(spacing: WRhythmSpacing.sm) {
                ProgressView()
                Text(label)
                    .font(WRhythmTypography.subhead)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AudioMuseFeatureUnavailableRow: View {
    let title: String
    let detail: String

    var body: some View {
        WRhythmCard(padding: WRhythmSpacing.md, style: .glass) {
            HStack(alignment: .top, spacing: WRhythmSpacing.sm) {
                WRhythmIconBadge(systemImage: "minus.circle", tint: .gray, size: 36)
                VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                    Text(title)
                        .font(WRhythmTypography.rowTitle)
                    Text(detail)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AudioMuseRadioStationsView: View {
    let radios: [AudioMuseRadioStation]
    let isLoading: Bool
    let errorMessage: String?
    let refresh: () -> Void
    let play: (AudioMuseRadioStation) -> Void
    let delete: (AudioMuseRadioStation) -> Void

    var body: some View {
        WRhythmCard(padding: WRhythmSpacing.md, style: .glass) {
            VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                HStack {
                    Label("Saved Radios", systemImage: "dot.radiowaves.left.and.right")
                        .font(WRhythmTypography.rowTitle)
                    Spacer()
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh AudioMuse radios")
                }

                if isLoading {
                    HStack(spacing: WRhythmSpacing.sm) {
                        ProgressView()
                        Text("Loading radios")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(WRhythmTheme.danger)
                } else if radios.isEmpty {
                    Text("No saved radios yet")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: WRhythmSpacing.xs) {
                        ForEach(radios) { radio in
                            AudioMuseRadioStationRow(
                                radio: radio,
                                play: { play(radio) },
                                delete: { delete(radio) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct AudioMuseRadioStationRow: View {
    let radio: AudioMuseRadioStation
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            WRhythmIconBadge(
                systemImage: "dot.radiowaves.left.and.right",
                tint: WRhythmTheme.playlistGen,
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(radio.name)
                    .font(WRhythmTypography.rowTitle)
                    .lineLimit(1)
                Text("Temperature \(radio.temperature, specifier: "%.1f")")
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: WRhythmSpacing.sm)

            Button(action: play) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(radio.name)")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(radio.name)")
        }
        .padding(.horizontal, WRhythmSpacing.sm)
        .padding(.vertical, WRhythmSpacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius))
    }
}

private struct AudioMuseRadioCreateCard: View {
    let seeds: [AudioMuseAlchemySeed]
    @State private var radioName = ""
    @State private var isCreating = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !isCreating &&
            !radioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !seeds.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
            Text("Save as Radio")
                .font(WRhythmTypography.controlLabelEmphasis)
                .foregroundStyle(.secondary)

#if os(watchOS)
            TextField("Name", text: $radioName)
#else
            TextField("Radio name", text: $radioName)
                .textFieldStyle(.roundedBorder)
#endif

            Button(action: createRadio) {
                Label(isCreating ? "Creating" : "Create Radio", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canCreate)

            if let statusMessage {
                Text(statusMessage)
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(WRhythmTheme.success)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(WRhythmTheme.danger)
            }
        }
    }

    private func createRadio() {
        guard canCreate else { return }
        let name = radioName.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                _ = try await NavidromeAPI.shared.createAudioMuseRadio(name: name, seeds: seeds)
                await MainActor.run {
                    radioName = ""
                    statusMessage = "Radio saved"
                    isCreating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not save radio"
                    isCreating = false
                }
            }
        }
    }
}

#if !os(watchOS)
private struct AudioMuseMapPlaylistBuilder: View {
    @ObservedObject private var api = NavidromeAPI.shared
    @State private var playlistName = ""
    @State private var query = ""
    @State private var results: [Song] = []
    @State private var selectedSongs: [Song] = []
    @State private var isSearching = false
    @State private var isCreating = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !isCreating &&
            !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !selectedSongs.isEmpty
    }

    var body: some View {
        WRhythmCard(padding: WRhythmSpacing.md, style: .glass) {
            VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                HStack(alignment: .center, spacing: WRhythmSpacing.sm) {
                    WRhythmIconBadge(systemImage: "map", tint: WRhythmTheme.playlistGen, size: 38)
                    VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                        Text("Map Playlist")
                            .font(WRhythmTypography.rowTitle)
                        Text("Select tracks and create an AudioMuse map playlist")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Playlist name", text: $playlistName)
                    .textFieldStyle(.roundedBorder)

                TextField("Search map tracks", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .wrhythmDismissFocusOnEscape()

                if !selectedSongs.isEmpty {
                    VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                        Text("\(selectedSongs.count) selected")
                            .font(WRhythmTypography.sectionLabel)
                            .foregroundStyle(.secondary)
                        ForEach(selectedSongs) { song in
                            SonicTrackSelectionRow(song: song, isSelected: true) {
                                selectedSongs.removeAll { $0.id == song.id }
                            }
                        }
                    }
                }

                if isSearching {
                    HStack(spacing: WRhythmSpacing.sm) {
                        ProgressView()
                        Text("Searching")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(WRhythmTheme.danger)
                } else if !results.isEmpty {
                    VStack(spacing: WRhythmSpacing.xs) {
                        ForEach(results.prefix(8)) { song in
                            SonicTrackSelectionRow(song: song, isSelected: selectedSongs.contains(where: { $0.id == song.id })) {
                                if selectedSongs.contains(where: { $0.id == song.id }) {
                                    selectedSongs.removeAll { $0.id == song.id }
                                } else {
                                    selectedSongs.append(song)
                                }
                            }
                        }
                    }
                }

                Button(action: createPlaylist) {
                    Label(isCreating ? "Creating" : "Create Playlist", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)

                if let statusMessage {
                    Text(statusMessage)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(WRhythmTheme.success)
                }
            }
        }
        .task(id: query) {
            await search()
        }
    }

    private func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearching = true
            errorMessage = nil
            let songs: [Song]
            do {
                songs = try await api.searchAudioMuseMapTracks(query: trimmedQuery)
            } catch {
                songs = try await api.search(query: trimmedQuery, songCount: 25).song ?? []
            }
            guard !Task.isCancelled, trimmedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = songs
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = "Search failed"
        }
        isSearching = false
    }

    private func createPlaylist() {
        guard canCreate else { return }
        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemIDs = selectedSongs.map(\.id)
        isCreating = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                let playlistID = try await api.createAudioMuseMapPlaylist(name: name, itemIDs: itemIDs)
                await MainActor.run {
                    statusMessage = "Created playlist \(playlistID)"
                    playlistName = ""
                    selectedSongs = []
                    isCreating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not create map playlist"
                    isCreating = false
                }
            }
        }
    }
}
#endif

private struct PlaylistGenModeToggle: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(WRhythmTypography.rowTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(WRhythmTheme.playlistGen)
    }
}

private enum SonicPlaylistMode: String, CaseIterable, Identifiable {
    case similarTracks = "Sonic Similarity"
    case sonicPath = "Find Sonic Path"
    case audioMuseAlchemy = "AudioMuse Alchemy"

    var id: String { rawValue }
}

private struct SonicPlaylistGeneratorView: View {
    @ObservedObject private var player = AudioPlayer.shared
    @State private var mode: SonicPlaylistMode = .similarTracks
    @State private var sourceQuery = ""
    @State private var startQuery = ""
    @State private var endQuery = ""
    @State private var alchemyQuery = ""
    @State private var sourceSong: Song?
    @State private var startSong: Song?
    @State private var endSong: Song?
    @State private var alchemySeeds: [AudioMuseAlchemySeed] = []

    let sonicSimilarityAvailable: Bool
    let audioMuseAlchemyAvailable: Bool
    let audioMuseRadioAvailable: Bool
    let didStartGeneration: () -> Void

    private var availableModes: [SonicPlaylistMode] {
        var modes: [SonicPlaylistMode] = []
        if sonicSimilarityAvailable {
            modes.append(contentsOf: [.similarTracks, .sonicPath])
        }
        if audioMuseAlchemyAvailable {
            modes.append(.audioMuseAlchemy)
        }
        return modes
    }

    var body: some View {
        WRhythmCard(padding: WRhythmSpacing.md) {
            VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                Picker("Generator", selection: $mode) {
                    ForEach(availableModes) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
#if !os(watchOS)
                .pickerStyle(.menu)
#endif
                .onAppear {
                    if !availableModes.contains(mode), let firstMode = availableModes.first {
                        mode = firstMode
                    }
                }
                .onChange(of: availableModes.map(\.id)) { _, _ in
                    if !availableModes.contains(mode), let firstMode = availableModes.first {
                        mode = firstMode
                    }
                }

                switch mode {
                case .similarTracks:
                    SonicTrackSearchPicker(
                        title: "Source track",
                        query: $sourceQuery,
                        selectedSong: $sourceSong
                    )

                    Button(action: generateSimilarTracks) {
                        Label(player.playlistGenIsGenerating ? "Generating" : "Generate", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!PlaylistGenerationActionPolicy.canStart(
                        isGenerating: player.playlistGenIsGenerating,
                        hasRequiredSelection: sourceSong != nil
                    ))

                case .sonicPath:
                    SonicTrackSearchPicker(
                        title: "Start track",
                        query: $startQuery,
                        selectedSong: $startSong
                    )

                    SonicTrackSearchPicker(
                        title: "End track",
                        query: $endQuery,
                        selectedSong: $endSong
                    )

                    Button(action: generateSonicPath) {
                        Label(
                            player.playlistGenIsGenerating ? "Generating" : "Generate Path",
                            systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!PlaylistGenerationActionPolicy.canStart(
                        isGenerating: player.playlistGenIsGenerating,
                        hasRequiredSelection: startSong != nil && endSong != nil
                    ))

                case .audioMuseAlchemy:
                    AudioMuseAlchemySeedSearchPicker(
                        title: "Seeds",
                        query: $alchemyQuery,
                        selectedSeeds: $alchemySeeds
                    )

                    Button(action: generateAudioMuseAlchemy) {
                        Label(player.playlistGenIsGenerating ? "Generating" : "Generate Alchemy", systemImage: "atom")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!PlaylistGenerationActionPolicy.canStart(
                        isGenerating: player.playlistGenIsGenerating,
                        hasRequiredSelection: !alchemySeeds.isEmpty
                    ))

                    if audioMuseRadioAvailable {
                        AudioMuseRadioCreateCard(seeds: alchemySeeds)
                    }
                }
            }
        }
    }

    private func generateSimilarTracks() {
        guard PlaylistGenerationActionPolicy.canStart(
            isGenerating: player.playlistGenIsGenerating,
            hasRequiredSelection: sourceSong != nil
        ), let sourceSong else { return }
        didStartGeneration()
        player.startSonicSimilarityPlaylistGeneration(for: sourceSong)
    }

    private func generateSonicPath() {
        guard PlaylistGenerationActionPolicy.canStart(
            isGenerating: player.playlistGenIsGenerating,
            hasRequiredSelection: startSong != nil && endSong != nil
        ), let startSong, let endSong else { return }
        didStartGeneration()
        player.startSonicPathPlaylistGeneration(from: startSong, to: endSong)
    }

    private func generateAudioMuseAlchemy() {
        guard AudioMuseAlchemySeedPolicy.canGenerate(
            seeds: alchemySeeds,
            isGenerating: player.playlistGenIsGenerating
        ) else { return }
        didStartGeneration()
        player.startAudioMuseAlchemyPlaylistGeneration(seeds: alchemySeeds)
    }
}

private struct SonicTrackSearchPicker: View {
    let title: String
    @Binding var query: String
    @Binding var selectedSong: Song?
    @State private var results: [Song] = []
    @State private var resultPage = 0
    @State private var canGoNext = false
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let pageSize = SonicTrackSearchPagingPolicy.defaultPageSize

    var body: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
            Text(title)
                .font(WRhythmTypography.controlLabelEmphasis)
                .foregroundStyle(.secondary)

            searchField
                .onChange(of: query) { _, newValue in
                    guard let selectedSong else { return }
                    if newValue != selectedSong.title {
                        self.selectedSong = nil
                    }
                }

            if let selectedSong {
                SonicTrackSelectionRow(song: selectedSong, isSelected: true) {
                    self.selectedSong = nil
                    query = ""
                }
            } else if isSearching {
                HStack(spacing: WRhythmSpacing.sm) {
                    ProgressView()
                    Text("Searching")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, WRhythmSpacing.xs)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(WRhythmTheme.danger)
            } else if hasSearchContent {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    searchSectionHeader

                    if results.isEmpty {
                        Text("No tracks on this page")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, WRhythmSpacing.xs)
                    } else {
                        ForEach(results) { song in
                            SonicTrackSelectionRow(song: song, isSelected: false) {
                                selectedSong = song
                                query = song.title
                                clearResults()
                            }
                        }
                    }
                }
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                Text("No track matches")
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, WRhythmSpacing.xs)
            }
        }
        .task(id: query) {
            resultPage = 0
            clearResults()
            await search(debounce: true)
        }
    }

    private var hasSearchContent: Bool {
        !results.isEmpty || resultPage > 0 || canGoNext
    }

    @ViewBuilder
    private var searchSectionHeader: some View {
        let canPrevious = SonicTrackSearchPagingPolicy.canGoPrevious(page: resultPage)

        HStack(spacing: WRhythmSpacing.xs) {
            Text("Tracks")
                .font(WRhythmTypography.sectionLabel)
                .foregroundStyle(.secondary)

            Spacer(minLength: WRhythmSpacing.sm)

            if canPrevious || canGoNext {
                Button {
                    goToPage(resultPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(!canPrevious || isSearching)
                .accessibilityLabel("Previous tracks page")

                Text("Page \(resultPage + 1)")
                    .font(WRhythmTypography.metadataEmphasis)
                    .foregroundStyle(WRhythmTheme.playlistGen)
                    .monospacedDigit()
                    .accessibilityHidden(true)

                Button {
                    goToPage(resultPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!canGoNext || isSearching)
                .accessibilityLabel("Next tracks page")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func goToPage(_ page: Int) {
        resultPage = max(0, page)
        Task {
            await search(debounce: false)
        }
    }

    private func clearResults() {
        results = []
        canGoNext = false
    }

    @ViewBuilder
    private var searchField: some View {
#if os(watchOS)
        TextField("Search tracks", text: $query)
#else
        TextField("Search tracks", text: $query)
            .textFieldStyle(.roundedBorder)
            .wrhythmDismissFocusOnEscape()
#endif
    }

    private func search(debounce: Bool) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedSong == nil, trimmedQuery.count >= 2 else {
            clearResults()
            errorMessage = nil
            isSearching = false
            return
        }

        do {
            if debounce {
                try await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            isSearching = true
            errorMessage = nil
            let capturedPage = resultPage
            let searchResult = try await NavidromeAPI.shared.search(
                query: trimmedQuery,
                songCount: SonicTrackSearchPagingPolicy.requestCount(pageSize: pageSize),
                songOffset: SonicTrackSearchPagingPolicy.offset(forPage: capturedPage, pageSize: pageSize)
            )
            guard !Task.isCancelled,
                  capturedPage == resultPage,
                  trimmedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            let fetchedSongs = searchResult.song ?? []
            results = SonicTrackSearchPagingPolicy.visibleItems(fetchedSongs, pageSize: pageSize)
            canGoNext = SonicTrackSearchPagingPolicy.canGoNextFromLookahead(resultCount: fetchedSongs.count, pageSize: pageSize)
        } catch is CancellationError {
            return
        } catch {
            clearResults()
            errorMessage = "Search failed"
        }

        isSearching = false
    }
}

private struct AudioMuseAlchemySeedSearchPicker: View {
    let title: String
    @Binding var query: String
    @Binding var selectedSeeds: [AudioMuseAlchemySeed]
    @State private var searchResult = SearchResult(artist: [], album: [], song: [])
    @State private var playlistResults: [PlaylistSummary] = []
    @State private var artistPage = 0
    @State private var albumPage = 0
    @State private var trackPage = 0
    @State private var playlistPage = 0
    @State private var artistCanGoNext = false
    @State private var albumCanGoNext = false
    @State private var trackCanGoNext = false
    @State private var playlistCanGoNext = false
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let pageSize = AudioMuseAlchemySeedSearchPagingPolicy.defaultPageSize

    private var hasResults: Bool {
        !(searchResult.artist ?? []).isEmpty ||
            !(searchResult.album ?? []).isEmpty ||
            !(searchResult.song ?? []).isEmpty ||
            !playlistResults.isEmpty
    }

    private var hasSearchContent: Bool {
        hasResults || artistPage > 0 || albumPage > 0 || trackPage > 0 || playlistPage > 0
    }

    private var currentPlaylistResults: [PlaylistSummary] {
        AudioMuseAlchemySeedSearchPagingPolicy.pageItems(
            playlistResults,
            page: playlistPage,
            pageSize: pageSize
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
            Text(title)
                .font(WRhythmTypography.controlLabelEmphasis)
                .foregroundStyle(.secondary)

            searchField

            if !selectedSeeds.isEmpty {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    Text("\(selectedSeeds.count) selected")
                        .font(WRhythmTypography.sectionLabel)
                        .foregroundStyle(.secondary)

                    ForEach(selectedSeeds) { seed in
                        AudioMuseAlchemySeedRow(seed: seed, isSelected: true) {
                            selectedSeeds = AudioMuseAlchemySeedPolicy.remove(seed, from: selectedSeeds)
                        }
                    }
                }
            }

            if isSearching {
                HStack(spacing: WRhythmSpacing.sm) {
                    ProgressView()
                    Text("Searching")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, WRhythmSpacing.xs)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(WRhythmTheme.danger)
            } else if hasSearchContent {
                VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                    seedSection(
                        .artists,
                        seeds: (searchResult.artist ?? []).map(AudioMuseAlchemySeed.artist)
                    )
                    seedSection(
                        .albums,
                        seeds: (searchResult.album ?? []).map(AudioMuseAlchemySeed.album)
                    )
                    seedSection(
                        .tracks,
                        seeds: (searchResult.song ?? []).map(AudioMuseAlchemySeed.song)
                    )
                    seedSection(
                        .playlists,
                        seeds: currentPlaylistResults.map(AudioMuseAlchemySeed.playlist)
                    )
                }
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                Text("No seed matches")
                    .font(WRhythmTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, WRhythmSpacing.xs)
            }
        }
        .task(id: query) {
            resetPages()
            clearResults()
            await search(debounce: true)
        }
    }

    @ViewBuilder
    private var searchField: some View {
#if os(watchOS)
        TextField("Search seeds", text: $query)
#else
        TextField("Search artists, albums, tracks, playlists", text: $query)
            .textFieldStyle(.roundedBorder)
            .wrhythmDismissFocusOnEscape()
#endif
    }

    @ViewBuilder
    private func seedSection(_ kind: AudioMuseAlchemySeedSearchPageKind, seeds: [AudioMuseAlchemySeed]) -> some View {
        let page = page(for: kind)
        let canPrevious = AudioMuseAlchemySeedSearchPagingPolicy.canGoPrevious(page: page)
        let canNext = canGoNext(for: kind)

        if !seeds.isEmpty || canPrevious || canNext {
            VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                seedSectionHeader(for: kind)

                if seeds.isEmpty {
                    Text("No \(kind.label.lowercased()) on this page")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, WRhythmSpacing.xs)
                } else {
                    ForEach(seeds) { seed in
                        AudioMuseAlchemySeedRow(seed: seed, isSelected: false) {
                            selectedSeeds = AudioMuseAlchemySeedPolicy.append(seed, to: selectedSeeds)
                            query = ""
                            clearResults()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func seedSectionHeader(for kind: AudioMuseAlchemySeedSearchPageKind) -> some View {
        let currentPage = page(for: kind)
        let canPrevious = AudioMuseAlchemySeedSearchPagingPolicy.canGoPrevious(page: currentPage)
        let canNext = canGoNext(for: kind)

        HStack(spacing: WRhythmSpacing.xs) {
            Text(kind.label)
                .font(WRhythmTypography.sectionLabel)
                .foregroundStyle(.secondary)

            Spacer(minLength: WRhythmSpacing.sm)

            if canPrevious || canNext {
                Button {
                    goToPage(currentPage - 1, kind: kind)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(!canPrevious || isSearching)
                .accessibilityLabel("Previous \(kind.label) page")

                Text("Page \(currentPage + 1)")
                    .font(WRhythmTypography.metadataEmphasis)
                    .foregroundStyle(WRhythmTheme.playlistGen)
                    .monospacedDigit()
                    .accessibilityHidden(true)

                Button {
                    goToPage(currentPage + 1, kind: kind)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!canNext || isSearching)
                .accessibilityLabel("Next \(kind.label) page")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func search(debounce: Bool) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            clearResults()
            errorMessage = nil
            isSearching = false
            return
        }

        do {
            if debounce {
                try await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            isSearching = true
            errorMessage = nil

            let capturedArtistPage = artistPage
            let capturedAlbumPage = albumPage
            let capturedTrackPage = trackPage
            let capturedPlaylistPage = playlistPage

            async let subsonicResult = NavidromeAPI.shared.search(
                query: trimmedQuery,
                artistCount: pageSize,
                artistOffset: AudioMuseAlchemySeedSearchPagingPolicy.offset(
                    forPage: capturedArtistPage,
                    pageSize: pageSize
                ),
                albumCount: pageSize,
                albumOffset: AudioMuseAlchemySeedSearchPagingPolicy.offset(
                    forPage: capturedAlbumPage,
                    pageSize: pageSize
                ),
                songCount: pageSize,
                songOffset: AudioMuseAlchemySeedSearchPagingPolicy.offset(
                    forPage: capturedTrackPage,
                    pageSize: pageSize
                )
            )
            async let playlists = NavidromeAPI.shared.getPlaylists()

            let result = try await subsonicResult
            let fetchedPlaylists = (try? await playlists) ?? []
            guard !Task.isCancelled,
                  trimmedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines),
                  capturedArtistPage == artistPage,
                  capturedAlbumPage == albumPage,
                  capturedTrackPage == trackPage,
                  capturedPlaylistPage == playlistPage else { return }

            searchResult = result
            playlistResults = fetchedPlaylists.filter { playlist in
                playlist.name.localizedCaseInsensitiveContains(trimmedQuery)
            }
            updatePageAvailability()
        } catch is CancellationError {
            return
        } catch {
            clearResults()
            errorMessage = "Search failed"
        }

        isSearching = false
    }

    private func page(for kind: AudioMuseAlchemySeedSearchPageKind) -> Int {
        switch kind {
        case .artists: return artistPage
        case .albums: return albumPage
        case .tracks: return trackPage
        case .playlists: return playlistPage
        }
    }

    private func canGoNext(for kind: AudioMuseAlchemySeedSearchPageKind) -> Bool {
        switch kind {
        case .artists: return artistCanGoNext
        case .albums: return albumCanGoNext
        case .tracks: return trackCanGoNext
        case .playlists: return playlistCanGoNext
        }
    }

    private func goToPage(_ page: Int, kind: AudioMuseAlchemySeedSearchPageKind) {
        let page = max(0, page)
        switch kind {
        case .artists:
            artistPage = page
        case .albums:
            albumPage = page
        case .tracks:
            trackPage = page
        case .playlists:
            playlistPage = page
        }

        Task {
            await search(debounce: false)
        }
    }

    private func resetPages() {
        artistPage = 0
        albumPage = 0
        trackPage = 0
        playlistPage = 0
        updatePageAvailability()
    }

    private func updatePageAvailability() {
        artistCanGoNext = AudioMuseAlchemySeedSearchPagingPolicy.canGoNext(
            resultCount: searchResult.artist?.count ?? 0,
            pageSize: pageSize
        )
        albumCanGoNext = AudioMuseAlchemySeedSearchPagingPolicy.canGoNext(
            resultCount: searchResult.album?.count ?? 0,
            pageSize: pageSize
        )
        trackCanGoNext = AudioMuseAlchemySeedSearchPagingPolicy.canGoNext(
            resultCount: searchResult.song?.count ?? 0,
            pageSize: pageSize
        )
        playlistCanGoNext = AudioMuseAlchemySeedSearchPagingPolicy.canGoNextLocal(
            totalCount: playlistResults.count,
            page: playlistPage,
            pageSize: pageSize
        )
    }

    private func clearResults() {
        searchResult = SearchResult(artist: [], album: [], song: [])
        playlistResults = []
        updatePageAvailability()
    }
}

private struct AudioMuseAlchemySeedRow: View {
    let seed: AudioMuseAlchemySeed
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch seed.kind {
        case .song: return "music.note"
        case .artist: return "person.2"
        case .album: return "square.stack"
        case .playlist: return "music.note.list"
        }
    }

    private var kindLabel: String {
        seed.kind.rawValue.capitalized
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WRhythmSpacing.sm) {
                WRhythmArtworkThumbnail(coverArtId: seed.coverArt, fallbackSystemImage: icon, tint: WRhythmTheme.playlistGen, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(seed.title)
                        .font(WRhythmTypography.rowTitle)
                        .lineLimit(1)
                    Text([kindLabel, seed.subtitle].compactMap { $0 }.joined(separator: " • "))
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: WRhythmSpacing.sm)

                Image(systemName: isSelected ? "xmark.circle.fill" : "plus.circle")
                    .foregroundStyle(WRhythmTheme.playlistGen)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Remove \(seed.title)" : "Add \(seed.title)")
    }
}

private struct SonicTrackSelectionRow: View {
    let song: Song
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WRhythmSpacing.sm) {
                WRhythmArtworkThumbnail(coverArtId: song.coverArt, fallbackSystemImage: "music.note", tint: WRhythmTheme.playlistGen, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(WRhythmTypography.rowTitle)
                        .lineLimit(1)
                    Text(song.artist ?? "Unknown Artist")
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: WRhythmSpacing.sm)

                Image(systemName: isSelected ? "xmark.circle.fill" : "plus.circle")
                    .foregroundStyle(WRhythmTheme.playlistGen)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Clear selected track" : "Select \(song.title)")
    }
}

struct RadioPlaylistRow: View {
    let radio: RadioPlaylist
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        NavigationLink(destination: RadioPlaylistDetailView(radio: radio)) {
            let downloadedCount = radio.songIds.filter { downloadManager.isDownloaded($0) }.count
            WRhythmCollectionRow(
                title: radio.sourceSongTitle,
                subtitle: radio.sourceSongArtist,
                detail: "\(downloadedCount)/\(radio.songIds.count) songs",
                coverArtId: radio.coverArt,
                fallbackSystemImage: "radio",
                tint: WRhythmTheme.playlistGen
            )
        }
        .buttonStyle(.plain)
    }
}

struct RadioPlaylistDetailView: View {
    let radio: RadioPlaylist
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        WRhythmScreen(coverArtId: radio.coverArt) {
            let downloadedSongs = radio.songIds.filter { downloadManager.isDownloaded($0) }

            WRhythmHeroHeader(
                title: radio.sourceSongTitle,
                subtitle: radio.sourceSongArtist,
                detail: "\(downloadedSongs.count) of \(radio.songIds.count) songs downloaded",
                systemImage: "radio",
                tint: WRhythmTheme.playlistGen,
                coverArtId: radio.coverArt
            )

            WRhythmActionStrip {
                if !downloadedSongs.isEmpty {
                    Button(action: {
                        playRadio()
                    }) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        shuffleRadio()
                    }) {
                        Image(systemName: "shuffle")
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: {
                    deleteRadio()
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(WRhythmTheme.danger)
                .accessibilityLabel("Delete Playlist Gen")
            }

            if downloadedSongs.isEmpty {
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No downloaded songs",
                    message: "Download this Playlist Gen before playing it offline"
                )
            } else {
                WRhythmSectionHeader(title: "Songs", subtitle: "\(downloadedSongs.count) ready")

                SlidingRenderWindowForEach(downloadedSongItems, estimatedRowHeight: 64, spacing: 8) { _, item in
                    if let downloadedSong = downloadManager.downloadedSongs[item.songId] {
                        let song = Song(
                            id: downloadedSong.songId,
                            title: downloadedSong.title,
                            album: downloadedSong.album,
                            albumId: nil,
                            artist: downloadedSong.artist,
                            artistId: nil,
                            track: nil,
                            year: nil,
                            genre: nil,
                            coverArt: downloadedSong.coverArt,
                            size: Int(downloadedSong.fileSize),
                            contentType: nil,
                            suffix: nil,
                            duration: nil,
                            bitRate: nil,
                            path: downloadedSong.filePath
                        )
                        TrackRowView(
                            song: song,
                            player: player,
                            downloadManager: downloadManager,
                            offlineMode: true,
                            selectionScopeSongs: downloadedQueueSongs
                        ) {
                            playRadio(startingAt: item.index)
                        }
                    }
                }
            }
        }
        .navigationTitle("Playlist Gen")
    }

    private var downloadedSongs: [String] {
        radio.songIds.filter { downloadManager.isDownloaded($0) }
    }

    private var downloadedSongItems: [DownloadedRadioSongItem] {
        downloadedSongs.enumerated().map { index, songId in
            DownloadedRadioSongItem(index: index, songId: songId)
        }
    }

    private var downloadedQueueSongs: [Song] {
        downloadedSongs.compactMap { songId -> Song? in
            guard let downloaded = downloadManager.downloadedSongs[songId] else { return nil }
            return makeSong(from: downloaded)
        }
    }

    private func playRadio(startingAt index: Int = 0) {
        let songs = downloadedQueueSongs

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs in radio")
            return
        }

        player.playQueue(songs, startingAt: index)
    }

    private func shuffleRadio() {
        let songs = downloadedQueueSongs

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs in radio")
            return
        }

        player.playQueueShuffled(songs)
    }

    private func makeSong(from downloaded: DownloadedSong) -> Song {
        Song(
            id: downloaded.songId,
            title: downloaded.title,
            album: downloaded.album,
            albumId: nil,
            artist: downloaded.artist,
            artistId: nil,
            track: nil,
            year: nil,
            genre: nil,
            coverArt: downloaded.coverArt,
            size: Int(downloaded.fileSize),
            contentType: nil,
            suffix: nil,
            duration: nil,
            bitRate: nil,
            path: downloaded.filePath
        )
    }

    private func deleteRadio() {
        downloadManager.deleteRadioPlaylist(radio.id)
    }
}

private struct DownloadedRadioSongItem: Identifiable {
    let index: Int
    let songId: String

    var id: String {
        "\(songId)-\(index)"
    }
}
