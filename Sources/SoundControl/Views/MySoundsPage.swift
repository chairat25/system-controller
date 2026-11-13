import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SoundControlCore

struct MySoundsPage: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false
    @State private var renaming: UserSound?
    @State private var newName = ""
    @State private var pendingDelete: UserSound?
    @State private var search = ""
    @State private var filter = UserSoundLibrary.Filter.all
    @State private var sort = UserSoundLibrary.Sort.recent
    @State private var selected: UUID?

    private static let formats = "WAV, AIFF, MP3, M4A, CAF or FLAC, up to 30 seconds"

    var body: some View {
        let sounds = model.config.userSounds
        WindowPage {
            PageHeader(title: "My Sounds",
                       subtitle: sounds.isEmpty ? "Your own clips, ready for any trigger."
                                                : "\(sounds.count) sound\(sounds.count == 1 ? "" : "s") in your library.") {
                HStack {
                    Button { model.revealSoundsFolder() } label: { Label("Show in Finder", systemImage: "folder") }
                    Button { chooseFiles() } label: { Label("Import…", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            }
            if sounds.isEmpty {
                dropZone(isCompact: false)
            } else {
                toolbar
                dropZone(isCompact: true)
                library(visibleSounds)
            }
        }
        .alert("Rename sound", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let sound = renaming { model.renameSound(sound.id, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete sound", role: .destructive) {
                if let sound = pendingDelete { model.deleteSound(sound.id) }
                pendingDelete = nil
            }
        } message: {
            let usage = pendingDelete.map { usageCount($0.id) } ?? 0
            Text(usage == 0 ? "Nothing uses this sound."
                 : "It is used \(usage) time\(usage == 1 ? "" : "s"). Those triggers and packs will fall back to their pack sound.")
        }
    }

    private var visibleSounds: [UserSound] {
        let filtered = UserSoundLibrary.filtered(model.config.userSounds, by: filter, search: search, usage: usageCount)
        return UserSoundLibrary.sorted(filtered, by: sort)
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.control) { toolbarItems }
            VStack(alignment: .leading, spacing: Spacing.related) { toolbarItems }
        }
    }

    @ViewBuilder
    private var toolbarItems: some View {
        SearchField(prompt: "Search sounds", text: $search)
        FilterSegment(title: "Show", selection: $filter)
        Spacer(minLength: 0)
        Picker("Sort by", selection: $sort) {
            ForEach(UserSoundLibrary.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func library(_ sounds: [UserSound]) -> some View {
        if sounds.isEmpty {
            EmptyState("No matching sounds", message: "Try another word or switch the filter back to All.",
                       systemImage: "magnifyingglass") {
                Button("Show all sounds") {
                    search = ""
                    filter = .all
                }
            }
        } else {
            GroupedList(items: sounds) { sound in row(sound) }
        }
    }

    /// Big and inviting while the library is empty; a single slim bar once sounds exist. Lights up while dragging.
    private func dropZone(isCompact: Bool) -> some View {
        Group {
            if isCompact && !isDropTargeted {
                HStack(spacing: Spacing.related) {
                    Image(systemName: "waveform.badge.plus").foregroundStyle(Theme.accent)
                    Text("Drop audio files here to add them").font(.callout)
                    Text("· \(Self.formats)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.control)
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 30)).foregroundStyle(Theme.accent)
                    Text(isDropTargeted ? "Release to import" : "Drop audio files here").font(.headline)
                    Text(Self.formats).font(.caption).foregroundStyle(.secondary)
                    Text("Sounds are copied into Sound Control, so moving the originals is fine.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !isDropTargeted {
                        Button("Choose files…") { chooseFiles() }.padding(.top, Spacing.micro)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
        }
        .background(isDropTargeted ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(isDropTargeted ? Theme.accent : Color.secondary.opacity(0.4)))
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDropped(providers)
            return true
        }
    }

    private func row(_ sound: UserSound) -> some View {
        let usage = usageCount(sound.id)
        let isExpanded = selected == sound.id
        return VStack(alignment: .leading, spacing: Spacing.related) {
            HStack(spacing: Spacing.control) {
                SymbolTile(symbol: "waveform", isActive: usage > 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sound.name).font(.body.weight(.medium))
                    HStack(spacing: 6) {
                        Text("\(sound.duration.formatted(.number.precision(.fractionLength(1)))) s")
                        Text("·")
                        Text(UserSoundLibrary.format(of: sound))
                        Text("·")
                        Text(usage == 0 ? "Not used" : "Used by \(usage)")
                            .foregroundStyle(usage == 0 ? Color.secondary : Theme.accent)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                PlayButton { model.preview(.user(id: sound.id)) }
                if usage > 0 {
                    RowIconButton(systemImage: isExpanded ? "chevron.up" : "chevron.down",
                                  help: isExpanded ? "Hide where it is used" : "Show where it is used") {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = isExpanded ? nil : sound.id }
                    }
                }
                Menu {
                    Button("Rename…") {
                        newName = sound.name
                        renaming = sound
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { pendingDelete = sound }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
                .accessibilityLabel("More actions for \(sound.name)")
            }
            if isExpanded {
                usageDetail(sound.id)
            }
        }
        .rowPadding()
    }

    /// The triggers and custom packs that point at this sound.
    private func usageDetail(_ id: UUID) -> some View {
        let ref = SoundRef.user(id: id)
        let triggers = TriggerID.allCases.filter { model.config.setting(for: $0).customSounds.contains(ref) }
        let packs = model.config.customPacks.filter { $0.overrides.values.contains { $0.contains(ref) } }
        return VStack(alignment: .leading, spacing: Spacing.micro) {
            ForEach(triggers, id: \.self) { trigger in
                Label(TriggerCatalog.info(for: trigger).title, systemImage: TriggerCatalog.info(for: trigger).symbol)
            }
            ForEach(packs) { pack in
                Label("Pack: \(pack.name)", systemImage: "theatermasks")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, WindowLayout.rowInset - 14)
    }

    private func usageCount(_ id: UUID) -> Int {
        UserSoundLibrary.usageCount(of: id, in: model.config)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return }
        model.importSounds(panel.urls)
    }

    private func loadDropped(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { _ = model.importSounds([url]) }
                }
            }
        }
    }
}
