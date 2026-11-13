import AppKit
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let pageAddressKey = "pageAddress"

    private var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func prepare() {
        guard isAvailable else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
    }

    func notify(title: String, subtitle: String?, body: String, pageURL: URL?) {
        guard isAvailable else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        if let pageURL {
            content.userInfo = [Self.pageAddressKey: pageURL.absoluteString]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let address = response.notification.request.content.userInfo[Self.pageAddressKey] as? String
        completionHandler()
        guard let address, let pageURL = URL(string: address) else {
            return
        }
        Task { @MainActor in
            NSWorkspace.shared.open(pageURL)
        }
    }
}
