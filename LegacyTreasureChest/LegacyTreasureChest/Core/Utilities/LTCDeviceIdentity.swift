//
//  LTCDeviceIdentity.swift
//  LegacyTreasureChest
//
//  Keychain-backed stable device identifier for request headers.
//  No tracking, no analytics — local-only identifier.
//

import Foundation
import Security

enum LTCDeviceIdentity {

    private static let service = "com.legacytreasurechest.device"
    private static let account = "ltc-device-id"

    static func deviceID() -> String {
        if let existing = readString(service: service, account: account) {
            return existing
        }

        let newID = UUID().uuidString
        _ = saveString(newID, service: service, account: account)
        return newID
    }

    enum KeychainDeletionResult {
        case deleted
        case notFound
    }

    /// Deletes the diagnostic device identifier from the Keychain, scoped
    /// to the exact service/account pair used by `deviceID()`. Does not
    /// generate a new identifier — the next call to `deviceID()` will
    /// lazily create one, unchanged from existing behavior. Used only by
    /// the full data-reset flow.
    @discardableResult
    static func deleteStoredIdentity() throws -> KeychainDeletionResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess:
            return .deleted
        case errSecItemNotFound:
            return .notFound
        default:
            throw AppError.dataError("Keychain delete failed with status \(status).")
        }
    }

    // MARK: - Keychain helpers

    private static func readString(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    @discardableResult
    private static func saveString(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)

        // Delete any existing item first (simplest reliable approach).
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
}
