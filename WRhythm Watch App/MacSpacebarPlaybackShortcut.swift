//
//  MacSpacebarPlaybackShortcut.swift
//  WRhythm
//

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
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.keyCode == 49 || event.charactersIgnoringModifiers == " " else {
                return event
            }
            guard !event.isARepeat else {
                return nil
            }
            guard event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
                .isEmpty else {
                return event
            }
            guard shouldHandleSpacebar(for: NSApp.keyWindow?.firstResponder) else {
                return event
            }

            Task { @MainActor in
                PlaybackKeyboardActions.togglePlayback()
            }
            return nil
        }

        private func shouldHandleSpacebar(for responder: NSResponder?) -> Bool {
            var current = responder
            while let responder = current {
                if responder is NSTextView
                    || responder is NSTextField
                    || responder is NSSearchField
                    || responder is NSComboBox
                    || responder is NSSlider
                    || responder is NSButton
                    || responder is NSSegmentedControl
                    || responder is NSPopUpButton {
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
