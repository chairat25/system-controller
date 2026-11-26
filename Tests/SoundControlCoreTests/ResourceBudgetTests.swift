import Foundation
import Testing
@testable import SoundControlCore

@Suite("Resource budget")
struct ResourceBudgetTests {
    private func signals(thermal: Int = 0, lowPower: Bool = false, memory: MemoryPressure = .normal,
                         load: Double = 0.2) -> ResourceSignals {
        ResourceSignals(thermalState: thermal, isLowPowerMode: lowPower, memory: memory, loadPerCore: load)
    }

    @Test("a cool, idle Mac runs everything at full rate")
    func calmIsFull() {
        let budget = ResourceBudget.decide(signals(), preference: .auto)
        #expect(budget.level == .full)
        #expect(budget.reasons.isEmpty)
        #expect(budget.walkingInterval == 1.0 / 24)
        #expect(budget.allowsClimbing)
        #expect(budget.sessionPollInterval == 1)
    }

    @Test("heat, Low Power Mode, low memory or a busy CPU each switch to saving", arguments: [
        (2, false, MemoryPressure.normal, 0.2, ResourceReason.hot),
        (0, true, MemoryPressure.normal, 0.2, ResourceReason.lowPower),
        (0, false, MemoryPressure.warning, 0.2, ResourceReason.memoryLow),
        (0, false, MemoryPressure.normal, 1.2, ResourceReason.busy),
    ])
    func savingSignals(thermal: Int, lowPower: Bool, memory: MemoryPressure, load: Double, reason: ResourceReason) {
        let budget = ResourceBudget.decide(signals(thermal: thermal, lowPower: lowPower, memory: memory, load: load),
                                           preference: .auto)
        #expect(budget.level == .saving)
        #expect(budget.reasons == [reason])
    }

    @Test("critical heat, critical memory or an overloaded CPU go to minimal", arguments: [
        (3, MemoryPressure.normal, 0.2, ResourceReason.veryHot),
        (0, MemoryPressure.critical, 0.2, ResourceReason.memoryCritical),
        (0, MemoryPressure.normal, 2.5, ResourceReason.veryBusy),
    ])
    func minimalSignals(thermal: Int, memory: MemoryPressure, load: Double, reason: ResourceReason) {
        let budget = ResourceBudget.decide(signals(thermal: thermal, memory: memory, load: load), preference: .auto)
        #expect(budget.level == .minimal)
        #expect(budget.reasons.contains(reason))
        #expect(!budget.allowsClimbing)
    }

    @Test("several reasons are all listed, the worst decides the level")
    func reasonsCombine() {
        let budget = ResourceBudget.decide(signals(lowPower: true, memory: .critical), preference: .auto)
        #expect(budget.level == .minimal)
        #expect(budget.reasons == [.lowPower, .memoryCritical])
    }

    @Test("each lower level does less work: slower frames, slower polling, capped throws")
    func levelsSlowDown() {
        let full = ResourceBudget.decide(signals(), preference: .auto)
        let saving = ResourceBudget.decide(signals(lowPower: true), preference: .auto)
        let minimal = ResourceBudget.decide(signals(thermal: 3), preference: .auto)
        #expect(full.walkingInterval < saving.walkingInterval && saving.walkingInterval < minimal.walkingInterval)
        #expect(full.restingInterval < saving.restingInterval && saving.restingInterval < minimal.restingInterval)
        #expect(full.sessionPollInterval < saving.sessionPollInterval
            && saving.sessionPollInterval < minimal.sessionPollInterval)
        let display120 = 1.0 / 120
        #expect(full.airborneInterval(display: display120) == display120)
        #expect(saving.airborneInterval(display: display120) == 1.0 / 30)
        #expect(minimal.airborneInterval(display: display120) == 1.0 / 20)
        // A slower display is never pushed faster.
        #expect(saving.airborneInterval(display: 1.0 / 24) == 1.0 / 24)
    }

    @Test("Always saves even on a calm Mac; Off never slows down")
    func preferences() {
        let always = ResourceBudget.decide(signals(), preference: .always)
        #expect(always.level == .saving)
        #expect(always.reasons == [.chosen])
        #expect(ResourceBudget.decide(signals(thermal: 3), preference: .always).level == .minimal)
        let off = ResourceBudget.decide(signals(thermal: 3, memory: .critical, load: 4), preference: .off)
        #expect(off.level == .full)
        #expect(off.reasons.isEmpty)
    }

    @Test("a busy CPU has to calm down a little before full rate comes back")
    func busyHysteresis() {
        let busy = ResourceBudget.decide(signals(load: 1.1), preference: .auto)
        #expect(busy.level == .saving)
        #expect(ResourceBudget.decide(signals(load: 0.9), preference: .auto, previous: busy).level == .saving)
        #expect(ResourceBudget.decide(signals(load: 0.7), preference: .auto, previous: busy).level == .full)
        #expect(ResourceBudget.decide(signals(load: 0.9), preference: .auto).level == .full)
    }

    @Test("the preference is stored by name and an unknown one falls back to Auto")
    func preferenceCoding() throws {
        let settings = AppSettings.default.withResourceSaving(.always)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).resourceSaving == .always)
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"resourceSaving":"turbo"}"#.utf8))
        #expect(odd.resourceSaving == .auto)
        #expect(AppSettings.default.resourceSaving == .auto)
        // Changing another setting keeps it.
        #expect(settings.withLanguage(.thai).withAutoUpdate(true).resourceSaving == .always)
    }
}

@Suite("Performance stats")
struct PerformanceStatsTests {
    @Test("starts empty")
    func empty() {
        #expect(PerformanceStats.empty.latest == nil)
        #expect(PerformanceStats.empty.count == 0)
    }

    @Test("keeps the latest sample and the lowest, highest and average since launch")
    func records() {
        let stats = PerformanceStats.empty
            .recording(PerformanceSample(cpuPercent: 4, memoryBytes: 80_000_000))
            .recording(PerformanceSample(cpuPercent: 30, memoryBytes: 120_000_000))
            .recording(PerformanceSample(cpuPercent: 2, memoryBytes: 70_000_000))
        #expect(stats.count == 3)
        #expect(stats.latest == PerformanceSample(cpuPercent: 2, memoryBytes: 70_000_000))
        #expect(stats.cpu.lowest == 2 && stats.cpu.highest == 30)
        #expect(stats.cpuAverage == 12)
        #expect(stats.memory.lowest == 70_000_000 && stats.memory.highest == 120_000_000)
    }

    @Test("recording returns a new value and leaves the old one alone")
    func immutable() {
        let first = PerformanceStats.empty.recording(PerformanceSample(cpuPercent: 1, memoryBytes: 1))
        _ = first.recording(PerformanceSample(cpuPercent: 50, memoryBytes: 9))
        #expect(first.count == 1 && first.cpu.highest == 1)
    }

    @Test("a broken reading (negative or not a number) is ignored")
    func ignoresBadSamples() {
        let stats = PerformanceStats.empty
            .recording(PerformanceSample(cpuPercent: 3, memoryBytes: 10))
            .recording(PerformanceSample(cpuPercent: .nan, memoryBytes: 20))
            .recording(PerformanceSample(cpuPercent: -1, memoryBytes: 20))
        #expect(stats.count == 1)
    }

    @Test("CPU percent comes from the CPU time used over the wall time, like Activity Monitor")
    func cpuPercent() {
        #expect(PerformanceSample.cpuPercent(cpuSeconds: 0.5, wallSeconds: 5) == 10)
        // Two cores busy for the whole interval read 200%.
        #expect(PerformanceSample.cpuPercent(cpuSeconds: 10, wallSeconds: 5) == 200)
        #expect(PerformanceSample.cpuPercent(cpuSeconds: 1, wallSeconds: 0) == nil)
        #expect(PerformanceSample.cpuPercent(cpuSeconds: -1, wallSeconds: 5) == nil)
    }
}
