import AppKit
import SnitchCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
    private let launchLanguage = AppLanguage.selected
    private let notifier = Notifier()
    private let hotKey = GlobalHotKey()
    private var coordinator: QueueCoordinator?
    private var reportFlow: ReportFlow?
    private var statusItemController: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning {
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = makeMainMenu()

        let store = ReportStore(rootDirectory: queueDirectory)
        do {
            try store.prepare()
        } catch {
            Alerts.run(
                title: String(localized: "Snitch cannot start"),
                text: String(localized: "Could not create the queue folder: \(error.localizedDescription)")
            )
            NSApp.terminate(nil)
            return
        }
        store.purgeAbandonedDrafts()

        TokenStore.migrateLegacyToken(toHost: settings.destinations.first?.host)
        notifier.prepare()

        let coordinator = QueueCoordinator(store: store, notifier: notifier, settings: settings)
        let reportFlow = ReportFlow(
            store: store,
            settings: settings,
            onEnqueued: { [weak coordinator] in coordinator?.retryNow() },
            onNeedsConfiguration: { [weak self] in self?.showSettings() }
        )
        let statusItemController = StatusItemController(coordinator: coordinator, settings: settings)
        statusItemController.onReport = { [weak reportFlow] in reportFlow?.trigger() }
        statusItemController.onOpenSettings = { [weak self] in self?.showSettings() }
        coordinator.onChange = { [weak statusItemController] in statusItemController?.refresh() }

        self.coordinator = coordinator
        self.reportFlow = reportFlow
        self.statusItemController = statusItemController

        hotKey.action = { [weak reportFlow] in reportFlow?.trigger() }
        hotKey.register(settings.hotKey)

        setUpLaunchAtLoginOnFirstRun()
        coordinator.start()

        if !settings.isConfigured {
            showSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
        hotKey.register(settings.hotKey)
    }

    private var isAnotherInstanceRunning: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).count > 1
    }

    private var queueDirectory: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appending(path: "Snitch", directoryHint: .isDirectory)
            .appending(path: "Queue", directoryHint: .isDirectory)
    }

    private func showSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(settings: settings, launchLanguage: launchLanguage)
            model.onRestart = { [weak self] in
                self?.restart()
            }
            model.onTokenSaved = { [weak self] in
                self?.coordinator?.retryNow()
            }
            model.onRecordingChange = { [weak self] isRecording in
                guard let self else {
                    return
                }
                if isRecording {
                    self.hotKey.unregister()
                } else {
                    self.hotKey.register(self.settings.hotKey)
                }
            }
            let hostingController = NSHostingController(rootView: SettingsView(model: model))
            hostingController.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Snitch settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    private func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \"$0\" 2>/dev/null; do sleep 0.1; done; open \"$1\"",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundlePath,
        ]
        guard (try? process.run()) != nil else {
            return
        }
        NSApp.terminate(nil)
    }

    private func setUpLaunchAtLoginOnFirstRun() {
        guard !settings.didSetUpLaunchAtLogin else {
            return
        }
        let bundlePath = Bundle.main.bundlePath
        let applicationDirectories = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        guard applicationDirectories.contains(where: { bundlePath.hasPrefix($0) }) else {
            return
        }
        settings.didSetUpLaunchAtLogin = true
        LaunchAtLogin.setEnabled(true)
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: String(localized: "Quit Snitch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        return mainMenu
    }
}
