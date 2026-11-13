import SwiftUI

/// Building blocks shared by the five pages of the Sound Control window, so they read as one app.
enum WindowLayout {
    static let pagePadding: CGFloat = 24
    static let pageSpacing: CGFloat = Spacing.section
    static let rowInset: CGFloat = 60
    static let searchMaxWidth: CGFloat = 280
}

/// A scrolling page with the shared padding, header and spacing.
struct WindowPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WindowLayout.pageSpacing) { content }
                .padding(WindowLayout.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Search box used in page toolbars.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.groupFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
        .frame(minWidth: 160, maxWidth: WindowLayout.searchMaxWidth)
    }
}

/// A segmented filter over any string-backed enum (All / On / Off, All / Played / Skipped…).
struct FilterSegment<Value: Hashable & RawRepresentable & CaseIterable>: View where Value.RawValue == String,
                                                                                     Value.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Value

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Value.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// A list section title with an optional count and a trailing action.
struct ListSectionHeader<Accessory: View>: View {
    let title: String
    var count: String?
    @ViewBuilder let accessory: Accessory

    init(_ title: String, count: String? = nil, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.count = count
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if let count {
                Text(count).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.related)
            accessory
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Rows separated by inset hairlines on one grouped surface.
struct GroupedList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var inset: CGFloat = WindowLayout.rowInset
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        Card {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, inset) }
                row(item)
            }
        }
    }
}

/// An explained empty page: an icon, what is missing and how to get some.
struct EmptyState<Action: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder let action: Action

    init(_ title: String, message: String, systemImage: String, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Spacing.related) {
            Image(systemName: systemImage).font(.system(size: 30)).foregroundStyle(Theme.accent)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action.padding(.top, Spacing.micro)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.major + 8)
        .padding(.horizontal, Spacing.major)
        .background(Theme.groupFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// An icon-only button for a row (customize, more…) with a tooltip and a spoken name.
struct RowIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
