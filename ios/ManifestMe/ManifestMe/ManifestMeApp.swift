//
//  ManifestMeApp.swift
//  ManifestMe
//
//  Created by Nick Askam on 2/4/26.
//

import SwiftUI
import LocalAuthentication

@main
struct ManifestMeApp: App {
    @StateObject var authService = AuthService()
    @StateObject var videoService = VideoService()
    @StateObject var subscriptionService = SubscriptionService()
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @Environment(\.scenePhase) var scenePhase
    @State private var isLocked: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if !hasCompletedOnboarding {
                        OnboardingView()
                    } else if authService.isAuthenticated {
                        MainTabView()
                            .environmentObject(videoService)
                    } else {
                        LoginView()
                    }
                }
                .environmentObject(authService)
                .environmentObject(subscriptionService)
                .task {
                    videoService.authService = authService
                    subscriptionService.authService = authService
                }

                // Face ID lock overlay — shown when app returns to foreground
                if isLocked {
                    BiometricLockView {
                        authenticate()
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && authService.isAuthenticated && authService.isBiometricEnabled {
                    isLocked = true
                    authenticate()
                }
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock ManifestMe") { success, _ in
            DispatchQueue.main.async {
                if success { isLocked = false }
                // If failed, overlay stays — user can tap to retry
            }
        }
    }
}

// Fullscreen overlay shown while the app is locked
struct BiometricLockView: View {
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "faceid")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                Text("ManifestMe")
                    .font(.title).bold().foregroundColor(.white)
                Button("Unlock with Face ID") {
                    onRetry()
                }
                .foregroundColor(.yellow)
            }
        }
    }
}
