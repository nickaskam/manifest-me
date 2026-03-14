//
//  PaywallView.swift
//  ManifestMe
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                // --- Header ---
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundColor(.yellow)
                    Text("Unlock ManifestMe")
                        .font(.title).bold().foregroundColor(.white)
                    Text("Subscribe to generate your monthly manifestation video.")
                        .font(.body).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // --- What's included ---
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "video.fill",     text: "1 personalized AI video per month")
                    FeatureRow(icon: "person.fill",    text: "Your face placed in the scene")
                    FeatureRow(icon: "play.circle.fill", text: "Watch & re-watch anytime")
                }
                .padding()
                .background(Color(white: 0.1))
                .cornerRadius(16)
                .padding(.horizontal)

                // --- Price ---
                if let product = subscriptionService.product {
                    Text("\(product.displayPrice) / month")
                        .font(.title2).bold().foregroundColor(.white)
                } else {
                    ProgressView().tint(.yellow)
                }

                // --- Error ---
                if let err = subscriptionService.purchaseError {
                    Text(err).font(.caption).foregroundColor(.red).padding(.horizontal)
                }

                // --- Subscribe button ---
                Button(action: {
                    Task { await subscriptionService.purchase() }
                }) {
                    Group {
                        if subscriptionService.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text("Subscribe")
                                .font(.headline).foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow)
                    .cornerRadius(12)
                }
                .disabled(subscriptionService.isLoading || subscriptionService.product == nil)
                .padding(.horizontal)

                // --- Restore ---
                Button("Restore Purchases") {
                    Task { await subscriptionService.restorePurchases() }
                }
                .font(.footnote).foregroundColor(.gray)

                Button("Not now") { dismiss() }
                    .font(.footnote).foregroundColor(.gray.opacity(0.6))

                Spacer()
            }
            .padding(.top, 48)
        }
        .onChange(of: subscriptionService.isSubscribed) { _, subscribed in
            if subscribed { dismiss() }
        }
        .task { await subscriptionService.loadProduct() }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.yellow).frame(width: 24)
            Text(text).foregroundColor(.white).font(.subheadline)
        }
    }
}
