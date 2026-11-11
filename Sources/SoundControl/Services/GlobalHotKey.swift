import AppKit
import Carbon.HIToolbox
import SoundControlCore

/// One system-wide hot key, alive as long as the app (the owner never removes its event handler). Carbon's hot key API needs no Accessibility or Input Monitoring permission.
@MainActor
final class GlobalHotKey {
    private static let signature: OSType = 0x5343_4B59 // 'SCKY'

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Replaces the registered shortcut. Returns false when macOS refuses it, usually because another app owns it.
    @discardableResult
    func register(_ shortcut: KeyShortcut?) -> Bool {
        unregister()
        guard let shortcut else { return true }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbonFlags, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}

extension KeyModifiers {
    var carbonFlags: UInt32 {
        var flags = 0
        if contains(.command) { flags |= cmdKey }
        if contains(.option) { flags |= optionKey }
        if contains(.control) { flags |= controlKey }
        if contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        self = result
    }
}
