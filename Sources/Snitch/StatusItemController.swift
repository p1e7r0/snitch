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
        menu.addItem(makeActionItem(title: String(localized: "New report (\(settings.hotKey.display))")) { [weak self] in
            self?.onReport()
        })

        let pendingItems = coordinator.pendingItems
        if !pendingItems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabledItem(
                pendingItems.count == 1
                    ? String(localized: "1 report queued")
                    : String(localized: "\(pendingItems.count) reports queued")
            ))
            for pendingItem in pendingItems {
                menu.addItem(makeItem(for: pendingItem))
            }
            menu.addItem(makeActionItem(title: String(localized: "Retry now")) { [weak self] in
                self?.coordinator.retryNow()
            })
        }

        menu.addItem(.separator())
        let pageURLs = settings.usableDestinations.compactMap { destination in
            destination.reference.map { (name: destination.displayName, url: $0.viewURL) }
        }
        for page in pageURLs {
            let title = pageURLs.count == 1
                ? String(localized: "Open the reports page")
                : String(localized: "Open “\(page.name)”")
            menu.addItem(makeActionItem(title: title) {
                NSWorkspace.shared.open(page.url)
            })
        }
        menu.addItem(makeActionItem(title: String(localized: "Settings…")) { [weak self] in
            self?.onOpenSettings()
        })
        menu.addItem(.separator())
        menu.addItem(makeActionItem(title: String(localized: "Quit Snitch")) {
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
        submenu.addItem(disabledItem(pendingItem.failure ?? String(localized: "Waiting to be sent")))
        submenu.addItem(.separator())

        submenu.addItem(makeActionItem(title: String(localized: "Delete the report…")) { [weak self] in
            self?.confirmDiscard(report)
        })
        item.submenu = submenu
        return item
    }

    private func confirmDiscard(_ report: Report) {
        let response = Alerts.run(
            title: String(localized: "Delete the queued report?"),
            text: String(localized: "“\(report.comment)” and its screenshots will be deleted without being sent."),
            buttons: [String(localized: "Delete"), String(localized: "Cancel")]
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
