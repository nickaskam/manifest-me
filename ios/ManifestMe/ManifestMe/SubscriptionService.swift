//
//  SubscriptionService.swift
//  ManifestMe
//

import Foundation
import StoreKit

@MainActor
class SubscriptionService: ObservableObject {
    // The product ID you will create in App Store Connect
    static let monthlyProductID = "com.manifestme.monthly"

    @Published var isSubscribed: Bool = false
    @Published var videosRemaining: Int = 0
    @Published var isLoading: Bool = false
    @Published var purchaseError: String? = nil

    // Available StoreKit products loaded from App Store Connect
    @Published var product: Product? = nil

    var authService: AuthService?

    // MARK: - Load product from App Store

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.monthlyProductID])
            product = products.first
        } catch {
            print("❌ StoreKit: Could not load products: \(error)")
        }
    }

    // MARK: - Check subscription status from backend

    func checkStatus() async {
        guard let authService,
              let url = URL(string: "\(authService.baseURL)/subscription/status/") else { return }

        let request = URLRequest(url: url)
        do {
            let (data, statusCode) = try await authService.makeAuthenticatedRequest(request)
            guard statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            isSubscribed = json["is_active"] as? Bool ?? false
            videosRemaining = json["videos_remaining"] as? Int ?? 0
        } catch {
            print("❌ Subscription status check failed: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else {
            purchaseError = "Product not available. Try again later."
            return
        }
        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await verifyWithBackend(transaction: transaction)
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Restore purchases

    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
            await checkStatus()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Private helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw URLError(.badServerResponse)
        case .verified(let value):
            return value
        }
    }

    private func verifyWithBackend(transaction: Transaction) async {
        guard let authService,
              let url = URL(string: "\(authService.baseURL)/subscription/verify/") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let expiresAt = transaction.expirationDate?.ISO8601Format() ?? ""
        let body: [String: Any] = [
            "transaction_id": String(transaction.id),
            "expires_at": expiresAt
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, statusCode) = try await authService.makeAuthenticatedRequest(request)
            if statusCode == 200 {
                isSubscribed = true
                videosRemaining = 1
                print("✅ Subscription activated on backend.")
            }
        } catch {
            print("❌ Backend subscription verification failed: \(error)")
        }
    }
}
