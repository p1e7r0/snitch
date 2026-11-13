import Foundation

public enum ReportKind: String, Codable, CaseIterable, Sendable {
    case bug = "Bug"
    case feature = "Feature"
}

public struct Report: Codable, Equatable, Sendable {
    public let identifier: String
    public let createdAt: Date
    public let kind: ReportKind
    public let areaName: String
    public let comment: String
    public let imageFileNames: [String]
    public let destination: PageReference

    public init(
        identifier: String,
        createdAt: Date,
        kind: ReportKind,
        areaName: String,
        comment: String,
        imageFileNames: [String],
        destination: PageReference
    ) {
        self.identifier = identifier
        self.createdAt = createdAt
        self.kind = kind
        self.areaName = areaName
        self.comment = comment
        self.imageFileNames = imageFileNames
        self.destination = destination
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decodeIfPresent(ReportKind.self, forKey: .kind) ?? .bug
        areaName = try container.decode(String.self, forKey: .areaName)
        comment = try container.decode(String.self, forKey: .comment)
        imageFileNames = try container.decode([String].self, forKey: .imageFileNames)
        destination = try container.decode(PageReference.self, forKey: .destination)
    }

    public var attachmentPrefix: String {
        Report.attachmentPrefix(forIdentifier: identifier)
    }

    public static func attachmentPrefix(forIdentifier identifier: String) -> String {
        "snitch-\(identifier)-"
    }
}

public struct ReportDraft: Equatable, Sendable {
    public let identifier: String
    public let directory: URL
}

public struct ReportStore: Sendable {
    public let rootDirectory: URL

    private static let reportFileName = "report.json"

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func prepare() throws {
        try createPrivateDirectory(at: rootDirectory)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var directory = rootDirectory
        try directory.setResourceValues(resourceValues)
    }

    public func createDraft(now: Date = Date()) throws -> ReportDraft {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = String(format: "%04x", UInt16.random(in: UInt16.min...UInt16.max))
        let identifier = "\(formatter.string(from: now))-\(suffix)"
        let directory = rootDirectory.appending(path: identifier, directoryHint: .isDirectory)
        try createPrivateDirectory(at: directory)
        return ReportDraft(identifier: identifier, directory: directory)
    }

    public func imageFileName(for draft: ReportDraft, index: Int) -> String {
        "\(Report.attachmentPrefix(forIdentifier: draft.identifier))\(index).png"
    }

    public func discard(_ draft: ReportDraft) {
        try? FileManager.default.removeItem(at: draft.directory)
    }

    public func enqueue(
        _ draft: ReportDraft,
        kind: ReportKind,
        areaName: String,
        comment: String,
        imageFileNames: [String],
        destination: PageReference,
        now: Date = Date()
    ) throws -> Report {
        let report = Report(
            identifier: draft.identifier,
            createdAt: now,
            kind: kind,
            areaName: areaName,
            comment: comment,
            imageFileNames: imageFileNames,
            destination: destination
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: draft.directory.appending(path: Self.reportFileName), options: .atomic)
        return report
    }

    public func pendingReports() -> [Report] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reports = reportDirectories().compactMap { directory -> Report? in
            guard let data = try? Data(contentsOf: directory.appending(path: Self.reportFileName)) else {
                return nil
            }
            return try? decoder.decode(Report.self, from: data)
        }
        return reports.sorted { first, second in
            (first.createdAt, first.identifier) < (second.createdAt, second.identifier)
        }
    }

    public func directory(for report: Report) -> URL {
        rootDirectory.appending(path: report.identifier, directoryHint: .isDirectory)
    }

    public func remove(_ report: Report) {
        try? FileManager.default.removeItem(at: directory(for: report))
    }

    public func purgeAbandonedDrafts() {
        for directory in reportDirectories() {
            let reportFile = directory.appending(path: Self.reportFileName)
            if !FileManager.default.fileExists(atPath: reportFile.path) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func createPrivateDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func reportDirectories() -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return (contents ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
