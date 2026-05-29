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

    private var sonicToolsCheckingSupport: Bool {
        api.sonicSimilaritySupported == nil ||
        (experimentalAudioMuseFeaturesEnabled && api.audioMuseAlchemySupported == nil)
    }

    private var hasAdvancedGenerator: Bool {
        api.sonicSimilaritySupported == true ||
        (experimentalAudioMuseFeaturesEnabled && api.audioMuseAlchemySupported == true)
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

                            ForEach(Array(player.playlistGenQueue.enumerated()), id: \.element.id) { index, song in
                                TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: false) {
                                    player.playQueue(player.playlistGenQueue, startingAt: index, clearGeneratedPlaylist: false)
                                }
                            }
                        }
                    }

                    if !downloadManager.radioPlaylists.isEmpty {
                        Section("Downloaded Playlist Gen") {
                            ForEach(downloadManager.radioPlaylists) { radio in
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
        }
        .task(id: showingSonicTools) {
            if showingSonicTools {
                _ = await api.checkSonicSimilaritySupport()
                if experimentalAudioMuseFeaturesEnabled {
                    _ = await api.checkAudioMuseAlchemySupport()
                }
            }
        }
        .task(id: experimentalAudioMuseFeaturesEnabled) {
            guard experimentalAudioMuseFeaturesEnabled else { return }
            _ = await api.checkAudioMuseAlchemySupport()
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
                        sonicSimilarityAvailable: api.sonicSimilaritySupported == true,
                        audioMuseAlchemyAvailable: experimentalAudioMuseFeaturesEnabled && api.audioMuseAlchemySupported == true
                    ) {
                        showingSonicTools = false
                    }
                    .listRowBackground(Color.clear)
                } else {
                    AdvancedPlaylistGenUnavailableView(
                        sonicSimilaritySupported: api.sonicSimilaritySupported == true,
                        audioMuseExperimentsEnabled: experimentalAudioMuseFeaturesEnabled,
                        audioMuseAlchemySupported: api.audioMuseAlchemySupported == true
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Playlist Gen")
        .wrhythmListSurface()
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
            Button(action: player.dismissPlaylistGenError) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Playlist Gen error")
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
    @State private var alchemySong: Song?

    let sonicSimilarityAvailable: Bool
    let audioMuseAlchemyAvailable: Bool
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
                    SonicTrackSearchPicker(
                        title: "Seed track",
                        query: $alchemyQuery,
                        selectedSong: $alchemySong
                    )

                    Button(action: generateAudioMuseAlchemy) {
                        Label(player.playlistGenIsGenerating ? "Generating" : "Generate Alchemy", systemImage: "atom")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!PlaylistGenerationActionPolicy.canStart(
                        isGenerating: player.playlistGenIsGenerating,
                        hasRequiredSelection: alchemySong != nil
                    ))
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
        guard PlaylistGenerationActionPolicy.canStart(
            isGenerating: player.playlistGenIsGenerating,
            hasRequiredSelection: alchemySong != nil
        ), let alchemySong else { return }
        didStartGeneration()
        player.startAudioMuseAlchemyPlaylistGeneration(for: alchemySong)
    }
}

private struct SonicTrackSearchPicker: View {
    let title: String
    @Binding var query: String
    @Binding var selectedSong: Song?
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

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
            } else if !results.isEmpty {
                VStack(spacing: WRhythmSpacing.xs) {
                    ForEach(results.prefix(5)) { song in
                        SonicTrackSelectionRow(song: song, isSelected: false) {
                            selectedSong = song
                            query = song.title
                            results = []
                        }
                    }
                }
            }
        }
        .task(id: query) {
            await search()
        }
    }

    @ViewBuilder
    private var searchField: some View {
#if os(watchOS)
        TextField("Search tracks", text: $query)
#else
        TextField("Search tracks", text: $query)
            .textFieldStyle(.roundedBorder)
#endif
    }

    private func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedSong == nil, trimmedQuery.count >= 2 else {
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
            let searchResult = try await NavidromeAPI.shared.search(query: trimmedQuery)
            guard !Task.isCancelled else { return }
            results = searchResult.song ?? []
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = "Search failed"
        }

        isSearching = false
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
                        TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: true) {
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

    private func playRadio(startingAt index: Int = 0) {
        let songs = downloadedSongs.compactMap { songId -> Song? in
            guard let downloaded = downloadManager.downloadedSongs[songId] else { return nil }
            return Song(
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

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs in radio")
            return
        }

        player.playQueue(songs, startingAt: index)
    }

    private func shuffleRadio() {
        let songs = downloadedSongs.compactMap { songId -> Song? in
            guard let downloaded = downloadManager.downloadedSongs[songId] else { return nil }
            return Song(
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

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs in radio")
            return
        }

        player.playQueueShuffled(songs)
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
