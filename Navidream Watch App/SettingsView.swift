//
//  SettingsView.swift
//  Navidream Watch App
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
        .confirmationDialog("Logout", isPresented: $showingLogoutConfirmation) {
            Button("Logout", role: .destructive) {
                api.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to logout?")
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
