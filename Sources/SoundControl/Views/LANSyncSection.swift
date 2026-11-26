import SwiftUI
import SoundControlCore

/// The "Sync" section of Settings: what to share, which Macs are paired, and how to pair another one.
struct LANSyncSection: View {
    @Environment(AppModel.self) private var model

    private var sync: LANSyncService { model.lanSync }
    private var pairing: LANSyncPairing { model.lanSync.pairing }

    var body: some View {
        Section {
            Toggle(L("Sync wallpaper"), isOn: Binding(
                get: { sync.settings.isWallpaperSyncOn },
                set: { value in sync.update { $0.withWallpaperSync(value) } }))
            Toggle(L("Mascot roams between Macs"), isOn: Binding(
                get: { sync.settings.isMascotRoamingOn },
                set: { value in sync.update { $0.withMascotRoaming(value) } }))
            if sync.settings.isMascotRoamingOn {
                LabeledContent(L("This Mac's animal")) {
                    Text(L(model.screenSaver.activeMascot.title)).foregroundStyle(.secondary)
                }
                MascotGrid(selection: model.screenSaver.activeMascot) { mascot in
                    model.updateScreenSaver { $0.withMascot(mascot) }
                }
            }
            ForEach(sync.settings.pairedPeers) { peer in
                PairedMacRow(peer: peer, isConnected: sync.connectedPeerIDs.contains(peer.id),
                             version: sync.peerVersions[peer.id],
                             setSide: { side in sync.update { $0.withSide(side, for: peer.id) } },
                             unpair: { sync.unpair(peer.id) })
            }
            PairingControls(pairing: pairing)
            if let problem = sync.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
            }
        } header: {
            Text(L("Sync"))
        } footer: {
            Text(L("Wallpaper sync keeps the screen saver photo and the desktop wallpaper the same on every paired Mac; the newest choice wins. The mascot can walk off one screen edge and appear on the Mac you set for that side. Only Macs you pair, by comparing a code on both screens, can connect. Nothing runs on the network while both switches are off."))
        }
    }
}

struct PairedMacRow: View {
    let peer: PairedPeer
    let isConnected: Bool
    /// What it said in its hello; nil while it is not connected.
    var version: LANSyncService.PeerVersion?
    let setSide: (PeerSide?) -> Void
    let unpair: () -> Void

    var body: some View {
        HStack(spacing: Spacing.related) {
            Circle().fill(isConnected ? Theme.success : Color.secondary.opacity(0.6))
                .frame(width: 7, height: 7)
                .frame(width: Theme.rowIconWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text(peer.name).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(placement).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let mismatch {
                    Text(mismatch).font(.caption).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.micro)
            Picker(L("Side"), selection: Binding(get: { peer.side }, set: setSide)) {
                Text(L("Left")).tag(PeerSide?.some(.left))
                Text(L("Not beside")).tag(PeerSide?.none)
                Text(L("Right")).tag(PeerSide?.some(.right))
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Menu {
                Button(L("Unpair"), role: .destructive, action: unpair)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("More"))
        }
    }

    /// Both sides need the same version for a visitor to keep its look; say so instead of looking broken.
    private var mismatch: String? {
        guard isConnected, let version else { return nil }
        guard let theirs = version.appVersion else { return L("Runs an older version. Update it to 1.7 or later.") }
        // The Windows companion has its own version numbers; it speaks the same protocol.
        guard version.platform == "macos", theirs != LANSyncService.appVersion else { return nil }
        return L("Runs %@, this Mac %@. Update both to the same version.", theirs, LANSyncService.appVersion)
    }

    private var placement: String {
        let device = version?.platform == "windows" ? "PC · " : ""
        let status = device + (isConnected ? L("Connected") : L("Not nearby"))
        guard let side = peer.side else { return "\(status) · \(L("wallpaper only"))" }
        return "\(status) · \(L(side == .left ? "to the left" : "to the right"))"
    }
}

struct PairingControls: View {
    let pairing: LANSyncPairing

    var body: some View {
        switch pairing.state {
        case let .confirming(code, peerName):
            confirmation(code: code, peerName: peerName)
        case let .connecting(peerName):
            SettingRow(L("Pairing with %@", peerName), systemImage: "link") {
                HStack {
                    ProgressView().controlSize(.small)
                    Button(L("Cancel")) { pairing.cancel() }.controlSize(.small)
                }
            }
        case let .failed(reason):
            SettingRow(reason, systemImage: "exclamationmark.triangle") {
                Button(L("Try Again")) { pairing.cancel() }.controlSize(.small)
            }
            .foregroundStyle(Theme.warning)
        case .idle:
            idle
        }
    }

    @ViewBuilder
    private var idle: some View {
        if pairing.isWindowOpen {
            SettingRow("Looking for Macs and PCs…",
                       detail: "Open Settings on the other computer and choose Pair there too. This stops after 2 minutes.",
                       systemImage: "dot.radiowaves.left.and.right") {
                Button(L("Stop")) { pairing.closeWindow() }.controlSize(.small)
            }
            ForEach(pairing.nearby) { mac in
                SettingRow(mac.name, systemImage: "desktopcomputer") {
                    Button(L("Pair")) { pairing.pair(with: mac) }.controlSize(.small)
                }
            }
        } else {
            SettingRow("Add a Mac or PC", systemImage: "plus.circle") {
                Button(L("Pair…")) { pairing.openWindow() }.controlSize(.small)
            }
        }
    }

    private func confirmation(code: String, peerName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Does %@ show the same code?", peerName)).font(.callout)
            Text(Self.spaced(code))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .textSelection(.disabled)
            HStack {
                Button(L("Confirm")) { pairing.confirm() }
                    .buttonStyle(.borderedProminent)
                Button(L("Cancel")) { pairing.cancel() }
            }
            Text(L("Tap Confirm on both Macs only if the codes match.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func spaced(_ code: String) -> String {
        guard code.count == PairingCode.digitCount else { return code }
        return code.prefix(3) + " " + code.suffix(3)
    }
}
