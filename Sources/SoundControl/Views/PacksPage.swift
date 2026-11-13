import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SoundControlCore

struct PacksPage: View {
    @Environment(AppModel.self) private var model
    @State private var editingPack: UUID?
    @State private var pendingDelete: CustomPack?

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]

    var body: some View {
        WindowPage {
            PageHeader(title: "Sound Packs",
                       subtitle: "A pack voices every trigger that follows it. Triggers set to their own sounds keep them.") {
                HStack {
                    Button { importPack() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                    Menu {
                        ForEach(BuiltInPack.allCases, id: \.self) { base in
                            Button("Start from \(base.title)") { editingPack = model.createPack(from: base).id }
                        }
                    } label: {
                        Label("New pack", systemImage: "plus")
                    }
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: Spacing.related) {
                ListSectionHeader("Built-in", count: "\(BuiltInPack.allCases.count)")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(BuiltInPack.allCases, id: \.self) { pack in
                        BuiltInPackCard(pack: pack)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.related) {
                ListSectionHeader("Your Packs", count: model.config.customPacks.isEmpty ? nil : "\(model.config.customPacks.count)")
                if model.config.customPacks.isEmpty {
                    EmptyState("No custom packs yet",
                               message: "Start from any built-in pack, then swap in your own sounds trigger by trigger.",
                               systemImage: "theatermasks.fill") {
                        Menu("New pack") {
                            ForEach(BuiltInPack.allCases, id: \.self) { base in
                                Button("Start from \(base.title)") { editingPack = model.createPack(from: base).id }
                            }
                        }
                        .fixedSize()
                    }
                } else {
                    GroupedList(items: model.config.customPacks) { pack in customRow(pack) }
                }
            }
        }
        .sheet(item: Binding(get: { editingPack.map(IdentifiedUUID.init) }, set: { editingPack = $0?.id })) { item in
            PackEditorSheet(packID: item.id)
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete pack", role: .destructive) {
                if let pack = pendingDelete { model.deletePack(pack.id) }
                pendingDelete = nil
            }
        } message: {
            Text("Your imported sounds stay in My Sounds.")
        }
    }

    private func customRow(_ pack: CustomPack) -> some View {
        let isActive = model.config.activePack == .custom(pack.id)
        return HStack(spacing: Spacing.control) {
            SymbolTile(symbol: "theatermasks.fill", isActive: isActive)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(pack.name).font(.body.weight(.medium))
                    if isActive { Badge(text: "Active", color: Theme.accent, symbol: "checkmark") }
                }
                Text("Based on \(pack.base.title) · \(pack.overrides.count) custom trigger\(pack.overrides.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isActive {
                Button("Use pack") { withAnimation(.easeOut(duration: 0.15)) { model.update { $0.selectingPack(.custom(pack.id)) } } }
            }
            Button("Edit") { editingPack = pack.id }
            Menu {
                Button("Export…") { export(pack) }
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = pack }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
            .accessibilityLabel("More actions for \(pack.name)")
        }
        .rowPadding()
    }

    private func export(_ pack: CustomPack) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(pack.name).\(PackArchive.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Export a pack folder you can share with another Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportPack(pack, to: url)
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .soundpack folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importPack(from: url)
    }
}

struct IdentifiedUUID: Identifiable {
    let id: UUID
}

private struct BuiltInPackCard: View {
    @Environment(AppModel.self) private var model
    let pack: BuiltInPack
    private static let previewMotifs: [Motif] = [.success, .rise, .click, .chime]
    @State private var previewStep = 0

    var body: some View {
        let isActive = model.config.activePack == .builtIn(pack)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SymbolTile(symbol: pack.symbol, isActive: true, size: 38)
                Spacer()
                if isActive { Badge(text: "Active", color: Theme.accent, symbol: "checkmark") }
            }
            Text(pack.title).font(.headline)
            Text(pack.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            HStack {
                Button {
                    // Previewing never switches the active pack.
                    let motif = Self.previewMotifs[previewStep % Self.previewMotifs.count]
                    previewStep += 1
                    if let ref = pack.sounds(for: motif).first { model.preview(ref) }
                } label: {
                    Label("Listen", systemImage: "play.fill")
                }
                Spacer()
                Button(isActive ? "In use" : "Use pack") {
                    withAnimation(.easeOut(duration: 0.15)) { model.update { $0.selectingPack(.builtIn(pack)) } }
                }
                .disabled(isActive)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(isActive ? Theme.accent.opacity(0.55) : Theme.hairline, lineWidth: isActive ? 1.5 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(pack.title)\(isActive ? ", active" : "")")
    }
}
