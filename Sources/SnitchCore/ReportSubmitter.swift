import Foundation

public struct SubmissionResult: Equatable, Sendable {
    public let identifier: Int?
}

public enum SubmissionError: Error, Equatable {
    case tooManyConflicts
}

public struct ReportSubmitter: Sendable {
    private let service: any ConfluenceService
    private let maximumAttempts: Int

    public init(service: any ConfluenceService, maximumAttempts: Int = 5) {
        self.service = service
        self.maximumAttempts = maximumAttempts
    }

    public func submit(_ report: Report, imageDirectory: URL) async throws -> SubmissionResult {
        var didUploadAttachments = false
        for _ in 0..<maximumAttempts {
            let page = try await service.fetchPage(report.destination.pageIdentifier)
            let bugPage = BugPage(storage: page.storage)
            if bugPage.containsAttachment(withPrefix: report.attachmentPrefix) {
                return SubmissionResult(identifier: bugPage.identifier(ofAttachmentPrefix: report.attachmentPrefix))
            }
            guard bugPage.hasTable else {
                throw BugPageError.tableNotFound
            }
            if !didUploadAttachments {
                try await uploadMissingAttachments(for: report, imageDirectory: imageDirectory)
                didUploadAttachments = true
            }
            let row = NewBugRow(
                kind: report.kind,
                areaName: report.areaName,
                comment: report.comment,
                attachmentFileNames: report.imageFileNames
            )
            let insertion = try bugPage.inserting(row)
            do {
                try await service.updatePage(
                    page,
                    storage: insertion.storage,
                    message: "Snitch: \(report.kind.rawValue) \(insertion.identifier) in \(insertion.language.vocabulary.quoted(report.areaName))"
                )
                return SubmissionResult(identifier: insertion.identifier)
            } catch ConfluenceError.versionConflict {
                continue
            }
        }
        throw SubmissionError.tooManyConflicts
    }

    private func uploadMissingAttachments(for report: Report, imageDirectory: URL) async throws {
        let pageIdentifier = report.destination.pageIdentifier
        for fileName in report.imageFileNames {
            if try await service.attachmentExists(pageIdentifier: pageIdentifier, fileName: fileName) {
                continue
            }
            let data = try Data(contentsOf: imageDirectory.appending(path: fileName))
            do {
                try await service.uploadAttachment(pageIdentifier: pageIdentifier, fileName: fileName, data: data)
            } catch let error as ConfluenceError {
                guard case .server = error,
                      try await service.attachmentExists(pageIdentifier: pageIdentifier, fileName: fileName) else {
                    throw error
                }
            }
        }
    }
}
