import AppKit
import SwiftUI
import SoundControlCore

/// Click, press the keys you want, done. Escape cancels; Delete clears the shortcut.
struct ShortcutRecorder: View {
    let shortcut: KeyShortcut?
    let onChange: (KeyShortcut?) -> Void
    let onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: toggle) {
                    Text(buttonTitle)
                        .font(.body.monospaced())
                        .frame(minWidth: 130)
                }
                .controlSize(.regular)
                if shortcut != nil, !isRecording {
                    Button("Clear") { onChange(nil) }.buttonStyle(.borderless).font(.caption)
                }
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(Theme.warning)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var buttonTitle: String {
        if isRecording { return "Press keys…" }
        return shortcut?.displayString ?? "Click to record"
    }

    private func toggle() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        hint = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }

    private func handle(_ event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        switch Int(event.keyCode) {
        case kEscapeKeyCode where modifiers.isEmpty:
            stopRecording()
        case kDeleteKeyCode where modifiers.isEmpty:
            onChange(nil)
            stopRecording()
        default:
            let label = KeyShortcut.label(forKeyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers)
            guard let next = KeyShortcut(keyCode: Int(event.keyCode), modifiers: modifiers, label: label) else {
                hint = "Hold ⌘, ⌥ or ⌃ together with a key."
                return
            }
            onChange(next)
            stopRecording()
        }
    }
}

private let kEscapeKeyCode = 53
private let kDeleteKeyCode = 51
