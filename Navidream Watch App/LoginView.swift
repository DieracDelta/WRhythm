//
//  LoginView.swift
//  Navidream Watch App
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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Navidream")
                        .font(.headline)
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
        .onAppear {
            serverURL = "https://office-desktop.tail5ca7.ts.net/navidrome/"
        }
    }

    private func login() {
        isLoading = true
        showError = false

        api.configure(baseURL: serverURL, username: username, password: password)

        Task {
            do {
                let success = try await api.ping()
                await MainActor.run {
                    isLoading = false
                    if success {
                        api.isAuthenticated = true
                    } else {
                        showError(message: "Authentication failed")
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
