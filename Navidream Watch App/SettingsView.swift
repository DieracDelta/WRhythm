//
//  SettingsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var api = NavidromeAPI.shared
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

            Section {
                Button(role: .destructive, action: {
                    showingLogoutConfirmation = true
                }) {
                    Text("Logout")
                }
            }
        }
        .navigationTitle("Settings")
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
