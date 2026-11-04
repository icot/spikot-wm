// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A colour from the config file, as sRGB components between 0 and 1.
///
/// Kept free of AppKit so parsing can be tested here; the agent turns it into an `NSColor`.
public struct RGBAColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA`, case-insensitive, with the `#` optional.
    ///
    /// The optional `#` is so the value `choosepass` passed to choose-gui, `-b ff78c6`, can be
    /// copied across as it was. Three-digit shorthand is not accepted: one more spelling of the
    /// same thing, and `#fff` against `#ffff` is an easy misreading.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8,
            digits.allSatisfy(\.isHexDigit),
            let value = UInt32(digits, radix: 16)
        else { return nil }

        let rgba = digits.count == 6 ? value << 8 | 0xff : value
        self.init(
            red: Double(rgba >> 24 & 0xff) / 255,
            green: Double(rgba >> 16 & 0xff) / 255,
            blue: Double(rgba >> 8 & 0xff) / 255,
            alpha: Double(rgba & 0xff) / 255)
    }
}

/// The picker's colours, from the `picker` section of the config file.
///
/// Every key is optional, and a missing one keeps the built-in colour: a translucent black panel,
/// white text, and the system accent colour behind the selected row. The accent colour has no hex
/// value, which is why the defaults are nil here rather than written out.
public struct PickerColors: Codable, Equatable, Sendable {
    /// The panel behind the list.
    public var background: String?
    /// The highlight behind the selected row.
    public var selection: String?
    /// The rows and the filter line. The "Type to filter" prompt uses it at 65% of its alpha.
    public var text: String?

    public init(background: String? = nil, selection: String? = nil, text: String? = nil) {
        self.background = background
        self.selection = selection
        self.text = text
    }

    /// Each configured colour parsed, nil where the key is absent.
    ///
    /// A value that does not parse is also nil here; `validate()` is what rejects it, at load, so
    /// that by the time the panel draws the only nil is an absent key.
    public var backgroundColor: RGBAColor? { background.flatMap(RGBAColor.init(hex:)) }
    public var selectionColor: RGBAColor? { selection.flatMap(RGBAColor.init(hex:)) }
    public var textColor: RGBAColor? { text.flatMap(RGBAColor.init(hex:)) }

    /// Rejects a value that is not a colour, naming the key, so a typo fails the load with a
    /// message instead of drawing the panel in a colour nobody asked for.
    public func validate() throws {
        let keys: [(String, String?)] = [
            ("background", background), ("selection", selection), ("text", text),
        ]
        for case let (key, value?) in keys where RGBAColor(hex: value) == nil {
            throw ConfigError.invalidColor(key: "picker." + key, value: value)
        }
    }
}
