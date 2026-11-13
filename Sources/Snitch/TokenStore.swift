import Foundation
import Security
import SnitchCore

enum TokenStore {
    private static let service = "local.snitch.confluence"
    private static let legacyAccount = "personal-access-token"

    static func read(host: String) -> String? {
        readItem(account: host)
    }

    static func save(_ token: String, host: String) -> Bool {
        let query = baseQuery(account: host)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrLabel as String] = String(localized: "Snitch: Confluence token (\(host))")
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func makeClient(for reference: PageReference) throws -> ConfluenceClient {
        let host = reference.host ?? reference.baseURL.absoluteString
        guard let token = read(host: host) else {
            throw ConfigurationError.missingToken(host: host)
        }
        return ConfluenceClient(baseURL: reference.baseURL, token: token)
    }

    static func migrateLegacyToken(toHost host: String?) {
        guard let host, let legacyToken = readItem(account: legacyAccount) else {
            return
        }
        if read(host: host) != nil || save(legacyToken, host: host) {
            SecItemDelete(baseQuery(account: legacyAccount) as CFDictionary)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readItem(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }
}
