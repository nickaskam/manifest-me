//
//  OnboardingView.swift
//  ManifestMe
//

import SwiftUI
import PhotosUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @State private var currentPage: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardingPage1().tag(0)
                OnboardingPage2().tag(1)
                OnboardingPage3().tag(2)
                OnboardingPage4(onFinish: { hasCompletedOnboarding = true }).tag(3)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
        }
    }
}

// MARK: - Page 1: Welcome

private struct OnboardingPage1: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 80))
                .foregroundColor(.yellow)
            Text("ManifestMe")
                .font(.largeTitle).bold().foregroundColor(.white)
            Text("Visualize your future.\nManifest your reality.")
                .font(.title3)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Spacer()
            Text("Swipe to continue →")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.6))
                .padding(.bottom, 60)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Page 2: How it works

private struct OnboardingPage2: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("How It Works")
                .font(.title).bold().foregroundColor(.white)

            VStack(alignment: .leading, spacing: 24) {
                HowItWorksRow(icon: "pencil.and.outline", color: .yellow,
                              title: "Describe your dream",
                              detail: "Write your future in the present tense — as if it's already true.")
                HowItWorksRow(icon: "wand.and.stars", color: .purple,
                              title: "AI creates your video",
                              detail: "Our AI generates a cinematic clip of you living that dream.")
                HowItWorksRow(icon: "play.rectangle.fill", color: .blue,
                              title: "Watch it daily",
                              detail: "Re-watch to reinforce your vision and build belief.")
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct HowItWorksRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundColor(.white)
                Text(detail).font(.subheadline).foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Page 3: Permissions

private struct OnboardingPage3: View {
    @State private var askedPhotos = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 70))
                .foregroundColor(.yellow)
            Text("One quick thing")
                .font(.title).bold().foregroundColor(.white)
            Text("ManifestMe puts *you* in your dream video. We need access to your photos so you can set a profile picture that our AI uses to generate your clips.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            if !askedPhotos {
                Button(action: requestPhotos) {
                    Text("Allow Photo Access")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
            } else {
                Text("✓ Permission requested")
                    .foregroundColor(.green)
            }

            Spacer()
            Text("Swipe to continue →")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.6))
                .padding(.bottom, 60)
        }
        .padding(.horizontal, 32)
    }

    func requestPhotos() {
        askedPhotos = true
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
    }
}

// MARK: - Page 4: Get Started

private struct OnboardingPage4: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundColor(.yellow)
            Text("You're ready.")
                .font(.largeTitle).bold().foregroundColor(.white)
            Text("Start by creating your account and choosing your first manifestation path.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button(action: onFinish) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow)
                    .cornerRadius(12)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
