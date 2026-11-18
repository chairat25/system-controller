import SwiftUI
import SoundControlCore

/// The "Sync" section of Settings: what to share, which Macs are paired, and how to pair another one.
struct LANSyncSection: View {
    @Environment(AppModel.self) private var model

    private var sync: LANSyncService { model.lanSync }
    private var pairing: LANSyncPairing { model.lanSync.pairing }

    var body: some View {
        Section {
            Toggle("Sync wallpaper", isOn: Binding(
                get: { sync.settings.isWallpaperSyncOn },
                set: { value in sync.update { $0.withWallpaperSync(value) } }))
            Toggle("Mascot roams between Macs", isOn: Binding(
                get: { sync.settings.isMascotRoamingOn },
                set: { value in sync.update { $0.withMascotRoaming(value) } }))
            ForEach(sync.settings.pairedPeers) { peer in
                PairedMacRow(peer: peer, isConnected: sync.connectedPeerIDs.contains(peer.id),
                             setSide: { side in sync.update { $0.withSide(side, for: peer.id) } },
                             unpair: { sync.unpair(peer.id) })
            }
            PairingControls(pairing: pairing)
            if let problem = sync.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Wallpaper sync keeps the screen saver photo and the desktop wallpaper the same on every paired Mac; the newest choice wins. The mascot can walk off one screen edge and appear on the Mac you set for that side. Only Macs you pair, by comparing a code on both screens, can connect. Nothing runs on the network while both switches are off.")
        }
    }
}

private struct PairedMacRow: View {
    let peer: PairedPeer
    let isConnected: Bool
    let setSide: (PeerSide) -> Void
    let unpair: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Badge(text: isConnected ? "Connected" : "Not nearby", color: isConnected ? .green : .secondary)
                Picker("Side", selection: Binding(get: { peer.side }, set: setSide)) {
                    ForEach(PeerSide.allCases) { side in Text(side.title).tag(side) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                Button("Unpair", role: .destructive, action: unpair)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name)
                Text("Sits to the \(peer.side.title.lowercased()) of this Mac").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PairingControls: View {
    let pairing: LANSyncPairing

    var body: some View {
        switch pairing.state {
        case let .confirming(code, peerName):
            confirmation(code: code, peerName: peerName)
        case let .connecting(peerName):
            LabeledContent("Pairing with \(peerName)") {
                HStack {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { pairing.cancel() }
                }
            }
        case let .failed(reason):
            LabeledContent {
                Button("Try Again") { pairing.cancel() }
            } label: {
                Text(reason).font(.caption).foregroundStyle(Theme.warning)
            }
        case .idle:
            idle
        }
    }

    @ViewBuilder
    private var idle: some View {
        if pairing.isWindowOpen {
            LabeledContent {
                Button("Stop") { pairing.closeWindow() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking for Macs…")
                    Text("Open Settings on the other Mac and choose Pair a Mac there too. This stops after 2 minutes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(pairing.nearby) { mac in
                LabeledContent(mac.name) {
                    Button("Pair") { pairing.pair(with: mac) }
                }
            }
        } else {
            LabeledContent("Add a Mac") {
                Button("Pair a Mac…") { pairing.openWindow() }
            }
        }
    }

    private func confirmation(code: String, peerName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Does \(peerName) show the same code?").font(.callout)
            Text(Self.spaced(code))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .textSelection(.disabled)
            HStack {
                Button("Confirm") { pairing.confirm() }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { pairing.cancel() }
            }
            Text("Tap Confirm on both Macs only if the codes match.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func spaced(_ code: String) -> String {
        guard code.count == PairingCode.digitCount else { return code }
        return code.prefix(3) + " " + code.suffix(3)
    }
}
