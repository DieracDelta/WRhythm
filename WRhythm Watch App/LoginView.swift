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
    @State private var showingHelpSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.accentColor)

                        Text("WRhythm")
                            .font(.title2.weight(.semibold))

                        Button(action: {
                            showingHelpSheet = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 8)

                    VStack(spacing: 12) {
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
                        } else {
                            Text("Login")
                        }
                    }
                    .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty || isLoading)
                    .padding(.top, 8)

                    Toggle(isOn: $deviceSyncManager.credentialSyncEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sync Credentials")
                                .font(.caption)
                            Text(deviceSyncManager.connectedDeviceNames.isEmpty ? "Looking for nearby WRhythm devices" : "Connected: \(deviceSyncManager.connectedDeviceNames.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    if showError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
                .padding()
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .wrhythmPageBackground()
        }
        .sheet(isPresented: $showingHelpSheet) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Credential Entry Tips")
                            .font(.headline)
                            .padding(.bottom, 4)

                        Text("For easier credential entry on Apple Watch:")
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Use Settings > Accessibility > Apple Watch Mirroring", systemImage: "applewatch")
                                .font(.caption2)

                            Label("This mirrors your watch to your iPhone screen", systemImage: "iphone")
                                .font(.caption2)

                            Label("Type credentials using your iPhone keyboard", systemImage: "keyboard")
                                .font(.caption2)
                        }
                        .padding(.leading)
                    }
                    .padding()
                }
                .navigationTitle("Help")
                .platformNavigationBarTitleDisplayModeInline()
            }
        }
        .onAppear {
            deviceSyncManager.requestCredentialSyncNow()
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

#Preview {
    LoginView()
}
