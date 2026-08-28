import CryptoKit
import Foundation
import Security

enum DeviceIdentityKey {
  private static let service = "dev.jvroth.eng.direct-pairing"
  private static let privateKeyAccount = "client-private-key-v1"
  private static let serverKeyAccount = "trusted-server-public-key-v1"

  static func loadOrCreate() -> Curve25519.KeyAgreement.PrivateKey {
    if let data = read(account: privateKeyAccount),
      let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    {
      return key
    }
    let key = Curve25519.KeyAgreement.PrivateKey()
    store(key.rawRepresentation, account: privateKeyAccount)
    return key
  }

  static func acceptsServerPublicKey(_ key: Data) -> Bool {
    if let trusted = read(account: serverKeyAccount) { return trusted == key }
    store(key, account: serverKeyAccount)
    return read(account: serverKeyAccount) == key
  }

  private static func read(account: String) -> Data? {
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

  private static func store(_ data: Data, account: String) {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let match: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: account,
      ]
      SecItemUpdate(match as CFDictionary, [kSecValueData: data] as CFDictionary)
    }
  }
}
