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
        List {
            Section {
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

            Section(header: Text("Appearance")) {
                Toggle(isOn: $darkModeEnabled) {
                    SettingsToggleLabel(
                        title: "Dark Mode",
                        subtitle: darkModeEnabled ? "Use dark appearance" : "Use light appearance",
                        systemImage: darkModeEnabled ? "moon.fill" : "sun.max"
                    )
                }
            }

            Section(header: Text("Downloads")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Concurrent Downloads")
                        .font(.caption)
                    HStack {
                        Text(downloadManager.maxConcurrentDownloads == 999 ? "∞" : "\(downloadManager.maxConcurrentDownloads)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 30, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: {
                                    downloadManager.maxConcurrentDownloads == 999 ? 17 : Double(downloadManager.maxConcurrentDownloads)
                                },
                                set: {
                                    downloadManager.maxConcurrentDownloads = $0 >= 17 ? 999 : Int($0)
                                }
                            ),
                            in: 1...17,
                            step: 1
                        )
                    }
                    Text(downloadManager.maxConcurrentDownloads == 999
                         ? "Unlimited - Required for fast background downloads"
                         : "Limited concurrent downloads (slower in background)")
                        .font(.caption2)
                        .foregroundColor(downloadManager.maxConcurrentDownloads == 999 ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default Playlist Gen Size")
                        .font(.caption)
                    HStack {
                        Text("\(radioDownloadCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 30, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(radioDownloadCount) },
                                set: { radioDownloadCount = Int($0) }
                            ),
                            in: 10...500,
                            step: 10
                        )
                    }
                    Text("Default number of songs for Playlist Gen")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Audio Quality")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Streaming Quality")
                        .font(.caption)

                    Picker("Streaming", selection: streamingQuality) {
                        ForEach(StreamingQuality.allCases, id: \.self) { quality in
                            Text(quality.label).tag(quality)
                        }
                    }

                    Text(streamingQuality.wrappedValue.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Download Quality")
                        .font(.caption)

                    Picker("Quality", selection: $selectedQuality) {
                        ForEach(AudioQuality.allCases, id: \.self) { quality in
                            Text("\(quality.label) (\(quality.rawValue)kbps)").tag(quality)
                        }
                    }
                    .disabled(api.transcodingSupported == false || downloadManager.isExecutingQualityChange)
                    .opacity((api.transcodingSupported == false || downloadManager.isExecutingQualityChange) ? 0.5 : 1.0)
                    .onChange(of: selectedQuality) { _, newValue in
                        // Only trigger if actually different from current setting
                        if newValue != downloadManager.audioQuality {
                            downloadManager.requestQualityChange(to: newValue)
                        }
                    }

                    // Show current quality description
                    Text(selectedQuality.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Transcoding status
                    if api.transcodingSupported == false {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("Server doesn't support transcoding")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    } else if downloadManager.isExecutingQualityChange {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Re-downloading songs...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Recheck transcoding support button
                Button(action: {
                    Task {
                        await api.checkTranscodingSupport()
                    }
                }) {
                    HStack {
                        if api.isCheckingTranscoding {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Check Server Capabilities")
                            .font(.caption)
                    }
                }
                .disabled(api.isCheckingTranscoding)
            }

            Section(header: Text("Offline")) {
                Toggle(isOn: $offlineMode) {
                    SettingsToggleLabel(
                        title: "Offline Mode",
                        subtitle: "Only show downloaded content",
                        systemImage: "wifi.slash"
                    )
                }
            }

            Section(header: Text("Devices")) {
                Toggle(isOn: $deviceSyncManager.syncModeEnabled) {
                    SettingsToggleLabel(
                        title: "Sync Mode",
                        subtitle: "Show and control playback on nearby WRhythm devices",
                        systemImage: "display.2"
                    )
                }

                Toggle(isOn: $deviceSyncManager.credentialSyncEnabled) {
                    SettingsToggleLabel(
                        title: "Sync Credentials",
                        subtitle: "Only fills empty logins on devices that also enabled this",
                        systemImage: "key"
                    )
                }

                SettingsInfoRow(
                    title: "Connected",
                    value: deviceSyncManager.connectedDeviceNames.isEmpty ? "No nearby devices" : deviceSyncManager.connectedDeviceNames.joined(separator: ", "),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }

            Section {
                Button(role: .destructive, action: {
                    presentedSheet = .logout
                    logoutConfirmationText = ""
                }) {
                    Text("Logout")
                }
            }
        }
        .navigationTitle("Settings")
        .wrhythmListSurface()
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
            NavigationView {
                ScrollView {
                    VStack(spacing: 8) {
                        // WARNING ICON
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                            .padding(.top, 4)

                        // CLEAR WARNING TEXT
                        Text("All Local Data Will Be Deleted")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)

                        Text("This will permanently delete:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)

                        // What gets deleted
                        VStack(alignment: .leading, spacing: 1) {
                            Text("• All downloaded music")
                            Text("• All playlists & metadata")
                            Text("• All local favorites")
                            Text("• Active downloads")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        Text("(Server data is NOT affected)")
                            .font(.caption2)
                            .foregroundColor(WRhythmTheme.success)
                            .italic()
                            .padding(.top, 2)

                        if let username = UserDefaults.standard.string(forKey: "navidrome_username") {
                            Text("User: \(username)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }

                        Text("Type LOGOUT to confirm")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 6)

                        TextField("Type LOGOUT", text: $logoutConfirmationText)
                            .platformAutocapitalizationCharacters()
                            .padding(.vertical, 6)

                        Button(action: {
                            api.logout()
                            presentedSheet = nil
                            logoutConfirmationText = ""
                        }) {
                            Text("Delete All Data & Logout")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(logoutConfirmationText != "LOGOUT")
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal)
                }
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
}

private enum SettingsSheet: String, Identifiable {
    case logout

    var id: String { rawValue }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            WRhythmIconBadge(systemImage: systemImage, tint: WRhythmTheme.accent, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(value)
                    .font(.caption2)
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
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            WRhythmIconBadge(systemImage: systemImage, tint: WRhythmTheme.accent, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
