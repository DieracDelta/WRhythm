//
//  SettingsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var api = NavidromeAPI.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("radioDownloadCount") private var radioDownloadCount = 25
    @State private var presentedSheet: SettingsSheet?
    @State private var logoutConfirmationText = ""
    @State private var selectedQuality: AudioQuality = DownloadManager.shared.audioQuality
    @AppStorage("streamingQuality") private var streamingQualityRaw = StreamingQuality.platformDefault.rawValue
    @AppStorage("darkModeEnabled") private var darkModeEnabled = true

    private var streamingQuality: Binding<StreamingQuality> {
        Binding {
            StreamingQuality(rawValue: streamingQualityRaw) ?? .platformDefault
        } set: { newValue in
            streamingQualityRaw = newValue.rawValue
        }
    }

    var body: some View {
        settingsRoot
        .onChange(of: offlineMode) { _, newValue in
            if newValue {
                deviceSyncManager.syncModeEnabled = false
                // Stop playback when entering offline mode
                AudioPlayer.shared.stop()
                print("🔇 Stopped playback due to offline mode")
            }
        }
        .onChange(of: deviceSyncManager.syncModeEnabled) { _, newValue in
            if newValue {
                offlineMode = false
            }
        }
        .onChange(of: downloadManager.audioQuality) { _, newValue in
            // Sync picker with actual quality (e.g., after migration resume)
            if selectedQuality != newValue {
                selectedQuality = newValue
            }
        }
        .onChange(of: downloadManager.showQualityChangePrompt) { _, showing in
            // If prompt was dismissed without action (e.g., cancelled), reset picker
            if !showing && downloadManager.pendingQualityChange == nil {
                selectedQuality = downloadManager.audioQuality
            }
        }
        .alert("Re-download Required", isPresented: $downloadManager.showQualityChangePrompt) {
            Button("Re-download All", role: .destructive) {
                Task {
                    await downloadManager.executeQualityChange()
                }
            }
            Button("Cancel", role: .cancel) {
                downloadManager.cancelQualityChange()
                selectedQuality = downloadManager.audioQuality  // Reset picker
            }
        } message: {
            if let pending = downloadManager.pendingQualityChange {
                Text("Changing quality to \(pending.label) will delete \(downloadManager.downloadedSongs.count) downloaded songs and re-download them. Active downloads will be cancelled.")
            } else {
                Text("This will re-download all songs in the new quality.")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .logout:
                NavigationStack {
                    WRhythmScreen {
                        WRhythmFeatureHeader(
                            title: "Delete Local Data",
                            subtitle: "Server data is not affected",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: WRhythmTheme.danger
                        )

                        WRhythmCard {
                            VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                                Text("This will permanently delete:")
                                    .font(WRhythmTypography.rowTitle)

                                VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                                    Text("All downloaded music")
                                    Text("All playlists and metadata")
                                    Text("All local favorites")
                                    Text("Active downloads")
                                }
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundColor(.secondary)

                                if let username = UserDefaults.standard.string(forKey: "navidrome_username") {
                                    Text("User: \(username)")
                                        .font(WRhythmTypography.metadata)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        WRhythmGlassCard {
                            VStack(spacing: WRhythmSpacing.sm) {
                                Text("Type LOGOUT to confirm")
                                    .font(WRhythmTypography.controlLabel)
                                    .foregroundColor(WRhythmTheme.danger)

                                TextField("Type LOGOUT", text: $logoutConfirmationText)
                                    .platformAutocapitalizationCharacters()
                                    .platformSearchTextFieldStyle()

                                Button(action: {
                                    api.logout()
                                    presentedSheet = nil
                                    logoutConfirmationText = ""
                                }) {
                                    Text("Delete All Data & Logout")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(WRhythmTheme.danger)
                                .disabled(logoutConfirmationText != "LOGOUT")
                            }
                        }
                    }
                    .navigationTitle("Confirm Logout")
                    .platformNavigationBarTitleDisplayModeInline()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                presentedSheet = nil
                                logoutConfirmationText = ""
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var settingsRoot: some View {
#if os(macOS)
        WRhythmScreen(horizontalPadding: WRhythmSpacing.xl, verticalPadding: WRhythmSpacing.xl) {
            WRhythmFeatureHeader(
                title: "Settings",
                subtitle: "Playback, downloads, and device sync",
                systemImage: "gearshape.fill"
            )

            SettingsPanel(title: "Account", systemImage: "person.crop.circle") {
                accountSettingsContent
            }

            SettingsPanel(title: "Appearance", systemImage: darkModeEnabled ? "moon.fill" : "sun.max") {
                appearanceSettingsContent
            }

            SettingsPanel(title: "Playback", systemImage: "play.circle.fill") {
                playbackSettingsContent
            }

            SettingsPanel(title: "Downloads", systemImage: "arrow.down.circle.fill") {
                downloadsSettingsContent
            }

            SettingsPanel(title: "Playlist Gen", systemImage: "wand.and.stars") {
                playlistGenSettingsContent
            }

            SettingsPanel(title: "Offline", systemImage: "wifi.slash") {
                offlineSettingsContent
            }

            SettingsPanel(title: "Devices", systemImage: "display.2") {
                deviceSettingsContent
            }

            SettingsPanel(title: "Account Actions", systemImage: "rectangle.portrait.and.arrow.right", tint: WRhythmTheme.danger) {
                logoutSettingsContent
            }
        }
        .navigationTitle("Settings")
#else
        List {
            Section {
                accountSettingsContent
            }

            Section(header: Text("Appearance")) {
                appearanceSettingsContent
            }

            Section(header: Text("Playback")) {
                playbackSettingsContent
            }

            Section(header: Text("Downloads")) {
                downloadsSettingsContent
            }

            Section(header: Text("Playlist Gen")) {
                playlistGenSettingsContent
            }

            Section(header: Text("Offline")) {
                offlineSettingsContent
            }

            Section(header: Text("Devices")) {
                deviceSettingsContent
            }

            Section {
                logoutSettingsContent
            }
        }
        .navigationTitle("Settings")
        .wrhythmListSurface()
#endif
    }

    @ViewBuilder
    private var accountSettingsContent: some View {
        if let serverURL = UserDefaults.standard.string(forKey: "navidrome_url") {
            SettingsInfoRow(title: "Server", value: serverURL, systemImage: "server.rack")
        }

        if let username = UserDefaults.standard.string(forKey: "navidrome_username") {
            SettingsInfoRow(title: "Username", value: username, systemImage: "person.crop.circle")
        }

        SettingsInfoRow(
            title: "Version",
            value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))",
            systemImage: "app.badge"
        )
    }

    @ViewBuilder
    private var appearanceSettingsContent: some View {
        Toggle(isOn: $darkModeEnabled) {
            SettingsToggleLabel(
                title: "Dark Mode"
            )
        }
    }

    @ViewBuilder
    private var playbackSettingsContent: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            Text("Streaming Quality")
                .font(WRhythmTypography.controlLabel)

            Picker("Streaming", selection: streamingQuality) {
                ForEach(StreamingQuality.allCases, id: \.self) { quality in
                    Text(quality.label).tag(quality)
                }
            }

            Text(streamingQuality.wrappedValue.description)
                .font(WRhythmTypography.metadata)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var downloadsSettingsContent: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            Text("Download Quality")
                .font(WRhythmTypography.controlLabel)

            Picker("Quality", selection: $selectedQuality) {
                ForEach(AudioQuality.allCases, id: \.self) { quality in
                    Text("\(quality.label) (\(quality.rawValue)kbps)").tag(quality)
                }
            }
            .disabled(api.transcodingSupported == false || downloadManager.isExecutingQualityChange)
            .opacity((api.transcodingSupported == false || downloadManager.isExecutingQualityChange) ? 0.5 : 1.0)
            .onChange(of: selectedQuality) { _, newValue in
                if newValue != downloadManager.audioQuality {
                    downloadManager.requestQualityChange(to: newValue)
                }
            }

            Text(selectedQuality.description)
                .font(WRhythmTypography.metadata)
                .foregroundColor(.secondary)

            if api.transcodingSupported == false {
                HStack(spacing: WRhythmSpacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(WRhythmTheme.warning)
                    Text("Server doesn't support transcoding")
                }
                .font(WRhythmTypography.metadata)
                .foregroundColor(WRhythmTheme.warning)
            } else if downloadManager.isExecutingQualityChange {
                HStack(spacing: WRhythmSpacing.xxs) {
                    SettingsInlineProgressView()
                    Text("Re-downloading songs...")
                        .foregroundColor(.secondary)
                }
                .font(WRhythmTypography.metadata)
            }
        }

        SettingsSliderRow(
            title: "Concurrent Downloads",
            valueText: downloadManager.maxConcurrentDownloads == 999 ? "∞" : "\(downloadManager.maxConcurrentDownloads)",
            detailText: downloadManager.maxConcurrentDownloads == 999
                ? "Unlimited - required for fast background downloads"
                : "Limited concurrent downloads",
            detailColor: downloadManager.maxConcurrentDownloads == 999 ? WRhythmTheme.success : .secondary,
            value: concurrentDownloadSliderValue,
            range: 1...17,
            step: 1
        )

        Button(action: {
            Task {
                await api.checkTranscodingSupport()
            }
        }) {
            HStack(spacing: WRhythmSpacing.xs) {
                if api.isCheckingTranscoding {
                    SettingsInlineProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text("Check Server Capabilities")
                    .font(WRhythmTypography.controlLabel)
            }
        }
        .disabled(api.isCheckingTranscoding)
    }

    @ViewBuilder
    private var playlistGenSettingsContent: some View {
        SettingsSliderRow(
            title: "Default Playlist Gen Size",
            valueText: "\(radioDownloadCount)",
            detailText: "Default number of songs for generated playlists",
            detailColor: .secondary,
            value: playlistGenCountSliderValue,
            range: 10...500,
            step: 10
        )
    }

    @ViewBuilder
    private var offlineSettingsContent: some View {
        Toggle(isOn: $offlineMode) {
            SettingsToggleLabel(
                title: "Offline Mode",
                subtitle: "Only show downloaded content"
            )
        }
    }

    @ViewBuilder
    private var deviceSettingsContent: some View {
        Toggle(isOn: $deviceSyncManager.syncModeEnabled) {
            SettingsToggleLabel(
                title: "Sync nearby devices",
                subtitle: "Show and control playback on nearby WRhythm devices"
            )
        }

        Toggle(isOn: $deviceSyncManager.credentialSyncEnabled) {
            SettingsToggleLabel(
                title: "Sync Credentials",
                subtitle: "Only fills empty logins on devices that also enabled this"
            )
        }

        SettingsInfoRow(
            title: "Connected",
            value: deviceSyncManager.connectedDeviceNames.isEmpty ? "No nearby devices" : deviceSyncManager.connectedDeviceNames.joined(separator: ", "),
            systemImage: "point.3.connected.trianglepath.dotted"
        )
    }

    @ViewBuilder
    private var logoutSettingsContent: some View {
        Button(role: .destructive, action: {
            presentedSheet = .logout
            logoutConfirmationText = ""
        }) {
            Text("Logout")
        }
    }

    private var concurrentDownloadSliderValue: Binding<Double> {
        Binding {
            downloadManager.maxConcurrentDownloads == 999 ? 17 : Double(downloadManager.maxConcurrentDownloads)
        } set: { newValue in
            downloadManager.maxConcurrentDownloads = newValue >= 17 ? 999 : Int(newValue)
        }
    }

    private var playlistGenCountSliderValue: Binding<Double> {
        Binding {
            Double(radioDownloadCount)
        } set: { newValue in
            radioDownloadCount = Int(newValue)
        }
    }
}

private enum SettingsSheet: String, Identifiable {
    case logout

    var id: String { rawValue }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = WRhythmTheme.accent
    private let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color = WRhythmTheme.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        WRhythmCard(style: .glass) {
            VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                HStack(spacing: WRhythmSpacing.sm) {
                    WRhythmIconBadge(systemImage: systemImage, tint: tint, size: 34)

                    Text(title)
                        .font(WRhythmTypography.featureTitle)
                }

                VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                    content
                }
            }
        }
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let valueText: String
    let detailText: String
    let detailColor: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(WRhythmTypography.controlLabel)

                Spacer(minLength: WRhythmSpacing.sm)

                Text(valueText)
                    .font(WRhythmTypography.controlLabel)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range, step: step)
                .tint(WRhythmTheme.accent)

            Text(detailText)
                .font(WRhythmTypography.metadata)
                .foregroundColor(detailColor)
        }
    }
}

private struct SettingsInlineProgressView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: 16, height: 16)
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            WRhythmIconBadge(systemImage: systemImage, tint: WRhythmTheme.accent, size: 32)

            VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                Text(title)
                    .font(WRhythmTypography.controlLabel)
                Text(value)
                    .font(WRhythmTypography.metadata)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsToggleLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
            Text(title)
                .font(WRhythmTypography.controlLabel)
            if let subtitle {
                Text(subtitle)
                    .font(WRhythmTypography.metadata)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
