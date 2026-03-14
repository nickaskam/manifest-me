//
//  VideoService.swift
//  ManifestMe
//
//  Created by Nick Askam on 2/9/26.
//

import Foundation
import Combine

struct ManifestationVideo: Identifiable, Decodable {
    let id = UUID()
    let url: String
    let name: String

    private enum CodingKeys: String, CodingKey {
        case url
        case name
    }
}

@MainActor
class VideoService: ObservableObject {
    // --- STATE ---
    @Published var isManifesting: Bool = false
    @Published var currentVideoURL: URL? = nil
    @Published var errorMessage: String = ""
    @Published var pollingJobId: String? = nil
    @Published var myVideos: [ManifestationVideo] = []
    @Published var progress: Float = 0.0

    // Injected by ManifestMeApp — used for automatic 401 handling
    var authService: AuthService?

    private let baseURL = "https://manifest-me-api-79704250837.us-central1.run.app/api"
    private var progressTimer: Timer?

    // MARK: - Fetch past videos

    func fetchVideos(token: String) {
        guard let url = URL(string: "\(baseURL)/videos/") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        Task {
            do {
                let (data, statusCode) = try await authenticatedData(for: request)

                if let rawJSON = String(data: data, encoding: .utf8) {
                    print("🔍 Videos response: \(rawJSON)")
                }

                if statusCode == 200 {
                    let videos = try JSONDecoder().decode([ManifestationVideo].self, from: data)
                    self.myVideos = videos
                    print("✅ Loaded \(videos.count) videos.")
                } else {
                    print("⚠️ fetchVideos: server returned \(statusCode)")
                }
            } catch {
                print("❌ fetchVideos error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Start a new manifestation

    func manifest(prompt: String, theme: String, token: String) {
        isManifesting = true
        progress = 0.0
        startProgressSimulation()

        guard let url = URL(string: "\(baseURL)/manifest/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": prompt, "theme": theme])

        Task {
            do {
                let (data, statusCode) = try await authenticatedData(for: request)

                if statusCode == 202,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let jobId = json["video_id"] as? String {
                    pollingJobId = jobId
                    await pollForCompletion(jobId: jobId, token: token)
                } else if statusCode == 403,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let err = json["error"] as? String {
                    isManifesting = false
                    stopProgress()
                    errorMessage = err == "quota_exceeded"
                        ? "You've used your video for this month. Come back next month!"
                        : "A subscription is required to manifest."
                } else {
                    isManifesting = false
                    stopProgress()
                    errorMessage = "Failed to start manifestation."
                }
            } catch {
                isManifesting = false
                stopProgress()
                print("❌ manifest error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Poll for video completion

    func pollForVideoStatus(jobId: String, token: String) {
        Task {
            await pollForCompletion(jobId: jobId, token: token)
        }
    }

    private func pollForCompletion(jobId: String, token: String) async {
        guard let url = URL(string: "\(baseURL)/videos/status/\(jobId)/") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await authenticatedData(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else { return }

            if status == "COMPLETED" {
                if let urlString = json["video_url"] as? String {
                    currentVideoURL = URL(string: urlString)
                }
                isManifesting = false
                pollingJobId = nil
                stopProgress()
                fetchVideos(token: token)
            } else if status == "FAILED" {
                isManifesting = false
                pollingJobId = nil
                stopProgress()
                errorMessage = "Manifestation failed."
            } else {
                // Still processing — wait 10s and retry
                try await Task.sleep(nanoseconds: 10_000_000_000)
                await pollForCompletion(jobId: jobId, token: token)
            }
        } catch {
            // URLError.userAuthenticationRequired means makeAuthenticatedRequest already logged us out
            print("❌ polling error: \(error.localizedDescription)")
            isManifesting = false
        }
    }

    // MARK: - Private helpers

    /// Routes the request through AuthService (which handles 401 → refresh → retry),
    /// falling back to a plain URLSession call if authService isn't wired up yet.
    private func authenticatedData(for request: URLRequest) async throws -> (Data, Int) {
        if let authService {
            return try await authService.makeAuthenticatedRequest(request)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private func startProgressSimulation() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if self.progress < 0.90 { self.progress += 0.01 }
        }
    }

    private func stopProgress() {
        progressTimer?.invalidate()
        progress = 1.0
    }
}
