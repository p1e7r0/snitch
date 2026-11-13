import AppKit
import SnitchCore

final class MenuAction: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invokeHandler() {
        handler()
    }
}

func makeActionItem(title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler: handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.invokeHandler), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    return item
}

final class StatusItemController: NSObject, NSMenuDelegate {
    var onReport: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: QueueCoordinator
    private let settings: AppSettings

    private static let maximumCommentLength = 40

    init(coordinator: QueueCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "ladybug", accessibilityDescription: "Snitch")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func refresh() {
        let count = coordinator.pendingItems.count
        statusItem.button?.title = count > 0 ? " \(count)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(makeActionItem(title: "Nuova segnalazione (\(settings.hotKey.display))") { [weak self] in
            self?.onReport()
        })

        let pendingItems = coordinator.pendingItems
        if !pendingItems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabledItem(pendingItems.count == 1 ? "1 segnalazione in coda" : "\(pendingItems.count) segnalazioni in coda"))
            for pendingItem in pendingItems {
                menu.addItem(makeItem(for: pendingItem))
            }
            menu.addItem(makeActionItem(title: "Riprova ora") { [weak self] in
                self?.coordinator.retryNow()
            })
        }

        menu.addItem(.separator())
        let pageURLs = settings.usableDestinations.compactMap { destination in
            destination.reference.map { (name: destination.displayName, url: $0.viewURL) }
        }
        for page in pageURLs {
            let title = pageURLs.count == 1 ? "Apri la pagina delle segnalazioni" : "Apri «\(page.name)»"
            menu.addItem(makeActionItem(title: title) {
                NSWorkspace.shared.open(page.url)
            })
        }
        menu.addItem(makeActionItem(title: "Impostazioni…") { [weak self] in
            self?.onOpenSettings()
        })
        menu.addItem(.separator())
        menu.addItem(makeActionItem(title: "Esci da Snitch") {
            NSApp.terminate(nil)
        })
    }

    private func makeItem(for pendingItem: QueueCoordinator.PendingItem) -> NSMenuItem {
        let report = pendingItem.report
        var title = report.comment
        if title.count > Self.maximumCommentLength {
            title = String(title.prefix(Self.maximumCommentLength)) + "…"
        }
        let item = NSMenuItem(title: "\(report.kind.rawValue) · \(report.areaName): \(title)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(disabledItem(pendingItem.failure ?? "In attesa di invio"))
        submenu.addItem(.separator())

        submenu.addItem(makeActionItem(title: "Elimina la segnalazione…") { [weak self] in
            self?.confirmDiscard(report)
        })
        item.submenu = submenu
        return item
    }

    private func confirmDiscard(_ report: Report) {
        let response = Alerts.run(
            title: "Eliminare la segnalazione in coda?",
            text: "«\(report.comment)» e i suoi screenshot verranno cancellati senza essere inviati.",
            buttons: ["Elimina", "Annulla"]
        )
        if response == .alertFirstButtonReturn {
            coordinator.discard(report)
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
