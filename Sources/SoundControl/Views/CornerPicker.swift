import SwiftUI
import SoundControlCore

/// A small screen split into four cells; click the corner where the Claude sessions list should sit.
struct CornerPicker: View {
    let selection: ScreenSaverCorner
    let onSelect: (ScreenSaverCorner) -> Void

    private static let rows: [[ScreenSaverCorner]] = [[.topLeft, .topRight], [.bottomLeft, .bottomRight]]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.rows, id: \.first) { row in
                HStack(spacing: 4) {
                    ForEach(row) { corner in cell(corner) }
                }
            }
        }
        .padding(5)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cell(_ corner: ScreenSaverCorner) -> some View {
        let isSelected = corner == selection
        return Button { onSelect(corner) } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Theme.accent : Color.secondary.opacity(0.22))
                .frame(width: 54, height: 32)
                .overlay(alignment: corner.alignment) {
                    // A tiny list marker sitting in the chosen corner of the cell.
                    Image(systemName: "list.bullet").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(4)
                }
        }
        .buttonStyle(.plain)
        .help(corner.title)
        .accessibilityLabel(corner.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension ScreenSaverCorner {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    var horizontalAlignment: HorizontalAlignment { isLeft ? .leading : .trailing }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}
