import Foundation

public struct NewBugRow: Equatable, Sendable {
    public let kind: ReportKind
    public let areaName: String
    public let comment: String
    public let attachmentFileNames: [String]

    public init(kind: ReportKind, areaName: String, comment: String, attachmentFileNames: [String]) {
        self.kind = kind
        self.areaName = areaName
        self.comment = comment
        self.attachmentFileNames = attachmentFileNames
    }
}

public struct BugPageInsertion: Equatable, Sendable {
    public let storage: String
    public let identifier: Int
}

public enum BugPageError: Error, Equatable {
    case tableNotFound
}

enum ColumnKind: Sendable, CaseIterable {
    case identifier
    case status
    case kind
    case area
    case description
    case images
    case history

    var title: String {
        switch self {
        case .identifier:
            return "ID"
        case .status:
            return "Stato"
        case .kind:
            return "Tipo"
        case .area:
            return "Area"
        case .description:
            return "Descrizione"
        case .images:
            return "Immagini"
        case .history:
            return "Storia"
        }
    }

    var widthPercentage: Int {
        switch self {
        case .identifier:
            return 4
        case .status:
            return 8
        case .kind:
            return 6
        case .area:
            return 13
        case .description:
            return 45
        case .images, .history:
            return 12
        }
    }

    var isRequired: Bool {
        self != .history
    }

    init?(headerText: String) {
        guard let column = Self.allCases.first(where: { $0.title.lowercased() == headerText.lowercased() }) else {
            return nil
        }
        self = column
    }
}

enum BugStatus: Sendable, CaseIterable {
    case open
    case inProgress
    case resolved

    var colour: String {
        switch self {
        case .open:
            return "Red"
        case .inProgress:
            return "Yellow"
        case .resolved:
            return "Green"
        }
    }

    var title: String {
        switch self {
        case .open:
            return "Aperto"
        case .inProgress:
            return "In corso"
        case .resolved:
            return "Risolto"
        }
    }

    var legend: String {
        switch self {
        case .open:
            return "da fare"
        case .inProgress:
            return "qualcuno ci sta lavorando"
        case .resolved:
            return "fatto e verificato"
        }
    }

    var macro: String {
        "<ac:structured-macro ac:name=\"status\" ac:schema-version=\"1\"><ac:parameter ac:name=\"colour\">\(colour)</ac:parameter><ac:parameter ac:name=\"title\">\(title)</ac:parameter></ac:structured-macro>"
    }
}

struct TableRow: Sendable {
    let range: Range<Int>
    let sectionName: String?
    let cellRanges: [Range<Int>]
}

struct BugTable: Sendable {
    let columns: [ColumnKind?]
    let headerRow: TableRow
    let dataRows: [TableRow]
    let firstTrailingBlankIndex: Int
    let bodyContentStart: Int?
    let headEnd: Int?

    func cellRange(of column: ColumnKind, in row: TableRow) -> Range<Int>? {
        guard let index = columns.firstIndex(of: column), index < row.cellRanges.count else {
            return nil
        }
        return row.cellRanges[index]
    }
}

public struct BugPage: Sendable {
    public static let requiredColumnTitles = ColumnKind.allCases.filter(\.isRequired).map(\.title)

    private let scanner: StorageScanner
    private let table: BugTable?

    public init(storage: String) {
        let scanner = StorageScanner(bytes: Array(storage.utf8))
        self.scanner = scanner
        self.table = BugPageParser(scanner: scanner).parse()
    }

    public var hasTable: Bool {
        table != nil
    }

    public var rowCount: Int {
        table?.firstTrailingBlankIndex ?? 0
    }

    public var areaNames: [String] {
        guard let table else {
            return []
        }
        var names: [String] = []
        for row in table.dataRows {
            guard let range = table.cellRange(of: .area, in: row) else {
                continue
            }
            let name = scanner.plainText(in: range)
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    public func containsAttachment(withPrefix prefix: String) -> Bool {
        scanner.contains(Self.attachmentReference(prefix), in: 0..<scanner.bytes.count)
    }

    public func identifier(ofAttachmentPrefix prefix: String) -> Int? {
        guard let table else {
            return nil
        }
        let reference = Self.attachmentReference(prefix)
        guard let row = table.dataRows.first(where: { scanner.contains(reference, in: $0.range) }) else {
            return nil
        }
        return identifier(of: row, in: table)
    }

    public func inserting(_ row: NewBugRow) throws -> BugPageInsertion {
        guard let table else {
            throw BugPageError.tableNotFound
        }
        let highestIdentifier = table.dataRows.compactMap { identifier(of: $0, in: table) }.max() ?? 0
        let newIdentifier = highestIdentifier + 1
        var insertedText = BugRowRenderer.render(row, identifier: newIdentifier, columns: table.columns)
        let blankIndex = table.firstTrailingBlankIndex
        let replacedRange: Range<Int>
        let bodyRows = ([table.headerRow] + table.dataRows).filter { $0.sectionName != "thead" }
        if blankIndex < table.dataRows.count {
            replacedRange = table.dataRows[blankIndex].range
        } else if let lastRow = bodyRows.last {
            replacedRange = lastRow.range.upperBound..<lastRow.range.upperBound
        } else if let bodyContentStart = table.bodyContentStart {
            replacedRange = bodyContentStart..<bodyContentStart
        } else {
            let headEnd = table.headEnd ?? table.headerRow.range.upperBound
            replacedRange = headEnd..<headEnd
            insertedText = "<tbody>" + insertedText + "</tbody>"
        }
        var bytes = Array(scanner.bytes[..<replacedRange.lowerBound])
        bytes.append(contentsOf: Array(insertedText.utf8))
        bytes.append(contentsOf: scanner.bytes[replacedRange.upperBound...])
        return BugPageInsertion(storage: String(decoding: bytes, as: UTF8.self), identifier: newIdentifier)
    }

    private func identifier(of row: TableRow, in table: BugTable) -> Int? {
        guard let range = table.cellRange(of: .identifier, in: row) else {
            return nil
        }
        let digits = scanner.plainText(in: range).filter { $0.isASCII && $0.isNumber }
        return Int(digits)
    }

    private static func attachmentReference(_ prefix: String) -> [UInt8] {
        Array("ri:filename=\"\(prefix)".utf8)
    }
}

enum BugRowRenderer {
    static let thumbnailWidth = 150

    static func render(_ row: NewBugRow, identifier: Int, columns: [ColumnKind?]) -> String {
        let cells = columns.map { column -> String in
            switch column {
            case .identifier:
                return "<td>\(identifier)</td>"
            case .status:
                return "<td><div class=\"content-wrapper\">\(BugStatus.open.macro)</div></td>"
            case .kind:
                return "<td>\(StorageText.escaped(row.kind.rawValue))</td>"
            case .area:
                return "<td>\(StorageText.escaped(row.areaName))</td>"
            case .description:
                return "<td>\(StorageText.escaped(row.comment))</td>"
            case .images:
                let images = row.attachmentFileNames.map { fileName in
                    "<p><ac:image ac:thumbnail=\"true\" ac:width=\"\(thumbnailWidth)\"><ri:attachment ri:filename=\"\(StorageText.escaped(fileName))\" /></ac:image></p>"
                }
                return "<td><div class=\"content-wrapper\">\(images.joined())</div></td>"
            case .history, nil:
                return "<td><br /></td>"
            }
        }
        return "<tr>\(cells.joined())</tr>"
    }
}

struct BugPageParser {
    let scanner: StorageScanner

    func parse() -> BugTable? {
        var tableDepth = 0
        var builder: TableBuilder?
        for tag in scanner.tags(in: 0..<scanner.bytes.count) {
            if tag.name == "table" {
                if tag.kind == .opening {
                    tableDepth += 1
                    if tableDepth == 1 {
                        builder = TableBuilder()
                    }
                } else if tag.kind == .closing, tableDepth > 0 {
                    tableDepth -= 1
                    if tableDepth == 0 {
                        if let table = builder?.makeTable(scanner: scanner) {
                            return table
                        }
                        builder = nil
                    }
                }
                continue
            }
            if tableDepth == 1 {
                builder?.consume(tag)
            }
        }
        return nil
    }
}

struct TableBuilder {
    private var rows: [TableRow] = []
    private var currentSection: String?
    private var bodyContentStart: Int?
    private var headEnd: Int?
    private var rowStart: Int?
    private var rowSection: String?
    private var rowCellRanges: [Range<Int>] = []
    private var cellContentStart: Int?

    mutating func consume(_ tag: StorageTag) {
        switch tag.name {
        case "thead", "tbody", "tfoot":
            if tag.kind == .opening {
                currentSection = tag.name
                if tag.name == "tbody", bodyContentStart == nil {
                    bodyContentStart = tag.range.upperBound
                }
            } else if tag.kind == .closing {
                if tag.name == "thead" {
                    headEnd = tag.range.upperBound
                }
                currentSection = nil
            }
        case "tr":
            if tag.kind == .opening {
                rowStart = tag.range.lowerBound
                rowSection = currentSection
                rowCellRanges = []
                cellContentStart = nil
            } else if tag.kind == .closing, let start = rowStart {
                rows.append(TableRow(
                    range: start..<tag.range.upperBound,
                    sectionName: rowSection,
                    cellRanges: rowCellRanges
                ))
                rowStart = nil
            }
        case "td", "th":
            guard rowStart != nil else {
                return
            }
            switch tag.kind {
            case .opening:
                cellContentStart = tag.range.upperBound
            case .closing:
                if let start = cellContentStart {
                    rowCellRanges.append(start..<tag.range.lowerBound)
                    cellContentStart = nil
                }
            case .selfClosing:
                rowCellRanges.append(tag.range.upperBound..<tag.range.upperBound)
            }
        default:
            break
        }
    }

    func makeTable(scanner: StorageScanner) -> BugTable? {
        guard let headerRow = rows.first else {
            return nil
        }
        let columns = headerRow.cellRanges.map { ColumnKind(headerText: scanner.plainText(in: $0)) }
        guard ColumnKind.allCases.filter(\.isRequired).allSatisfy({ columns.contains($0) }) else {
            return nil
        }
        let dataRows = Array(rows.dropFirst())
        var firstTrailingBlankIndex = dataRows.count
        while firstTrailingBlankIndex > 0,
              dataRows[firstTrailingBlankIndex - 1].cellRanges.allSatisfy({ scanner.isBlank(in: $0) }) {
            firstTrailingBlankIndex -= 1
        }
        return BugTable(
            columns: columns,
            headerRow: headerRow,
            dataRows: dataRows,
            firstTrailingBlankIndex: firstTrailingBlankIndex,
            bodyContentStart: bodyContentStart,
            headEnd: headEnd
        )
    }
}
