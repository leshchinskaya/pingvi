import CryptoKit
import Foundation
import Security

public struct PingviPairingRecord: Codable, Equatable, Sendable {
    public let serviceID: String
    public let localDeviceID: String
    public let peerDeviceID: String
    public let peerName: String
    public let pairingKey: Data
    public let createdAt: Date

    public init(
        serviceID: String,
        localDeviceID: String,
        peerDeviceID: String,
        peerName: String,
        pairingKey: Data,
        createdAt: Date = Date()
    ) {
        self.serviceID = serviceID
        self.localDeviceID = localDeviceID
        self.peerDeviceID = peerDeviceID
        self.peerName = peerName
        self.pairingKey = pairingKey
        self.createdAt = createdAt
    }

    public var fingerprint: String {
        SHA256.hash(data: pairingKey).prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

public final class PingviKeychain: @unchecked Sendable {
    public let service: String

    public init(service: String = "app.pingvi.link") {
        self.service = service
    }

    public func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    public func set(_ data: Data, for account: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = lookup
            attributes.forEach { add[$0.key] = $0.value }
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw keychainError(status) }
        } else if update != errSecSuccess {
            throw keychainError(update)
        }
    }

    public func remove(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    public func codable<T: Decodable>(_ type: T.Type, for account: String) -> T? {
        guard let data = data(for: account) else { return nil }
        return try? JSONDecoder.pingvi.decode(type, from: data)
    }

    public func setCodable<T: Encodable>(_ value: T, for account: String) throws {
        try set(JSONEncoder.pingvi.encode(value), for: account)
    }

    private func keychainError(_ status: OSStatus) -> Error {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Ошибка Keychain \(status)"]
        )
    }
}
