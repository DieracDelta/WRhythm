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
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
