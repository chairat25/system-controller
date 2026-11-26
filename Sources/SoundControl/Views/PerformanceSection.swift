import SwiftUI
import SoundControlCore

/// The app's own CPU and memory use since launch (now, lowest, highest), how hard it is allowed to work on this
/// Mac right now, and the owner's choice of when to save resources. The numbers refresh only while it is shown.
struct PerformanceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let resources = model.resources
        let stats = resources.shownStats
        PopoverSection(L("Performance")) {
            SettingRow("Save resources", detail: "Slower animations and polling when the Mac is hot, busy or low on memory",
                       systemImage: "leaf") {
                Picker(L("Save resources"), selection: Binding(
                    get: { model.appSettings.resourceSaving },
                    set: { value in model.updateAppSettings { $0.withResourceSaving(value) } })) {
                    ForEach(ResourceSaving.allCases) { Text(L($0.title)).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
            }
            SettingRow("Now running at", detail: reasonText(resources.budget), systemImage: "gauge.with.dots.needle.50percent") {
                Text(L(resources.budget.level.title))
                    .font(.callout)
                    .foregroundStyle(resources.budget.level == .full ? Color.secondary : Theme.warning)
            }
            SettingRow("CPU", detail: cpuDetail(stats), systemImage: "cpu") {
                Text(stats.latest.map { Self.percent($0.cpuPercent) } ?? "–").font(.callout.monospacedDigit())
            }
            SettingRow("Memory", detail: memoryDetail(stats, peak: resources.shownPeakMemory),
                       systemImage: "memorychip") {
                Text(stats.latest.map { Self.megabytes($0.memoryBytes) } ?? "–").font(.callout.monospacedDigit())
            }
            Footnote("Since the app started, read every 5 seconds. 100% is one CPU core fully busy, as in Activity Monitor.")
        }
        .onAppear { resources.beginWatching() }
        .onDisappear { resources.endWatching() }
    }

    private func reasonText(_ budget: ResourceBudget) -> String {
        budget.reasons.isEmpty ? L("Nothing is holding it back")
            : budget.reasons.map { L($0.title) }.joined(separator: " · ")
    }

    private func cpuDetail(_ stats: PerformanceStats) -> String {
        guard stats.count > 0 else { return L("Measuring…") }
        return L("Lowest %@ · average %@ · highest %@", Self.percent(stats.cpu.lowest),
                 Self.percent(stats.cpuAverage), Self.percent(stats.cpu.highest))
    }

    private func memoryDetail(_ stats: PerformanceStats, peak: UInt64) -> String {
        guard stats.count > 0 else { return L("Measuring…") }
        return L("Lowest %@ · highest %@ · peak %@", Self.megabytes(stats.memory.lowest),
                 Self.megabytes(stats.memory.highest), Self.megabytes(max(peak, stats.memory.highest)))
    }

    private static func percent(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value)
    }

    private static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
