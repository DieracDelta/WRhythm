//
//  LoginView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var api = NavidromeAPI.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var presentedSheet: LoginSheet?

    var body: some View {
        NavigationStack {
            WRhythmScreen(horizontalPadding: WRhythmSpacing.md) {
                WRhythmFeatureHeader(
                    title: "WRhythm",
                    subtitle: "Connect to your Navidrome library",
                    systemImage: "waveform.circle.fill",
                    tint: WRhythmTheme.accent
                )

                WRhythmGlassCard {
                    VStack(spacing: WRhythmSpacing.md) {
                        VStack(spacing: WRhythmSpacing.sm) {
                            TextField("Server URL", text: $serverURL)
                                .textContentType(.URL)
                                .platformAutocapitalizationNever()

                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .platformAutocapitalizationNever()

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                        }
                        .platformSearchTextFieldStyle()

                        Button(action: login) {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Login")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WRhythmTheme.accent)
                        .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty || isLoading)

                        if showError {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundColor(WRhythmTheme.danger)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(WRhythmSpacing.xs)
                                .background(WRhythmTheme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
                        }
                    }
                }

                credentialSyncCard

                Button(action: {
                    presentedSheet = .help
                }) {
                    Label("Credential Help", systemImage: "info.circle")
                        .font(WRhythmTypography.controlLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(WRhythmTheme.secondaryAccent)
                .frame(maxWidth: 460)
            }
            .navigationTitle("Login")
            .platformNavigationBarTitleDisplayModeInline()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .help:
            NavigationStack {
                WRhythmScreen {
                    WRhythmCard {
                        VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                            Text("Credential Entry Tips")
                                .font(.headline)

                            Text("For easier credential entry on Apple Watch:")
                                .font(WRhythmTypography.rowSubtitle)

                            VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                                Label("Use Apple Watch Mirroring", systemImage: "applewatch")
                                Label("Type from your iPhone keyboard", systemImage: "keyboard")
                            }
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .navigationTitle("Help")
                .platformNavigationBarTitleDisplayModeInline()
            }
            }
        }
        .onAppear {
            deviceSyncManager.requestCredentialSyncNow()
        }
    }

    private var credentialSyncStatusText: String {
        deviceSyncManager.connectedDeviceNames.isEmpty
            ? "Nearby login sync"
            : "Synced with \(deviceSyncManager.connectedDeviceNames.joined(separator: ", "))"
    }

    @ViewBuilder
    private var credentialSyncCard: some View {
        WRhythmCard {
#if os(watchOS)
            VStack(alignment: .leading, spacing: WRhythmSpacing.sm) {
                Text("Sync Login")
                    .font(WRhythmTypography.rowTitle)
                    .lineLimit(1)

                Text(credentialSyncStatusText)
                    .font(WRhythmTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Toggle("Sync Login", isOn: $deviceSyncManager.credentialSyncEnabled)
                    .labelsHidden()
                    .tint(WRhythmTheme.secondaryAccent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Sync Login")
            }
#else
            Toggle(isOn: $deviceSyncManager.credentialSyncEnabled) {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                    Text("Sync Login")
                        .font(WRhythmTypography.rowTitle)
                    Text(credentialSyncStatusText)
                        .font(WRhythmTypography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(WRhythmTheme.secondaryAccent)
#endif
        }
    }

    private func login() {
        isLoading = true
        showError = false

        Task {
            do {
                let success = try await api.validateAndConfigure(
                    baseURL: serverURL,
                    username: username,
                    password: password
                )
                await MainActor.run {
                    isLoading = false
                    if success {
                        print("✅ Login successful")
                    } else {
                        showError(message: "Unable to authenticate. Please check:\n• Username and password are correct\n• Server URL is valid\n• Server is running and accessible")
                    }
                }
            } catch let error as URLError {
                await MainActor.run {
                    isLoading = false
                    switch error.code {
                    case .notConnectedToInternet, .networkConnectionLost:
                        showError(message: "No internet connection. Please check your network and try again.")
                    case .timedOut:
                        showError(message: "Connection timed out. Check your internet or if the server is running.")
                    case .cannotFindHost, .cannotConnectToHost:
                        showError(message: "Cannot reach server. Check the server URL and verify it's accessible.")
                    default:
                        showError(message: "Network error: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    showError(message: error.localizedDescription)
                }
            }
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

private enum LoginSheet: String, Identifiable {
    case help

    var id: String { rawValue }
}

#Preview {
    LoginView()
}
