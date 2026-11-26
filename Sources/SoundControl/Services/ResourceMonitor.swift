import Darwin
import Foundation
import Observation
import OSLog
import SoundControlCore

/// Measures the app's own CPU and memory use and watches the Mac's state (heat, Low Power Mode, memory pressure,
/// CPU load), then decides how hard the app may work (`budget`). Reading costs two system calls every few
/// seconds. The numbers reach the UI only while the Performance section is on screen.
@MainActor
@Observable
final class ResourceMonitor {
    private static let sampleInterval: TimeInterval = 5
    private static let sampleTolerance: TimeInterval = 1
    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "ResourceMonitor")

    /// How hard the app may work right now. Written only when it changes.
    private(set) var budget = ResourceBudget.full
    /// CPU and memory since launch, refreshed only while someone watches (`beginWatching`).
    private(set) var shownStats = PerformanceStats.empty
    /// The highest memory footprint macOS recorded for this process, including moments between samples.
    private(set) var shownPeakMemory: UInt64 = 0
    private(set) var shownSignals = ResourceSignals.calm

    /// Called after `budget` changes, so timers can pick up the new rates.
    @ObservationIgnored var onBudgetChange: (ResourceBudget) -> Void = { _ in }
    @ObservationIgnored private var preference: () -> ResourceSaving = { .default }
    @ObservationIgnored private var stats = PerformanceStats.empty
    @ObservationIgnored private var signals = ResourceSignals.calm
    @ObservationIgnored private var memory = MemoryPressure.normal
    @ObservationIgnored private var lastCPUSeconds: Double?
    @ObservationIgnored private var lastWall: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var watchers = 0

    func start(preference: @escaping () -> ResourceSaving) {
        guard timer == nil else { return }
        self.preference = preference
        sample()
        let next = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        next.tolerance = Self.sampleTolerance
        RunLoop.main.add(next, forMode: .common)
        timer = next
        installSystemObservers()
    }

    /// The owner changed the resource-saving choice.
    func preferenceChanged() { reevaluate() }

    func beginWatching() {
        watchers += 1
        publish()
    }

    func endWatching() {
        watchers = max(watchers - 1, 0)
    }

    // MARK: - Sampling

    private func sample() {
        let now = Date()
        let cpuSeconds = Self.cpuSeconds()
        if let lastCPUSeconds, let lastWall, let cpuSeconds,
           let percent = PerformanceSample.cpuPercent(cpuSeconds: cpuSeconds - lastCPUSeconds,
                                                      wallSeconds: now.timeIntervalSince(lastWall)),
           let footprint = Self.memoryFootprint() {
            stats = stats.recording(PerformanceSample(cpuPercent: percent, memoryBytes: footprint.current))
        }
        lastCPUSeconds = cpuSeconds
        lastWall = now
        reevaluate()
        publish()
    }

    private func reevaluate() {
        signals = ResourceSignals(thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                                  isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                  memory: memory, loadPerCore: Self.loadPerCore())
        let next = ResourceBudget.decide(signals, preference: preference(), previous: budget)
        guard next != budget else { return }
        let reasons = next.reasons.map(\.rawValue).joined(separator: ",")
        Self.logger.notice("Resource level \(next.level.title, privacy: .public) [\(reasons, privacy: .public)]")
        budget = next
        onBudgetChange(next)
    }

    /// Observation redraws every reader on any write, so nothing is written while no one looks or nothing changed.
    private func publish() {
        guard watchers > 0 else { return }
        if shownStats != stats { shownStats = stats }
        if shownSignals != signals { shownSignals = signals }
        let peak = Self.memoryFootprint()?.peak ?? 0
        if shownPeakMemory != peak { shownPeakMemory = peak }
    }

    // MARK: - System state

    private func installSystemObservers() {
        let center = NotificationCenter.default
        observers = [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange]
            .map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reevaluate() }
                }
            }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            let event = source.data
            MainActor.assumeIsolated { self?.memoryPressureChanged(event) }
        }
        source.activate()
        pressureSource = source
    }

    private func memoryPressureChanged(_ event: DispatchSource.MemoryPressureEvent) {
        memory = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
        if memory != .normal {
            // Give freed heap pages back to the system right away instead of when malloc gets round to it.
            malloc_zone_pressure_relief(nil, 0)
        }
        reevaluate()
    }

    // MARK: - Readings

    /// User plus system CPU time of the whole process, threads that ended included.
    private static func cpuSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let seconds = { (time: timeval) in Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// The physical footprint (what Activity Monitor shows as Memory) now and at its highest since launch.
    private static func memoryFootprint() -> (current: UInt64, peak: UInt64)? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (info.phys_footprint, max(UInt64(info.ledger_phys_footprint_peak), info.phys_footprint))
    }

    private static func loadPerCore() -> Double {
        var load = [0.0]
        guard getloadavg(&load, 1) == 1 else { return 0 }
        return load[0] / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    }
}
