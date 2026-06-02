//
//  MacSpacebarPlaybackShortcut.swift
//  WRhythm
//

enum SpacebarPlaybackShortcutPolicy {
    enum EventPhase: Sendable {
        case keyDown
        case keyUp
        case other
    }

    enum Decision: Sendable, Equatable {
        case passThrough
        case consume
        case toggleAndConsume
    }

    static func decision(
        isSpacebar: Bool,
        eventPhase: EventPhase,
        isRepeat: Bool,
        hasDisallowedModifiers: Bool,
        responderAllowsPlaybackShortcut: Bool
    ) -> Decision {
        guard isSpacebar, !hasDisallowedModifiers, responderAllowsPlaybackShortcut else {
            return .passThrough
        }

        switch eventPhase {
        case .keyDown:
            return isRepeat ? .consume : .toggleAndConsume
        case .keyUp:
            return .consume
        case .other:
            return .passThrough
        }
    }
}

#if os(macOS)
import AppKit
import SwiftUI

struct MacSpacebarPlaybackShortcut: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installIfNeeded()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.installIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        private var monitor: Any?

        deinit {
            uninstall()
        }

        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let decision = SpacebarPlaybackShortcutPolicy.decision(
                isSpacebar: event.keyCode == 49 || event.charactersIgnoringModifiers == " ",
                eventPhase: eventPhase(for: event),
                isRepeat: event.isARepeat,
                hasDisallowedModifiers: hasDisallowedModifiers(event.modifierFlags),
                responderAllowsPlaybackShortcut: shouldHandleSpacebar(for: NSApp.keyWindow?.firstResponder)
            )

            switch decision {
            case .passThrough:
                return event
            case .consume:
                return nil
            case .toggleAndConsume:
                Task { @MainActor in
                    PlaybackKeyboardActions.togglePlayback()
                }
                return nil
            }
        }

        private func eventPhase(for event: NSEvent) -> SpacebarPlaybackShortcutPolicy.EventPhase {
            switch event.type {
            case .keyDown:
                return .keyDown
            case .keyUp:
                return .keyUp
            default:
                return .other
            }
        }

        private func hasDisallowedModifiers(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
            !modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
                .isEmpty
        }

        private func shouldHandleSpacebar(for responder: NSResponder?) -> Bool {
            var current = responder
            while let responder = current {
                if responder is NSTextView
                    || responder is NSTextField
                    || responder is NSSearchField
                    || responder is NSComboBox {
                    return false
                }

                if let view = responder as? NSView {
                    current = view.superview
                } else {
                    current = nil
                }
            }
            return true
        }
    }
}

extension View {
    func macSpacebarPlaybackShortcut() -> some View {
        background {
            MacSpacebarPlaybackShortcut()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
#endif
