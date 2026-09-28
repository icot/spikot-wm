import AppKit

/// The picker's contents: the filter line, then one row per window.
///
/// Laid out by hand rather than with a table view. There are at most a dozen rows, no selection
/// model to share, and no cell reuse worth having; a stack of labels is less code than a table's
/// data source and delegate, and the whole view is rebuilt on every keystroke anyway.
///
/// Key events arrive here because the panel makes this the first responder. `NSView` beeps at an
/// unhandled key, so the handler says whether it took it.
final class PickerView: NSView {
    private let handler: (NSEvent) -> Bool
    private let filterLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    private static let rowHeight: CGFloat = 26
    private static let padding: CGFloat = 12
    private static let filterHeight: CGFloat = 28

    init(handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
        super.init(frame: .zero)

        wantsLayer = true
        // A translucent dark panel with rounded corners, which is what every other launcher on the
        // platform looks like. Not themed: the panel is its own surface rather than part of a
        // window, so it does not need to follow light and dark.
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.cornerRadius = 10

        // Declared dark so every system colour used below resolves against this surface rather
        // than against the window's appearance, which is light by default.
        appearance = NSAppearance(named: .darkAqua)

        filterLabel.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        filterLabel.textColor = .white
        addSubview(filterLabel)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !handler(event) { super.keyDown(with: event) }
    }

    /// The height the panel needs for a given number of rows.
    func fittingHeight(rows: Int) -> CGFloat {
        Self.padding * 2 + Self.filterHeight + CGFloat(rows) * (Self.rowHeight + 2)
    }

    func render(filter: String, rows: [WindowPicker.Row], selection: Int) {
        filterLabel.stringValue = filter.isEmpty ? "Type to filter" : "> " + filter
        // White at reduced alpha rather than `.secondaryLabelColor`, which resolves to a dark grey
        // against a light appearance and so was almost invisible on the black panel: the prompt
        // read as an empty line above the list.
        filterLabel.textColor = filter.isEmpty ? NSColor.white.withAlphaComponent(0.65) : .white

        stack.subviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.prefix(WindowPicker.visibleRows).enumerated() {
            stack.addView(
                rowView(row, number: index + 1, selected: index == selection),
                in: .bottom)
        }
        needsLayout = true
    }

    private func rowView(_ row: WindowPicker.Row, number: Int, selected: Bool) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 5
        container.layer?.backgroundColor =
            selected
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor

        // The number is shown for the first nine, because those keys pick a row outright.
        let prefix = number <= 9 ? "\(number)  " : "   "
        let label = NSTextField(labelWithString: prefix + row.label)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: Self.rowHeight),
        ])
        return container
    }

    override func layout() {
        super.layout()
        let width = bounds.width - Self.padding * 2
        filterLabel.frame = NSRect(
            x: Self.padding, y: bounds.maxY - Self.padding - Self.filterHeight,
            width: width, height: Self.filterHeight)
        stack.frame = NSRect(
            x: Self.padding, y: Self.padding,
            width: width, height: filterLabel.frame.minY - Self.padding)
        for view in stack.subviews {
            view.frame.size.width = width
        }
    }
}
