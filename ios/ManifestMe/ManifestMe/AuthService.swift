//
//  AuthService.swift
//  ManifestMe
//
//  Created by Nick Askam on 2/9/26.
//

import Foundation
import Combine

@MainActor
class AuthService: ObservableObject {
    // --- STATE ---
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var isBiometricEnabled: Bool = UserDefaults.standard.bool(forKey: "isBiometricEnabled")

    // Same URL as before — hardcoded is fine for MVP
    let baseURL = "https://manifest-me-api-79704250837.us-central1.run.app/api"

    // --- INITIALIZATION ---
    init() {
        if KeychainHelper.standard.read() != nil {
            print("🔑 Token found in Keychain. Restoring session.")
            self.isAuthenticated = true
        }
    }

    // --- 1. REGISTER ---
    func register(email: String, password: String, inviteCode: String) {
        isLoading = true
        errorMessage = ""

        guard let url = URL(string: "\(baseURL)/register/") else { return }
        let body: [String: Any] = ["email": email, "password": password, "invite_code": inviteCode]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                isLoading = false
                if status == 200 {
                    handleSuccess(data: data)
                } else if status == 403 {
                    errorMessage = "🚫 Invalid or Expired Invite Code."
                } else {
                    errorMessage = "Registration failed. Email might already be registered."
                }
            } catch {
                isLoading = false
                errorMessage = "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    // --- 2. LOGIN ---
    func login(email: String, password: String) {
        isLoading = true
        errorMessage = ""

        guard let url = URL(string: "\(baseURL)/login/") else { return }
        let body: [String: Any] = ["username": email, "password": password]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                isLoading = false
                if status == 200 {
                    handleSuccess(data: data)
                } else {
                    errorMessage = "Invalid email or password."
                }
            } catch {
                isLoading = false
                errorMessage = "Connection Error: \(error.localizedDescription)"
            }
        }
    }

    // --- 3. LOGOUT ---
    func logout() {
        KeychainHelper.standard.delete()
        KeychainHelper.standard.deleteRefreshToken()
        isAuthenticated = false
    }

    // --- 4. AUTHENTICATED REQUEST ---
    // Makes an API call with the current token. If the server returns 401 (expired token),
    // it automatically tries to refresh the token once, then retries. If refresh also
    // fails, the user is logged out and the call throws an error.
    func makeAuthenticatedRequest(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, statusCode) = try await executeWithCurrentToken(request)

        if statusCode == 401 {
            let refreshed = await tryRefreshToken()
            if refreshed {
                let (retryData, retryStatus) = try await executeWithCurrentToken(request)
                if retryStatus == 401 {
                    logout()
                    throw URLError(.userAuthenticationRequired)
                }
                return (retryData, retryStatus)
            } else {
                logout()
                throw URLError(.userAuthenticationRequired)
            }
        }

        return (data, statusCode)
    }

    // MARK: - Private helpers

    private func executeWithCurrentToken(_ request: URLRequest) async throws -> (Data, Int) {
        var req = request
        if let token = KeychainHelper.standard.read() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private func tryRefreshToken() async -> Bool {
        guard let refreshToken = KeychainHelper.standard.readRefreshToken(),
              let url = URL(string: "\(baseURL)/token/refresh/") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh": refreshToken])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["access"] as? String else {
                print("🔑 Token refresh failed — logging out.")
                return false
            }
            KeychainHelper.standard.save(token: newAccess)
            print("🔑 Token refreshed successfully.")
            return true
        } catch {
            return false
        }
    }

    private func handleSuccess(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access"] as? String else {
            errorMessage = "Failed to parse server response."
            return
        }
        KeychainHelper.standard.save(token: accessToken)
        if let refreshToken = json["refresh"] as? String {
            KeychainHelper.standard.saveRefreshToken(refreshToken)
        }
        isAuthenticated = true
        print("🎉 Auth Success! Tokens saved.")
    }
}
