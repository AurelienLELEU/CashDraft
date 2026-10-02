import Foundation
import Security

enum DeviceIdentity {
    private static let service = "com.cashdraft.device"
    private static let account = "install-identity"

    /// A keychain item normally survives app reinstallation on iOS. It is only a deterrent,
    /// never a replacement for StoreKit purchase verification and restoration.
    static func existingOrCreate() -> (id: String, isNew: Bool) {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) { return (value, false) }
        let value = UUID().uuidString
        query.removeValue(forKey: kSecReturnData as String)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
        return (value, true)
    }

    private static let licenseAccount = "license-state"

    static func loadLicense() -> AppLicense? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: licenseAccount, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AppLicense.self, from: data)
    }

    static func saveLicense(_ license: AppLicense) {
        guard let data = try? JSONEncoder().encode(license) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: licenseAccount]
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
