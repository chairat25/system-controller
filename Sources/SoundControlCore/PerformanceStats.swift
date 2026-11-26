import Foundation

/// One reading of the app's own CPU and memory use.
public struct PerformanceSample: Equatable, Sendable {
    /// Share of one CPU core over the last interval, like Activity Monitor: two busy cores read 200.
    public let cpuPercent: Double
    /// Physical memory footprint in bytes, the "Memory" column of Activity Monitor.
    public let memoryBytes: UInt64

    public init(cpuPercent: Double, memoryBytes: UInt64) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    var isValid: Bool { cpuPercent.isFinite && cpuPercent >= 0 }

    /// CPU time used over wall time, in percent of one core; nil when either is unusable.
    public static func cpuPercent(cpuSeconds: Double, wallSeconds: Double) -> Double? {
        guard cpuSeconds.isFinite, wallSeconds.isFinite, cpuSeconds >= 0, wallSeconds > 0 else { return nil }
        return cpuSeconds / wallSeconds * 100
    }
}

/// Lowest, highest and average of a series of readings.
public struct PerformanceRange<Value: Comparable & Sendable>: Equatable, Sendable {
    public let lowest: Value
    public let highest: Value

    func including(_ value: Value) -> Self {
        Self(lowest: min(lowest, value), highest: max(highest, value))
    }
}

/// The app's CPU and memory use since launch: the latest reading and the lowest, highest and average.
/// Immutable: `recording` returns a new value.
public struct PerformanceStats: Equatable, Sendable {
    public let latest: PerformanceSample?
    public let count: Int
    public let cpu: PerformanceRange<Double>
    public let memory: PerformanceRange<UInt64>
    private let cpuTotal: Double

    public static let empty = PerformanceStats(latest: nil, count: 0, cpu: PerformanceRange(lowest: 0, highest: 0),
                                               memory: PerformanceRange(lowest: 0, highest: 0), cpuTotal: 0)

    public var cpuAverage: Double { count > 0 ? cpuTotal / Double(count) : 0 }

    public func recording(_ sample: PerformanceSample) -> Self {
        guard sample.isValid else { return self }
        guard count > 0 else {
            return Self(latest: sample, count: 1, cpu: PerformanceRange(lowest: sample.cpuPercent, highest: sample.cpuPercent),
                        memory: PerformanceRange(lowest: sample.memoryBytes, highest: sample.memoryBytes),
                        cpuTotal: sample.cpuPercent)
        }
        return Self(latest: sample, count: count + 1, cpu: cpu.including(sample.cpuPercent),
                    memory: memory.including(sample.memoryBytes), cpuTotal: cpuTotal + sample.cpuPercent)
    }

    private init(latest: PerformanceSample?, count: Int, cpu: PerformanceRange<Double>,
                 memory: PerformanceRange<UInt64>, cpuTotal: Double) {
        self.latest = latest
        self.count = count
        self.cpu = cpu
        self.memory = memory
        self.cpuTotal = cpuTotal
    }
}
