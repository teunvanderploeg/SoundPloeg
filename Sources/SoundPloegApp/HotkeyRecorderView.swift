import AppKit
import Carbon
import SoundPloegCore
import SwiftUI

struct HotkeyRecorderView: View {
    let currentShortcut: HotkeyShortcut
    let onShortcutRecorded: (HotkeyShortcut) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Hotkey")
            Spacer()
            Text(currentShortcut.displayName)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Button(isRecording ? "Press keys..." : "Record") {
                toggleRecording()
            }
            .help("Record a shortcut with Command, Option, or Control. Press Escape to cancel.")
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let modifiers = carbonModifiers(from: event.modifierFlags)
            let code = UInt32(event.keyCode)
            let display = displayName(for: event)

            // Shift alone should not turn normal typing into a global shortcut.
            guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
            onShortcutRecorded(HotkeyShortcut(keyCode: code, carbonModifiers: modifiers, displayName: display))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var output: UInt32 = 0
        if flags.contains(.command) { output |= UInt32(cmdKey) }
        if flags.contains(.option) { output |= UInt32(optionKey) }
        if flags.contains(.control) { output |= UInt32(controlKey) }
        if flags.contains(.shift) { output |= UInt32(shiftKey) }
        return output
    }

    private func displayName(for event: NSEvent) -> String {
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("⌘") }
        if event.modifierFlags.contains(.option) { parts.append("⌥") }
        if event.modifierFlags.contains(.control) { parts.append("⌃") }
        if event.modifierFlags.contains(.shift) { parts.append("⇧") }

        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓"
        ]
        let key = specialKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        return parts.joined() + key
    }
}
