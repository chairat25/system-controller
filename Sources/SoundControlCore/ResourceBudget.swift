import Foundation

/// How much memory the system has left, as macOS reports it to apps.
public enum MemoryPressure: Int, Sendable, Comparable {
    case normal
    case warning
    case critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The owner's choice of how the app reacts to a busy or struggling Mac. Kept on this Mac only.
public enum ResourceSaving: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Slows down only while the Mac is hot, on Low Power Mode, short of memory or busy.
    case auto
    /// Always runs lighter, for an older or slower Mac.
    case always
    /// Never slows down.
    case off

    public static let `default` = ResourceSaving.auto

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "Automatic"
        case .always: "Always save"
        case .off: "Off"
        }
    }
}

/// What the Mac reports about its own state, read by the app every few seconds.
public struct ResourceSignals: Equatable, Sendable {
    /// `ProcessInfo.ThermalState` raw value: 0 nominal, 1 fair, 2 serious, 3 critical.
    public let thermalState: Int
    public let isLowPowerMode: Bool
    public let memory: MemoryPressure
    /// One-minute load average divided by the number of CPU cores. Above 1, work is waiting for a free core.
    public let loadPerCore: Double

    public static let calm = ResourceSignals(thermalState: 0, isLowPowerMode: false, memory: .normal, loadPerCore: 0)

    public init(thermalState: Int, isLowPowerMode: Bool, memory: MemoryPressure, loadPerCore: Double) {
        self.thermalState = thermalState
        self.isLowPowerMode = isLowPowerMode
        self.memory = memory
        self.loadPerCore = loadPerCore.isFinite ? max(loadPerCore, 0) : 0
    }
}

/// How hard the app may work right now.
public enum ResourceLevel: Int, Sendable, Comparable {
    case full
    case saving
    case minimal

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .full: "Full speed"
        case .saving: "Saving resources"
        case .minimal: "Minimal"
        }
    }
}

/// Why the app is running lighter, shown next to the level.
public enum ResourceReason: String, Sendable, CaseIterable {
    case chosen
    case hot
    case veryHot
    case lowPower
    case memoryLow
    case memoryCritical
    case busy
    case veryBusy

    var level: ResourceLevel {
        switch self {
        case .chosen, .hot, .lowPower, .memoryLow, .busy: .saving
        case .veryHot, .memoryCritical, .veryBusy: .minimal
        }
    }

    public var title: String {
        switch self {
        case .chosen: "Always save is on"
        case .hot: "The Mac is hot"
        case .veryHot: "The Mac is very hot"
        case .lowPower: "Low Power Mode"
        case .memoryLow: "Memory is low"
        case .memoryCritical: "Memory is almost full"
        case .busy: "The CPU is busy"
        case .veryBusy: "The CPU is overloaded"
        }
    }
}

/// How fast the desktop mascots animate and how often the app polls, for the Mac's current state. Pure value
/// type: the app reads the signals, this decides.
public struct ResourceBudget: Equatable, Sendable {
    static let seriousThermal = 2
    static let criticalThermal = 3
    static let busyLoad = 1.0
    static let overloadedLoad = 2.0
    /// A busy CPU must drop this far below the threshold before the level goes back up, so it does not flap.
    static let loadHysteresis = 0.2

    public let level: ResourceLevel
    /// Every reason that applies, in a fixed order.
    public let reasons: [ResourceReason]

    public static let full = ResourceBudget(level: .full, reasons: [])

    public static func decide(_ signals: ResourceSignals, preference: ResourceSaving,
                              previous: ResourceBudget? = nil) -> ResourceBudget {
        guard preference != .off else { return .full }
        let wasBusy = previous?.reasons.contains { $0 == .busy || $0 == .veryBusy } ?? false
        let slack = wasBusy ? loadHysteresis : 0
        var found: Set<ResourceReason> = []
        if preference == .always { found.insert(.chosen) }
        if signals.thermalState >= criticalThermal {
            found.insert(.veryHot)
        } else if signals.thermalState >= seriousThermal {
            found.insert(.hot)
        }
        if signals.isLowPowerMode { found.insert(.lowPower) }
        switch signals.memory {
        case .critical: found.insert(.memoryCritical)
        case .warning: found.insert(.memoryLow)
        case .normal: break
        }
        if signals.loadPerCore >= overloadedLoad - slack {
            found.insert(.veryBusy)
        } else if signals.loadPerCore >= busyLoad - slack {
            found.insert(.busy)
        }
        let reasons = ResourceReason.allCases.filter(found.contains)
        return ResourceBudget(level: reasons.map(\.level).max() ?? .full, reasons: reasons)
    }

    /// Seconds between frames while a desktop mascot walks.
    public var walkingInterval: TimeInterval {
        switch level {
        case .full: 1.0 / 24
        case .saving: 1.0 / 15
        case .minimal: 1.0 / 10
        }
    }

    /// Seconds between frames while every mascot rests (only breathing and blinks move).
    public var restingInterval: TimeInterval {
        switch level {
        case .full: 1.0 / 12
        case .saving: 1.0 / 8
        case .minimal: 1.0 / 4
        }
    }

    /// Seconds between frames while a mascot is held or thrown: the chosen display rate, capped when saving.
    public func airborneInterval(display: TimeInterval) -> TimeInterval {
        switch level {
        case .full: display
        case .saving: max(display, 1.0 / 30)
        case .minimal: max(display, 1.0 / 20)
        }
    }

    /// Climbing reads the window list twice a second; skipped when the Mac is struggling.
    public var allowsClimbing: Bool { level < .minimal }

    /// Seconds between reads of Claude Code's sessions folder.
    public var sessionPollInterval: TimeInterval {
        switch level {
        case .full: 1
        case .saving: 2
        case .minimal: 4
        }
    }
}
