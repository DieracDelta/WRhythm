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
    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("radioDownloadCount") private var radioDownloadCount = 25
    @State private var showingLogoutConfirmation = false
    @State private var logoutConfirmationText = ""
    @State private var selectedQuality: AudioQuality = DownloadManager.shared.audioQuality

    var body: some View {
        List {
            Section {
                if let serverURL = UserDefaults.standard.string(forKey: "navidrome_url") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(serverURL)
                            .font(.caption2)
                            .lineLimit(2)
                    }
                }

                if let username = UserDefaults.standard.string(forKey: "navidrome_username") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(username)
                            .font(.caption2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                        .font(.caption2)
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
                    Text("Default Radio Size")
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
                    Text("Default number of songs for radio (can adjust per-radio)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Audio Quality")) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Offline Mode")
                            .font(.caption)
                        Text("Only show downloaded content")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive, action: {
                    showingLogoutConfirmation = true
                    logoutConfirmationText = ""
                }) {
                    Text("Logout")
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: offlineMode) { _, newValue in
            if newValue {
                // Stop playback when entering offline mode
                AudioPlayer.shared.stop()
                print("🔇 Stopped playback due to offline mode")
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
        .sheet(isPresented: $showingLogoutConfirmation) {
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
                            .foregroundColor(.green)
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
                            .textInputAutocapitalization(.characters)
                            .padding(.vertical, 6)

                        Button(action: {
                            api.logout()
                            showingLogoutConfirmation = false
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
                            showingLogoutConfirmation = false
                            logoutConfirmationText = ""
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
