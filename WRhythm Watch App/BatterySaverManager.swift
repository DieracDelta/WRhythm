//
//  BatterySaverManager.swift
//  WRhythm Watch App
//
//  Created by Claude Code
//

import Foundation
import Combine
import WatchKit

class BatterySaverManager: ObservableObject {
    static let shared = BatterySaverManager()

    // Published state - all views can observe this
    @Published var isActive: Bool = false

    // Settings (stored in UserDefaults)
    @Published var autoModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoModeEnabled, forKey: "batterySaver_autoMode")
        }
    }

    @Published var manualModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(manualModeEnabled, forKey: "batterySaver_manualMode")
            updateActiveState()
        }
    }

    @Published var maxCachedViews: Int {
        didSet {
            UserDefaults.standard.set(maxCachedViews, forKey: "batterySaver_maxCachedViews")
        }
    }

    @Published var batteryCheckInterval: Int {
        didSet {
            UserDefaults.standard.set(batteryCheckInterval, forKey: "batterySaver_checkInterval")
            if autoModeEnabled {
                restartMonitoring()
            }
        }
    }

    private var batteryMonitorTimer: Timer?

    init() {
        // Load settings
        self.autoModeEnabled = UserDefaults.standard.bool(forKey: "batterySaver_autoMode")
        self.manualModeEnabled = UserDefaults.standard.bool(forKey: "batterySaver_manualMode")
        self.maxCachedViews = UserDefaults.standard.integer(forKey: "batterySaver_maxCachedViews")
        self.batteryCheckInterval = UserDefaults.standard.integer(forKey: "batterySaver_checkInterval")

        if maxCachedViews == 0 {
            maxCachedViews = 2 // Default
        }

        if batteryCheckInterval == 0 {
            batteryCheckInterval = 300 // Default: 5 minutes = 300 seconds
        } else if batteryCheckInterval < 60 {
            // Old format detected (minutes, likely 1-10)
            // Convert to seconds
            batteryCheckInterval = batteryCheckInterval * 60
            print("🔄 Migrated battery check interval from minutes to seconds: \(batteryCheckInterval)s")
        }

        // Start monitoring if auto mode enabled
        if autoModeEnabled {
            startMonitoring()
        }

        updateActiveState()
    }

    func toggleAutoMode(_ enabled: Bool) {
        autoModeEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
        updateActiveState()
    }

    private func startMonitoring() {
        // Check battery at configured interval (already in seconds)
        let intervalInSeconds = TimeInterval(batteryCheckInterval)
        batteryMonitorTimer = Timer.scheduledTimer(withTimeInterval: intervalInSeconds, repeats: true) { [weak self] _ in
            self?.checkBatteryLevel()
        }
        checkBatteryLevel() // Immediate check
        print("🔋 Battery monitoring started with \(batteryCheckInterval)s interval")
    }

    private func stopMonitoring() {
        batteryMonitorTimer?.invalidate()
        batteryMonitorTimer = nil
        print("🔋 Battery monitoring stopped")
    }

    private func restartMonitoring() {
        stopMonitoring()
        if autoModeEnabled {
            startMonitoring()
        }
    }

    private func checkBatteryLevel() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let batteryLevel = WKInterfaceDevice.current().batteryLevel

        // Activate if battery < 20%
        if batteryLevel >= 0 && batteryLevel < 0.2 {
            print("🔋 Low battery detected: \(Int(batteryLevel * 100))%")
            updateActiveState()
        }
    }

    private func updateActiveState() {
        let previousState = isActive

        // Manual override takes precedence
        if manualModeEnabled {
            isActive = true
        } else if autoModeEnabled {
            // Auto mode: check battery level
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
            let batteryLevel = WKInterfaceDevice.current().batteryLevel
            isActive = batteryLevel >= 0 && batteryLevel < 0.2
        } else {
            isActive = false
        }

        if previousState != isActive {
            print("🔋 Battery Saver Mode: \(isActive ? "ENABLED" : "DISABLED")")
            NotificationCenter.default.post(name: .batterySaverModeChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let batterySaverModeChanged = Notification.Name("batterySaverModeChanged")
}
