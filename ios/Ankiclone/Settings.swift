import Foundation
import Security

/// Server address and API token. The token lives in the Keychain, never in the repo or UserDefaults.
enum AppSettings {
  private static let urlKey = "serverURL"
  private static let account = "apiToken"

  static var serverURL: String {
    get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: urlKey) }
  }

  static var token: String {
    get {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
      ]
      var item: AnyObject?
      guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
      return String(decoding: data, as: UTF8.self)
    }
    set {
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
      SecItemDelete(query as CFDictionary)
      guard !newValue.isEmpty else { return }
      var attributes = query
      attributes[kSecValueData as String] = Data(newValue.utf8)
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(attributes as CFDictionary, nil)
    }
  }

  static var isConfigured: Bool { !serverURL.isEmpty && !token.isEmpty }
}
