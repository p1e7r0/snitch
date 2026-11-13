import AppKit
import SnitchCore
import SwiftUI

final class ReportPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class ReportFlow: NSObject, NSWindowDelegate {
    private final class Session {
        let draft: ReportDraft
        let model: ReportDraftModel
        let panel: ReportPanel
        var nextImageIndex = 2
        var refreshTask: Task<Void, Never>?

        init(draft: ReportDraft, model: ReportDraftModel, panel: ReportPanel) {
            self.draft = draft
            self.model = model
            self.panel = panel
        }
    }

    private let store: ReportStore
    private let settings: AppSettings
    private let onEnqueued: () -> Void
    private let onNeedsConfiguration: () -> Void
    private var session: Session?
    private var isCapturing = false

    init(
        store: ReportStore,
        settings: AppSettings,
        onEnqueued: @escaping () -> Void,
        onNeedsConfiguration: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onEnqueued = onEnqueued
        self.onNeedsConfiguration = onNeedsConfiguration
    }

    func trigger() {
        guard !isCapturing else {
            return
        }
        if let session {
            addScreenshot(to: session)
            return
        }
        guard settings.isConfigured else {
            onNeedsConfiguration()
            return
        }
        guard ensureScreenCapturePermission() else {
            return
        }
        guard let draft = try? store.createDraft() else {
            Alerts.run(
                title: String(localized: "Unable to prepare the report"),
                text: String(localized: "Could not write to the application folder.")
            )
            return
        }
        isCapturing = true
        Task {
            let draftImage = await capture(into: draft, index: 1)
            isCapturing = false
            guard let draftImage else {
                store.discard(draft)
                return
            }
            openSession(draft: draft, firstImage: draftImage)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }

    private func capture(into draft: ReportDraft, index: Int) async -> DraftImage? {
        let fileName = store.imageFileName(for: draft, index: index)
        let fileURL = draft.directory.appending(path: fileName)
        guard await ScreenCapture.captureSelection(to: fileURL),
              let data = try? Data(contentsOf: fileURL),
              let image = NSImage(data: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return DraftImage(fileName: fileName, image: image)
    }

    private func openSession(draft: ReportDraft, firstImage: DraftImage) {
        let model = ReportDraftModel()
        model.images = [firstImage]
        model.destinationOptions = settings.usableDestinations.map {
            DestinationOption(identifier: $0.identifier, name: $0.displayName)
        }
        model.selectedDestinationIdentifier = settings.currentDestination?.identifier ?? ""

        let panel = ReportPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "New report")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }

        let hostingController = NSHostingController(rootView: ReportView(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hostingController

        let newSession = Session(draft: draft, model: model, panel: panel)
        session = newSession
        model.onSend = { [weak self] in self?.send() }
        model.onCancel = { [weak self] in self?.cancel() }
        model.onAddScreenshot = { [weak self] in self?.trigger() }
        model.onRemoveImage = { [weak self] fileName in self?.removeImage(named: fileName) }
        model.onDestinationChange = { [weak self, weak newSession] in
            guard let self, let newSession else {
                return
            }
            self.loadSelectedDestination(for: newSession)
        }

        loadSelectedDestination(for: newSession)
        position(panel)
        show(panel, model: model)
    }

    private func loadSelectedDestination(for session: Session) {
        guard let destination = settings.destination(withIdentifier: session.model.selectedDestinationIdentifier) else {
            return
        }
        session.model.areaName = destination.lastAreaName ?? ""
        session.model.areaSuggestions = areaSuggestions(for: destination)
        session.model.notice = nil
        refreshAreaNames(for: session, destinationIdentifier: destination.identifier)
    }

    private func addScreenshot(to session: Session) {
        isCapturing = true
        session.panel.orderOut(nil)
        let index = session.nextImageIndex
        session.nextImageIndex += 1
        Task {
            let draftImage = await capture(into: session.draft, index: index)
            isCapturing = false
            guard self.session === session else {
                return
            }
            if let draftImage {
                session.model.images.append(draftImage)
            }
            show(session.panel, model: session.model)
        }
    }

    private func removeImage(named fileName: String) {
        guard let session, session.model.images.count > 1 else {
            return
        }
        session.model.images.removeAll { $0.fileName == fileName }
        try? FileManager.default.removeItem(at: session.draft.directory.appending(path: fileName))
    }

    private func send() {
        guard let session, session.model.canSend else {
            return
        }
        let destinationIdentifier = session.model.selectedDestinationIdentifier
        guard let reference = settings.destination(withIdentifier: destinationIdentifier)?.reference else {
            onNeedsConfiguration()
            return
        }
        let areaName = session.model.trimmedAreaName
        do {
            _ = try store.enqueue(
                session.draft,
                kind: session.model.kind,
                areaName: areaName,
                comment: session.model.trimmedComment,
                imageFileNames: session.model.images.map(\.fileName),
                destination: reference
            )
        } catch {
            session.model.notice = String(localized: "Could not save the report: \(error.localizedDescription)")
            return
        }
        settings.lastDestinationIdentifier = destinationIdentifier
        settings.updateDestination(withIdentifier: destinationIdentifier) { $0.lastAreaName = areaName }
        close(session)
        onEnqueued()
    }

    private func cancel() {
        guard let session else {
            return
        }
        store.discard(session.draft)
        close(session)
    }

    private func close(_ session: Session) {
        self.session = nil
        session.refreshTask?.cancel()
        session.panel.orderOut(nil)
    }

    private func show(_ panel: ReportPanel, model: ReportDraftModel) {
        panel.makeKeyAndOrderFront(nil)
        model.focusRequestCount += 1
    }

    private func position(_ panel: ReportPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2 + visibleFrame.height * 0.1
        )
        panel.setFrameOrigin(origin)
    }

    private func refreshAreaNames(for session: Session, destinationIdentifier: String) {
        session.refreshTask?.cancel()
        session.refreshTask = Task {
            let notice: String?
            do {
                let summary = try await settings.refreshDestination(withIdentifier: destinationIdentifier)
                notice = summary.hasTable
                    ? nil
                    : String(localized: "\(FailureDescription.missingTableText) The report will stay in the queue.")
            } catch {
                notice = String(localized: "Area list not updated. \(FailureDescription.text(for: error)) The report will stay in the queue.")
            }
            guard !Task.isCancelled,
                  self.session === session,
                  session.model.selectedDestinationIdentifier == destinationIdentifier,
                  let destination = settings.destination(withIdentifier: destinationIdentifier) else {
                return
            }
            session.model.areaSuggestions = areaSuggestions(for: destination)
            session.model.notice = notice
        }
    }

    private func areaSuggestions(for destination: Destination) -> [String] {
        var names = destination.cachedAreaNames
        if let lastAreaName = destination.lastAreaName, !lastAreaName.isEmpty, !names.contains(lastAreaName) {
            names.append(lastAreaName)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func ensureScreenCapturePermission() -> Bool {
        if ScreenCapture.hasPermission {
            return true
        }
        ScreenCapture.requestPermission()
        let response = Alerts.run(
            title: String(localized: "Screen recording permission required"),
            text: String(localized: "Enable Snitch in System Settings → Privacy & Security → Screen & System Audio Recording, then restart Snitch."),
            buttons: [String(localized: "Open System Settings"), String(localized: "Cancel")]
        )
        if response == .alertFirstButtonReturn,
           let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(settingsURL)
        }
        return false
    }
}
