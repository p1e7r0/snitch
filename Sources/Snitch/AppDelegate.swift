import AppKit
import SnitchCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
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
                title: "Snitch non può partire",
                text: "Non riesco a creare la cartella della coda: \(error.localizedDescription)"
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
            let model = SettingsModel(settings: settings)
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
            window.title = "Impostazioni di Snitch"
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
            withTitle: "Esci da Snitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editMenu = NSMenu(title: "Modifica")
        editMenu.addItem(withTitle: "Annulla", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Ripristina", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Taglia", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Seleziona tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowMenu = NSMenu(title: "Finestra")
        windowMenu.addItem(withTitle: "Chiudi", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        return mainMenu
    }
}
