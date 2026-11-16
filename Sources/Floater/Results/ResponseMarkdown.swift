import AppKit

enum ResponseMarkdown {
    static func render(_ source: String, style: ReadingTextStyle) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: style.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style.paragraphStyle,
        ]
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full)) else {
            return NSAttributedString(string: source, attributes: base)
        }
        let result = NSMutableAttributedString()
        var previous: PresentationIntent?
        var tables: [Int: NSTextTable] = [:]
        for (intent, range) in parsed.runs[\.presentationIntent] {
            let components = intent?.components ?? []
            let paragraph = style.paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            var attributes = base
            var font = style.font
            var prefix = ""
            var listDepth = 0
            var ordinal: Int?
            var ordered = false
            var itemID: Int?
            var isCode = false
            var table: NSTextTable?
            var row = 0
            var column: Int?
            var isTableHeader = false
            for component in components {
                switch component.kind {
                case .header(let level):
                    font = .systemFont(ofSize: style.fontSize + CGFloat(max(1, 5 - level)) * 2, weight: .semibold)
                case .codeBlock:
                    isCode = true
                    font = .monospacedSystemFont(ofSize: style.fontSize - 1, weight: .regular)
                    attributes[.backgroundColor] = NSColor.quaternaryLabelColor
                case .blockQuote:
                    paragraph.headIndent += 12
                    paragraph.firstLineHeadIndent += 12
                    attributes[.foregroundColor] = NSColor.secondaryLabelColor
                case .listItem(let value):
                    if ordinal == nil { ordinal = value; itemID = component.identity }
                case .orderedList, .unorderedList:
                    if listDepth == 0, case .orderedList = component.kind { ordered = true }
                    listDepth += 1
                case .table(let columns):
                    let existing = tables[component.identity] ?? NSTextTable()
                    existing.numberOfColumns = columns.count
                    existing.setValue(100, type: .percentageValueType, for: .width)
                    tables[component.identity] = existing
                    table = existing
                    if let column, columns.indices.contains(column) {
                        switch columns[column].alignment {
                        case .left: paragraph.alignment = .left
                        case .center: paragraph.alignment = .center
                        case .right: paragraph.alignment = .right
                        @unknown default: break
                        }
                    }
                case .tableHeaderRow:
                    isTableHeader = true
                    font = .systemFont(ofSize: style.fontSize, weight: .semibold)
                case .tableRow(let index): row = index
                case .tableCell(let index): column = index
                default: break
                }
            }
            if let previous {
                let sameContainer = previous.components.last?.identity == components.last?.identity
                let separator = sameContainer ? "\n" : "\n\n"
                let trailing = result.string.reversed().prefix { $0 == "\n" }.count
                if trailing < separator.count {
                    result.append(NSAttributedString(string: String(separator.dropFirst(trailing)), attributes: base))
                }
            }
            if listDepth > 0 {
                let indentation = CGFloat(listDepth - 1) * 18
                let marker = ordered ? "\(ordinal ?? 1)." : "•"
                let markerWidth = (marker as NSString).size(withAttributes: [.font: font]).width + 8
                paragraph.firstLineHeadIndent += indentation
                paragraph.headIndent += indentation + max(18, markerWidth)
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                let sameItem = previous?.components.contains { $0.identity == itemID } == true
                if sameItem {
                    paragraph.firstLineHeadIndent = paragraph.headIndent
                } else {
                    prefix = marker + "\t"
                }
            }
            if let table, let column {
                let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(5, type: .absoluteValueType, for: .padding)
                cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                cell.setBorderColor(.separatorColor)
                if isTableHeader { cell.backgroundColor = .quaternaryLabelColor }
                paragraph.textBlocks = [cell]
            }
            attributes[.font] = font
            attributes[.paragraphStyle] = paragraph
            result.append(NSAttributedString(string: prefix, attributes: attributes))
            for run in parsed[range].runs {
                var inline = attributes
                var runFont = font
                let traits = run.inlinePresentationIntent ?? []
                if traits.contains(.code), !isCode {
                    runFont = .monospacedSystemFont(ofSize: style.fontSize - 1, weight: .regular)
                    inline[.backgroundColor] = NSColor.quaternaryLabelColor
                }
                if traits.contains(.stronglyEmphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask) }
                if traits.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
                if traits.contains(.strikethrough) { inline[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let link = run.link { inline[.link] = link }
                inline[.font] = runFont
                let text = traits.contains(.softBreak) ? "\n" : String(parsed[run.range].characters)
                result.append(NSAttributedString(string: text, attributes: inline))
            }
            previous = intent
        }
        // Keep plain-text replies' final line breaks when Markdown consumes them.
        let trailing = source.reversed().prefix { $0 == "\n" }.count
        let renderedTrailing = result.string.reversed().prefix { $0 == "\n" }.count
        if trailing > renderedTrailing {
            result.append(NSAttributedString(string: String(repeating: "\n", count: trailing - renderedTrailing), attributes: base))
        }
        return result
    }
}
