import Foundation
import Security

enum RemoteRelaySecretStore {
  private static let service = "dev.jvroth.eng.remote-relay"
  private static let account = "channel-token-v1"

  static func load() -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }

  static func save(_ token: Data) throws {
    let match: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let attributes: [CFString: Any] = [
      kSecValueData: token,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(match.merging(attributes) { _, new in new } as CFDictionary, nil)
    if status == errSecDuplicateItem {
      guard SecItemUpdate(match as CFDictionary, attributes as CFDictionary) == errSecSuccess else {
        throw RemoteRelaySecretError.keychain
      }
    } else if status != errSecSuccess {
      throw RemoteRelaySecretError.keychain
    }
  }

  static func remove() {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

protocol RemoteRelaySecretStoring: Sendable {
  func load() -> Data?
  func save(_ token: Data) throws
  func remove()
}

struct KeychainRemoteRelaySecretStore: RemoteRelaySecretStoring {
  func load() -> Data? { RemoteRelaySecretStore.load() }
  func save(_ token: Data) throws { try RemoteRelaySecretStore.save(token) }
  func remove() { RemoteRelaySecretStore.remove() }
}

enum RemoteRelaySecretError: LocalizedError {
  case keychain
  var errorDescription: String? { "Eng could not save the remote channel token in Keychain." }
}
