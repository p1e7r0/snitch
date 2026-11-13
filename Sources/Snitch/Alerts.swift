import AppKit

enum Alerts {
    @discardableResult
    static func run(title: String, text: String, buttons: [String] = []) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
