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
    @ObservedObject private var batterySaver = BatterySaverManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("radioDownloadCount") private var radioDownloadCount = 25
    @State private var showingLogoutConfirmation = false
    @State private var logoutConfirmationText = ""

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

            Section(header: Text("Battery Saver")) {
                // Status indicator
                HStack {
                    Image(systemName: batterySaver.isActive ? "bolt.slash.fill" : "bolt.fill")
                        .foregroundColor(batterySaver.isActive ? .orange : .green)
                    Text("Battery Saver")
                        .font(.caption)
                    Spacer()
                    Text(batterySaver.isActive ? "Active" : "Inactive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Manual toggle
                Toggle(isOn: $batterySaver.manualModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual Mode")
                            .font(.caption)
                        Text("Force enable/disable")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Auto mode toggle
                Toggle(isOn: Binding(
                    get: { batterySaver.autoModeEnabled },
                    set: { batterySaver.toggleAutoMode($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Mode")
                            .font(.caption)
                        Text("Enable at low battery (<20%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Max cached views stepper
                VStack(spacing: 4) {
                    Stepper(value: $batterySaver.maxCachedViews, in: 1...CachedView.allCases.count) {
                        HStack {
                            Text("Cached Views")
                                .font(.caption2)
                            Spacer()
                            Text("\(batterySaver.maxCachedViews)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep only the \(batterySaver.maxCachedViews) most recently used \(batterySaver.maxCachedViews == 1 ? "view" : "views") in memory")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("• Lower = less memory, better battery")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("• Higher = smoother navigation")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("• Recommended: 2-3 views")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 2)
                }

                // Battery check interval steppers (only visible when auto mode enabled)
                if batterySaver.autoModeEnabled {
                    VStack(spacing: 4) {
                        Text("Check Interval")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Convert total seconds to h/m/s for display
                        let totalSeconds = batterySaver.batteryCheckInterval
                        let hours = totalSeconds / 3600
                        let minutes = (totalSeconds % 3600) / 60
                        let seconds = totalSeconds % 60

                        // Hours stepper (0-23)
                        Stepper(value: Binding(
                            get: { hours },
                            set: { newHours in
                                let newTotal = (newHours % 24) * 3600 + minutes * 60 + seconds
                                batterySaver.batteryCheckInterval = max(10, newTotal)
                            }
                        ), in: 0...23) {
                            HStack {
                                Text("Hours")
                                    .font(.caption2)
                                Spacer()
                                Text("\(hours)h")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        // Minutes stepper (0-59)
                        Stepper(value: Binding(
                            get: { minutes },
                            set: { newMinutes in
                                let newTotal = hours * 3600 + (newMinutes % 60) * 60 + seconds
                                batterySaver.batteryCheckInterval = max(10, newTotal)
                            }
                        ), in: 0...59) {
                            HStack {
                                Text("Minutes")
                                    .font(.caption2)
                                Spacer()
                                Text("\(minutes)m")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        // Seconds stepper (0-59)
                        Stepper(value: Binding(
                            get: { seconds },
                            set: { newSeconds in
                                let newTotal = hours * 3600 + minutes * 60 + (newSeconds % 60)
                                batterySaver.batteryCheckInterval = max(10, newTotal)
                            }
                        ), in: 0...59) {
                            HStack {
                                Text("Seconds")
                                    .font(.caption2)
                                Spacer()
                                Text("\(seconds)s")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        // Total display
                        Text("Total: \(formatInterval(totalSeconds))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)

                        // Description
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How often to check battery level when auto mode is enabled")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("• Longer intervals = better battery life")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("• Shorter intervals = faster response")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("• Recommended: 5-10 minutes")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    }
                }

                // Explanation
                Text("Reduces battery usage by:\n• Disabling album art\n• Limiting cached views\n• Reducing memory usage")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
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
        .onChange(of: offlineMode) { newValue in
            if newValue {
                // Stop playback when entering offline mode
                AudioPlayer.shared.stop()
                print("🔇 Stopped playback due to offline mode")
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

    private func formatInterval(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60

        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 || parts.isEmpty { parts.append("\(s)s") }

        return parts.joined(separator: " ")
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
