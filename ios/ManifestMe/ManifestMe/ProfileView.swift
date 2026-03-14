//
//  ProfileView.swift
//  ManifestMe
//
//  Created by Nick Askam on 2/9/26.
//

import SwiftUI
import PhotosUI
import LocalAuthentication

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @State private var profileImageURL: URL?
    @State private var biometricError: String? = nil

    // --- PICKER STATE ---
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isUploading: Bool = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // AVATAR WITH PICKER OVERLAY
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        AsyncImage(url: profileImageURL) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else if isUploading {
                                ProgressView().tint(.yellow)
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
                        
                        // EDIT ICON
                        Image(systemName: "pencil.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 30))
                            .background(Color.black.clipShape(Circle()))
                    }
                }
                // TRIGGER UPLOAD ON SELECTION
                .onChange(of: selectedItem) { oldValue, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            uploadProfilePicture(data: data)
                        }
                    }
                }
                
                Text("Dreamer")
                    .font(.title).bold().foregroundColor(.white)
                
                // --- SECURITY SECTION ---
                VStack(alignment: .leading, spacing: 12) {
                    Text("Security")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)

                    Toggle(isOn: Binding(
                        get: { authService.isBiometricEnabled },
                        set: { enabled in
                            if enabled {
                                requestBiometrics { success in
                                    if success {
                                        authService.isBiometricEnabled = true
                                        UserDefaults.standard.set(true, forKey: "isBiometricEnabled")
                                    } else {
                                        biometricError = "Face ID is not available on this device."
                                    }
                                }
                            } else {
                                authService.isBiometricEnabled = false
                                UserDefaults.standard.set(false, forKey: "isBiometricEnabled")
                            }
                        }
                    )) {
                        HStack {
                            Image(systemName: "faceid")
                                .foregroundColor(.yellow)
                            Text("Require Face ID on open")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                    .tint(.yellow)

                    if let err = biometricError {
                        Text(err).font(.caption).foregroundColor(.red).padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .background(Color(white: 0.1))
                .cornerRadius(10)
                .padding(.horizontal)

                Button(action: { authService.logout() }) {
                    Text("Log Out")
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.1))
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 50)
        }
        .onAppear { fetchProfile() }
    }
    
    // --- BIOMETRICS ---
    func requestBiometrics(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable Face ID for ManifestMe") { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    // --- UPLOAD LOGIC ---
    func uploadProfilePicture(data: Data) {
        guard let token = KeychainHelper.standard.read() else { return }
        guard let url = URL(string: "https://manifest-me-api-79704250837.us-central1.run.app/api/profile/upload/") else { return }
        
        self.isUploading = true
        let boundary = "Boundary-\(UUID().uuidString)"
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // --- CONSTRUCT THE BODY MANUALLY ---
        var body = Data()
        let lineBreak = "\r\n"
        
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(data)
        body.append("\(lineBreak)--\(boundary)--\(lineBreak)".data(using: .utf8)!)

        Task {
            do {
                let (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("✅ Success! Image manifest on Neon.")
                        fetchProfile()
                    } else {
                        let msg = String(data: responseData, encoding: .utf8) ?? "Unknown Error"
                        print("❌ Code \(httpResponse.statusCode): \(msg)")
                    }
                }
                self.isUploading = false
            } catch {
                print("❌ Network Error: \(error.localizedDescription)")
                self.isUploading = false
            }
        }
    }
    
    func fetchProfile() {
        guard let token = KeychainHelper.standard.read() else { return }
        
        // ⚠️ Make sure this URL matches your backend (localhost or IP)
        guard let url = URL(string: "https://manifest-me-api-79704250837.us-central1.run.app/api/profile/status/") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("👤 Checking profile image...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                // 1. Check for basic errors
                if let error = error {
                    print("❌ Profile Error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else { return }
                
                // 2. Parse the JSON
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        // 3. Did the backend say "has_image": true?
                        if let hasImage = json["has_image"] as? Bool, hasImage == true,
                           let urlString = json["image_url"] as? String {
                            
                            // 4. Update the UI!
                            self.profileImageURL = URL(string: urlString)
                            print("✅ Loaded Profile Pic!")
                            
                        } else {
                            print("🤷‍♂️ No custom image found. Keeping placeholder.")
                        }
                    }
                } catch {
                    print("❌ JSON Decode Error: \(error)")
                }
            }
        }.resume()
    }
}
