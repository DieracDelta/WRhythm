//
//  MetricKitReporter.swift
//  WRhythm
//

import Foundation

struct MetricKitPayloadFilePolicy: Sendable {
    static func filename(prefix: String, receivedAt: Date, index: Int) -> String {
        let timestamp = safeTimestamp(for: receivedAt)
        return "\(prefix)-\(timestamp)-\(index).json"
    }

    static func sanitizedFilename(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    static func safeTimestamp(for date: Date) -> String {
        ISO8601DateFormatter.wrhythmMetricKitFilename
            .string(from: date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}

private extension ISO8601DateFormatter {
    static let wrhythmMetricKitFilename: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

#if POWER_INFO && canImport(MetricKit)
import MetricKit

final class MetricKitReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitReporter()

    private let fileManager: FileManager
    private var hasStarted = false

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        sanitizeExistingPayloadFilenames()
        MXMetricManager.shared.add(self)
        print("📈 MetricKit reporter started. Payloads will be saved to: \(payloadDirectory.path)")
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        savePayloads(payloads, prefix: "metrics")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        savePayloads(payloads, prefix: "diagnostics")
    }

    private var payloadDirectory: URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("WRhythm", isDirectory: true)
            .appendingPathComponent("MetricKit", isDirectory: true)
    }

    private func savePayloads(_ payloads: [MXMetricPayload], prefix: String) {
        save(payloads.map { $0.jsonRepresentation() }, prefix: prefix)
    }

    private func savePayloads(_ payloads: [MXDiagnosticPayload], prefix: String) {
        save(payloads.map { $0.jsonRepresentation() }, prefix: prefix)
    }

    private func save(_ payloadData: [Data], prefix: String) {
        guard !payloadData.isEmpty else { return }

        do {
            try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        } catch {
            print("⚠️ Failed to create MetricKit payload directory: \(error.localizedDescription)")
            return
        }

        let receivedAt = Date()
        for (index, data) in payloadData.enumerated() {
            let filename = MetricKitPayloadFilePolicy.filename(prefix: prefix, receivedAt: receivedAt, index: index)
            let url = payloadDirectory.appendingPathComponent(filename, isDirectory: false)
            do {
                try data.write(to: url, options: .atomic)
                print("📈 Saved MetricKit \(prefix) payload: \(url.path)")
            } catch {
                print("⚠️ Failed to save MetricKit \(prefix) payload: \(error.localizedDescription)")
            }
        }
    }

    private func sanitizeExistingPayloadFilenames() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: payloadDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in contents where url.pathExtension == "json" {
            let safeName = MetricKitPayloadFilePolicy.sanitizedFilename(url.lastPathComponent)
            guard safeName != url.lastPathComponent else { continue }

            let destination = url.deletingLastPathComponent().appendingPathComponent(safeName, isDirectory: false)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }

            do {
                try fileManager.moveItem(at: url, to: destination)
                print("📈 Renamed MetricKit payload for export: \(destination.lastPathComponent)")
            } catch {
                print("⚠️ Failed to rename MetricKit payload: \(error.localizedDescription)")
            }
        }
    }
}
#else
final class MetricKitReporter {
    static let shared = MetricKitReporter()

    private init() {}

    func start() {}
}
#endif
