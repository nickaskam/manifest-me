//
//  KeychainHelper.swift
//  ManifestMe
//
//  Created by Nick Askam on 2/4/26.
//
import Security
import Foundation

class KeychainHelper {
    static let standard = KeychainHelper()
    private let service = "com.manifestme.auth"
    private let accessAccount = "authToken"
    private let refreshAccount = "authRefreshToken"

    // MARK: - Access Token

    func save(token: String) {
        saveItem(token, account: accessAccount)
    }

    func read() -> String? {
        readItem(account: accessAccount)
    }

    func delete() {
        deleteItem(account: accessAccount)
    }

    // MARK: - Refresh Token

    func saveRefreshToken(_ token: String) {
        saveItem(token, account: refreshAccount)
    }

    func readRefreshToken() -> String? {
        readItem(account: refreshAccount)
    }

    func deleteRefreshToken() {
        deleteItem(account: refreshAccount)
    }

    // MARK: - Private helpers

    private func saveItem(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as [String: Any]
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = data
        SecItemAdd(newItem as CFDictionary, nil)
    }

    private func readItem(account: String) -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [String: Any]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func deleteItem(account: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as [String: Any]
        SecItemDelete(query as CFDictionary)
    }
}
