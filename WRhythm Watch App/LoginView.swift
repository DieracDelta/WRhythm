//
//  LoginView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var api = NavidromeAPI.shared
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
                VStack(spacing: 12) {
                    HStack {
                        Text("WRhythm")
                            .font(.headline)

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

                    TextField("Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)

                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .textContentType(.password)

                    Button(action: login) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Login")
                        }
                    }
                    .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty || isLoading)
                    .padding(.top, 8)

                    if showError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
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
                .navigationBarTitleDisplayMode(.inline)
            }
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
