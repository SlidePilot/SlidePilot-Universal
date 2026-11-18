import Foundation
import Security
import SlidePilotRemoteProtocol

/// Keeps pairing keys in the Keychain (ADR 0017): one generic password per trusted device,
/// readable only on this device and never synced, because a key belongs to one device pair.
///
/// On macOS the app uses the file-based Keychain: the data protection Keychain needs a
/// keychain access group entitlement, which ad-hoc signed test builds cannot have.
nonisolated struct KeychainTrustStore: TrustStore {
    struct KeychainError: Error, Equatable {
        let status: OSStatus
    }

    /// One item per device; the account is the instance ID, the data a `StoredEntry`.
    private struct StoredEntry: Codable {
        let device: TrustedDevice
        let key: Data
    }

    private let service: String

    /// `service` names the Keychain items; tests use their own name.
    init(service: String) {
        self.service = service
    }

    func key(for instanceID: InstanceID) -> PairingKey? {
        guard let entry = entry(for: instanceID) else { return nil }
        return PairingKey(rawRepresentation: entry.key)
    }

    func devices() -> [TrustedDevice] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [Data] else { return [] }
        return items.compactMap { try? JSONDecoder().decode(StoredEntry.self, from: $0).device }
            .sorted { $0.deviceName.localizedStandardCompare($1.deviceName) == .orderedAscending }
    }

    func trust(_ device: TrustedDevice, key: PairingKey) throws {
        let data = try JSONEncoder().encode(StoredEntry(device: device, key: key.rawRepresentation))
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: "SlidePilot Remote: \(device.deviceName)",
        ]
        // Update in place, so a concurrent pairing of the same device never sees it missing.
        var status = SecItemUpdate(baseQuery(account: device.instanceID) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(account: device.instanceID).merging(attributes) { _, new in new }
            #if os(iOS)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func removeTrust(for instanceID: InstanceID) throws {
        let status = SecItemDelete(baseQuery(account: instanceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func entry(for instanceID: InstanceID) -> StoredEntry? {
        var query = baseQuery(account: instanceID)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(StoredEntry.self, from: data)
    }

    private func baseQuery(account: InstanceID? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        if let account {
            query[kSecAttrAccount as String] = account.description
        }
        return query
    }
}
