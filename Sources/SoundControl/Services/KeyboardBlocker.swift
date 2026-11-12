import AppKit
import CoreGraphics
import OSLog

/// Swallows every keyboard event (keys, modifiers, media and brightness keys) while running.
/// Unlike `InputMonitor` this tap filters events, so it needs Accessibility, not just Input Monitoring.
/// The power button and Touch ID are handled below the event system and cannot be blocked.
@MainActor
final class KeyboardBlocker {
    static let permissionMessage = "Keyboard lock needs Accessibility permission. Turn on Sound Control in System Settings → Privacy & Security → Accessibility, then try again."

    /// `NSEvent.EventType.systemDefined`: media, volume and brightness keys. CGEventType has no case for it.
    private static let systemDefinedType: UInt32 = 14
    private static let blockedTypes: [UInt32] = [
        CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue, systemDefinedType
    ]

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.pond.soundcontrol", category: "KeyboardBlocker")

    /// While true, keys reach the system instead of being dropped, so the owner can type a login password.
    var passesKeys = false

    var isRunning: Bool { tap != nil }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the macOS prompt that leads to the Accessibility pane.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Returns false when macOS refuses the tap (usually missing Accessibility).
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = Self.blockedTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, context in
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let context {
                    let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { blocker.reenable() }
                }
                return Unmanaged.passUnretained(event)
            default:
                return KeyboardBlocker.allowsKeys(context) ? Unmanaged.passUnretained(event) : nil
            }
        }, userInfo: context) else {
            logger.error("Keyboard tap was refused")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        tap = nil
        source = nil
    }

    private func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// The tap callback runs on the main run loop, the same actor that owns `passesKeys`.
    private static func allowsKeys(_ context: UnsafeMutableRawPointer?) -> Bool {
        guard let context else { return false }
        return MainActor.assumeIsolated {
            Unmanaged<KeyboardBlocker>.fromOpaque(context).takeUnretainedValue().passesKeys
        }
    }
}
