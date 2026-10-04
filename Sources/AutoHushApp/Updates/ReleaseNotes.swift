import AppKit

/// A release's notes (the Markdown of its CHANGELOG section) as text for the
/// update popup: headings in bold, list items with bullets, bold, italic and
/// code kept, and links as plain text, so nothing in them can be clicked.
enum ReleaseNotes {
    /// Longer notes are cut, ending in "…".
    static let maxLength = 3_000

    /// One paragraph of the notes. A list item's or a paragraph's wrapped
    /// lines are joined.
    enum Block: Equatable {
        case heading(String)
        case item(String)
        case paragraph(String)
    }

    static func blocks(in markdown: String) -> [Block] {
        var blocks: [Block] = []
        var current: Block?
        func finish() {
            if let current { blocks.append(current) }
            current = nil
        }
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && line.count >= 3 {
                finish()
            } else if line.hasPrefix("#") {
                finish()
                blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                finish()
                current = .item(String(line.dropFirst(2)))
            } else {
                switch current {
                case .item(let text): current = .item(text + " " + line)
                case .paragraph(let text): current = .paragraph(text + " " + line)
                case .heading, nil: current = .paragraph(line)
                }
            }
        }
        finish()
        return blocks
    }

    static func text(from markdown: String, fontSize: CGFloat = NSFont.smallSystemFontSize) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: fontSize)
        let result = NSMutableAttributedString()
        for block in blocks(in: markdown) {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = fontSize / 3
            switch block {
            case .heading(let text):
                if result.length > 0 { paragraph.paragraphSpacingBefore = fontSize / 2 }
                result.append(inline(text, font: .boldSystemFont(ofSize: fontSize), paragraph: paragraph))
            case .item(let text):
                let indent = fontSize * 1.2
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                paragraph.headIndent = indent
                result.append(inline("•\t" + text, font: font, paragraph: paragraph))
            case .paragraph(let text):
                result.append(inline(text, font: font, paragraph: paragraph))
            }
        }
        guard result.length > maxLength else { return result }
        let cut = NSMutableAttributedString(attributedString: result.attributedSubstring(from: NSRange(location: 0, length: maxLength)))
        cut.append(NSAttributedString(string: "…", attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        return cut
    }

    /// `text` with its inline Markdown applied; unreadable Markdown is shown as is.
    private static func inline(_ text: String, font: NSFont, paragraph: NSParagraphStyle) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: base)
        }
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = base
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            } else {
                var traits = font.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                attributes[.font] = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
            }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}
