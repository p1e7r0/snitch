import AppKit
import Carbon.HIToolbox

struct HotKeyCombination: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let standard = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_B),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⌃⌥⌘B"
    )

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: String(localized: "Space"),
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
    ]

    static func from(event: NSEvent) -> HotKeyCombination? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }
        var carbonModifiers = 0
        var symbols = ""
        if flags.contains(.control) {
            carbonModifiers |= controlKey
            symbols += "⌃"
        }
        if flags.contains(.option) {
            carbonModifiers |= optionKey
            symbols += "⌥"
        }
        if flags.contains(.shift) {
            carbonModifiers |= shiftKey
            symbols += "⇧"
        }
        if flags.contains(.command) {
            carbonModifiers |= cmdKey
            symbols += "⌘"
        }
        let keyName = specialKeyNames[Int(event.keyCode)]
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "?"
        return HotKeyCombination(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: UInt32(carbonModifiers),
            display: symbols + keyName
        )
    }
}

final class GlobalHotKey {
    var action: (() -> Void)?
    private var hotKeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            handleHotKeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
    }

    @discardableResult
    func register(_ combination: HotKeyCombination) -> Bool {
        unregister()
        let identifier = EventHotKeyID(signature: OSType(0x534E_4954), id: 1)
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        hotKeyReference = nil
    }
}

private nonisolated func handleHotKeyEvent(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }
    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else {
            return
        }
        Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue().action?()
    }
    return noErr
}
