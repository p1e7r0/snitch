import AppKit
import Network
import SnitchCore

final class QueueCoordinator {
    struct PendingItem {
        let report: Report
        let failure: String?
    }

    var onChange: (() -> Void)?

    private let store: ReportStore
    private let notifier: Notifier
    private let settings: AppSettings
    private let pathMonitor = NWPathMonitor()
    private var failures: [String: String] = [:]
    private var isProcessing = false
    private var needsAnotherPass = false
    private var retryTask: Task<Void, Never>?
    private var retryDelay = QueueCoordinator.initialRetryDelay

    private static let initialRetryDelay = Duration.seconds(15)
    private static let maximumRetryDelay = Duration.seconds(300)

    init(store: ReportStore, notifier: Notifier, settings: AppSettings) {
        self.store = store
        self.notifier = notifier
        self.settings = settings
    }

    var pendingItems: [PendingItem] {
        store.pendingReports().map { PendingItem(report: $0, failure: failures[$0.identifier]) }
    }

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else {
                return
            }
            Task { @MainActor in
                self?.retryNow()
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.retryNow()
            }
        }
        processQueue()
    }

    func retryNow() {
        retryDelay = Self.initialRetryDelay
        processQueue()
    }

    func processQueue() {
        if isProcessing {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        retryTask?.cancel()
        Task {
            await submitPendingReports()
            isProcessing = false
            onChange?()
            if needsAnotherPass {
                needsAnotherPass = false
                processQueue()
            } else {
                scheduleRetryIfNeeded()
            }
        }
    }

    func discard(_ report: Report) {
        store.remove(report)
        failures[report.identifier] = nil
        onChange?()
    }

    private func submitPendingReports() async {
        var clients: [URL: ConfluenceClient] = [:]
        var blockedHosts: Set<String?> = []
        for report in store.pendingReports() where !blockedHosts.contains(report.destination.host) {
            do {
                let client = try clients[report.destination.baseURL] ?? TokenStore.makeClient(for: report.destination)
                clients[report.destination.baseURL] = client
                let result = try await ReportSubmitter(service: client)
                    .submit(report, imageDirectory: store.directory(for: report))
                store.remove(report)
                failures[report.identifier] = nil
                retryDelay = Self.initialRetryDelay
                let label = result.identifier.map { "\(report.kind.rawValue) \($0)" } ?? report.kind.rawValue
                notifier.notify(
                    title: report.kind == .feature
                        ? String(localized: "notification.added.feature", defaultValue: "\(label) added")
                        : String(localized: "notification.added.bug", defaultValue: "\(label) added"),
                    subtitle: settings.pageLabel(for: report.destination),
                    body: "\(report.areaName) · \(report.comment)",
                    pageURL: report.destination.viewURL
                )
            } catch {
                let description = FailureDescription.text(for: error)
                let previousDescription = failures[report.identifier]
                failures[report.identifier] = description
                if previousDescription != description {
                    notifier.notify(
                        title: String(localized: "Report queued, retrying automatically"),
                        subtitle: settings.pageLabel(for: report.destination),
                        body: description,
                        pageURL: nil
                    )
                }
                if Self.blocksHost(error) {
                    blockedHosts.insert(report.destination.host)
                }
            }
            onChange?()
        }
    }

    private static func blocksHost(_ error: Error) -> Bool {
        switch error {
        case ConfigurationError.missingToken, ConfluenceError.network, ConfluenceError.authentication:
            return true
        default:
            return false
        }
    }

    private func scheduleRetryIfNeeded() {
        guard !store.pendingReports().isEmpty else {
            retryDelay = Self.initialRetryDelay
            return
        }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.maximumRetryDelay)
        retryTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            processQueue()
        }
    }
}
