import Foundation
import Observation
import SnitchCore

struct Destination: Codable, Equatable {
    var identifier: String
    var address: String
    var title: String?
    var cachedAreaNames: [String] = []
    var lastAreaName: String?

    var reference: PageReference? {
        PageReference(pageAddress: address)
    }

    var host: String? {
        reference?.host
    }

    var displayName: String {
        title ?? address
    }
}

enum ConfigurationError: Error, Equatable {
    case missingToken(host: String)
    case unrecognizedAddress
}

@Observable
final class AppSettings {
    var destinations: [Destination] {
        didSet { store(destinations, forKey: Key.destinations) }
    }

    var lastDestinationIdentifier: String? {
        didSet { defaults.set(lastDestinationIdentifier, forKey: Key.lastDestinationIdentifier) }
    }

    var hotKey: HotKeyCombination {
        didSet { store(hotKey, forKey: Key.hotKey) }
    }

    var didSetUpLaunchAtLogin: Bool {
        didSet { defaults.set(didSetUpLaunchAtLogin, forKey: Key.didSetUpLaunchAtLogin) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let destinations = "destinations"
        static let lastDestinationIdentifier = "lastDestinationIdentifier"
        static let hotKey = "hotKey"
        static let didSetUpLaunchAtLogin = "didSetUpLaunchAtLogin"
        static let legacyPageAddress = "pageAddress"
        static let legacyLastAreaName = "lastAreaName"
        static let legacyCachedAreaNames = "cachedAreaNames"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        destinations = Self.load([Destination].self, forKey: Key.destinations, from: defaults) ?? []
        lastDestinationIdentifier = defaults.string(forKey: Key.lastDestinationIdentifier)
        hotKey = Self.load(HotKeyCombination.self, forKey: Key.hotKey, from: defaults) ?? .standard
        didSetUpLaunchAtLogin = defaults.bool(forKey: Key.didSetUpLaunchAtLogin)
        migrateLegacySettings()
    }

    var usableDestinations: [Destination] {
        destinations.filter { $0.reference != nil }
    }

    var currentDestination: Destination? {
        let usable = usableDestinations
        return usable.first { $0.identifier == lastDestinationIdentifier } ?? usable.first
    }

    var isConfigured: Bool {
        guard let host = currentDestination?.host else {
            return false
        }
        return TokenStore.read(host: host) != nil
    }

    func destination(withIdentifier identifier: String) -> Destination? {
        destinations.first { $0.identifier == identifier }
    }

    func destination(for reference: PageReference) -> Destination? {
        destinations.first { $0.reference == reference }
    }

    func pageLabel(for reference: PageReference) -> String? {
        usableDestinations.count > 1 ? destination(for: reference)?.displayName : nil
    }

    func updateDestination(withIdentifier identifier: String, _ update: (inout Destination) -> Void) {
        guard let index = destinations.firstIndex(where: { $0.identifier == identifier }) else {
            return
        }
        update(&destinations[index])
    }

    @discardableResult
    func addDestination(address: String, title: String? = nil) -> Destination {
        let destination = Destination(identifier: UUID().uuidString, address: address, title: title)
        destinations.append(destination)
        return destination
    }

    func removeDestination(withIdentifier identifier: String) {
        destinations.removeAll { $0.identifier == identifier }
    }

    func refreshDestination(withIdentifier identifier: String) async throws -> PageSummary {
        guard let reference = destination(withIdentifier: identifier)?.reference else {
            throw ConfigurationError.unrecognizedAddress
        }
        let summary = try await TokenStore.makeClient(for: reference).summarizePage(reference.pageIdentifier)
        updateDestination(withIdentifier: identifier) {
            $0.title = summary.title
            $0.cachedAreaNames = summary.areaNames
        }
        return summary
    }

    private func migrateLegacySettings() {
        if defaults.data(forKey: Key.destinations) == nil,
           let address = defaults.string(forKey: Key.legacyPageAddress), !address.isEmpty {
            destinations = [Destination(
                identifier: UUID().uuidString,
                address: address,
                title: nil,
                cachedAreaNames: defaults.stringArray(forKey: Key.legacyCachedAreaNames) ?? [],
                lastAreaName: defaults.string(forKey: Key.legacyLastAreaName)
            )]
        }
        for key in [Key.legacyPageAddress, Key.legacyLastAreaName, Key.legacyCachedAreaNames] {
            defaults.removeObject(forKey: key)
        }
    }

    private func store<Value: Encodable>(_ value: Value, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
