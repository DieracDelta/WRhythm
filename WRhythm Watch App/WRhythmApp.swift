//
//  WRhythmApp.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

@main
struct WRhythm_Watch_AppApp: App {
    @StateObject private var libraryDataManager = LibraryDataManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryDataManager)
        }
    }
}
