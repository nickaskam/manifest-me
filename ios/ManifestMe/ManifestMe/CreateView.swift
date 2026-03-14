import SwiftUI

struct CreateView: View {
    let theme: String

    @EnvironmentObject var videoService: VideoService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var subscriptionService: SubscriptionService

    @Environment(\.dismiss) var dismiss

    @State private var prompt: String = ""
    @State private var showPaywall: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                // Close button
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                                .padding()
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .zIndex(1)

                VStack(spacing: 20) {
                    Text("Dream It.")
                        .font(.largeTitle).bold().foregroundColor(.white)
                        .padding(.top, 40)

                    Text("Describe your future reality in the present tense.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    TextEditor(text: $prompt)
                        .frame(height: 150)
                        .padding()
                        .background(Color(white: 0.1))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        )
                        .padding()

                    Spacer()

                    Button(action: handleManifest) {
                        Text("Start Manifesting")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(prompt.isEmpty ? Color.gray : Color.yellow)
                            .cornerRadius(12)
                    }
                    .disabled(prompt.isEmpty)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(subscriptionService)
            }
        }
        .task { await subscriptionService.checkStatus() }
    }

    private func handleManifest() {
        guard let token = KeychainHelper.standard.read() else { return }

        // If not subscribed, show paywall instead of starting
        if !subscriptionService.isSubscribed {
            showPaywall = true
            return
        }

        print("📌 sending theme=\(theme) prompt=\(prompt)")
        videoService.manifest(prompt: prompt, theme: theme, token: token)
        dismiss()
    }
}
