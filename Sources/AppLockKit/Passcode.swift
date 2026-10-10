import CryptoKit
import Foundation
import Security

/// App-wide passcode API. The real work lives in `PasscodeStore`, which can be
/// pointed at a throwaway Keychain service for tests.
enum Passcode {

    private static let shared = PasscodeStore(service: "com.aryan.applock", account: "passcode")

    static var isSet: Bool { shared.isSet }
    static func set(_ pin: String) { shared.set(pin) }
    static func verify(_ pin: String) -> Bool { shared.verify(pin) }
    static func clear() { shared.clear() }
}

/// Stores the passcode as a salted SHA-256 hash in the Keychain. The plaintext
/// passcode is never written anywhere.
struct PasscodeStore {

    let service: String
    let account: String

    init(service: String, account: String = "passcode") {
        self.service = service
        self.account = account
    }

    var isSet: Bool { loadHash() != nil }

    /// Saves a new passcode, replacing any existing one.
    func set(_ pin: String) {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 16, buffer.baseAddress!)
        }
        let hash = derive(pin: pin, salt: salt)
        write(value: "\(salt.hexString)$\(hash.hexString)")
    }

    func verify(_ pin: String) -> Bool {
        guard let stored = loadHash() else { return false }
        let parts = stored.split(separator: "$", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let salt = Data(hexString: parts[0]),
              let expected = Data(hexString: parts[1]) else { return false }
        let actual = derive(pin: pin, salt: salt)
        return constantTimeEquals(actual, expected)
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Internals

    private func derive(pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func write(value: String) {
        let data = Data(value.utf8)
        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private func loadHash() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(chars[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self = Data(bytes)
    }
}
