import SwiftUI

/// Building blocks shared by every page of the menu-bar popover, so the three tabs read the same way.
enum Spacing {
    static let micro: CGFloat = 4
    static let related: CGFloat = 8
    static let control: CGFloat = 12
    static let sectionInner: CGFloat = 16
    static let section: CGFloat = 20
    static let major: CGFloat = 24
}

/// A titled group of controls on a subtle background. The title sits outside, like System Settings.
struct PopoverSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.related) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title)
                Spacer(minLength: Spacing.related)
                accessory
            }
            VStack(alignment: .leading, spacing: Spacing.control) { content }
                .padding(Spacing.control)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.groupFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous).strokeBorder(Theme.hairline))
        }
    }
}

/// Small section title: semibold, secondary, never shouting.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, Spacing.micro)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row with an icon, a title, an optional detail line and a trailing control.
struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var systemImage: String?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, detail: String? = nil, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.related) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.rowIconWidth)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.related)
            trailing
        }
    }
}

/// A switch row: the whole row is the label, the switch sits at the trailing edge.
struct SettingToggle: View {
    let title: String
    var detail: String?
    var systemImage: String?
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        SettingRow(title, detail: detail, systemImage: systemImage) {
            Toggle(title, isOn: Binding(get: { isOn }, set: onChange))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }
}

/// A short explanation under a group of controls.
struct Footnote: View {
    let text: String
    var tone: Color = .secondary

    init(_ text: String, tone: Color = .secondary) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What a status pill can say. Each one is backed by a real state, never a placeholder.
enum StatusLevel {
    case good, pending, problem, off

    var color: Color {
        switch self {
        case .good: Theme.success
        case .pending: Theme.warning
        case .problem: Theme.danger
        case .off: .secondary
        }
    }
}

/// A coloured dot and a short word: Allowed, Ready, Pending Permission…
struct StatusIndicator: View {
    let text: String
    let level: StatusLevel

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(level.color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(level == .off ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The main action of a page: full width, filled with the accent.
struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .disabled(isDisabled)
    }
}

/// A utility action: full width, plain bordered button with a leading icon.
struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isDisabled)
    }
}

/// A row that opens a deeper page: progressive disclosure for advanced settings.
struct DisclosureRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRow(title, detail: detail, systemImage: systemImage) {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
