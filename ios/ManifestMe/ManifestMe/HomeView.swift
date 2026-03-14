//
//  HomeView.swift
//  ManifestMe
//
//  Created by Nick Askam on 2/4/26.
//

import SwiftUI
import AVKit

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var videoService: VideoService
    @State private var showCreateSheet = false
    
    // Grid Layout: 2 columns
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView { // Wrap in Nav View for full screen playback
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(alignment: .leading) {
                        // --- HEADER ---
                        HStack {
                            Text("My Manifestations")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { authService.logout() }) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        
                        // --- 1. STATUS BAR (If Cooking) ---
                        if videoService.isManifesting {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("✨ Manifesting your dream...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                ProgressView(value: videoService.progress)
                                    .tint(.yellow)
                                
                                // Suggestion: Add a "Background" tip
                                Text("This takes about 5 mins. You can safely close the app; we're working in the cloud!")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .italic()
                            }
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.2)) // Dark Purple/Blue background
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1) // Gold border
                            )
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity)) // Slide & Fade animation
                        }
                        
                        // --- 2. THE GALLERY GRID ---
                        if videoService.myVideos.isEmpty {
                            Text("No manifestations yet. Start dreaming!")
                                .foregroundColor(.gray)
                                .padding(.top, 50)
                                .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(videoService.myVideos) { video in
                                    NavigationLink(destination: FullScreenPlayer(videoURL: URL(string: video.url)!)) {
                                        VStack {
                                            // Simple Thumbnail / Placeholder
                                            ZStack {
                                                // 1. The Async Thumbnail Generator
                                                VideoThumbnail(url: URL(string: video.url)!)
                                                    .aspectRatio(16/9, contentMode: .fill) // ✅ New Landscape Mode
                                                    .frame(minWidth: 0, maxWidth: .infinity)
                                                    .cornerRadius(12)
                                                    .clipped() // Don't let images bleed out
                                                
                                                // 2. Play Icon Overlay
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(.white.opacity(0.8))
                                                    .shadow(radius: 4)
                                            }
                                            
                                            Text("Dream \(video.name.prefix(8))...") // Short name
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            // --- LOAD VIDEOS ON APPEAR ---
            .onAppear {
                if let token = KeychainHelper.standard.read() {
                    // 1. Load the history as usual
                    videoService.fetchVideos(token: token)
                    
                    // 2. NEW: If we were manifesting when the app closed, resume polling
                    // You'll need to store 'pollingJobId' in UserDefaults if you want
                    // it to survive a full app kill, but for now, this handles navigation:
                    if let jobId = videoService.pollingJobId {
                        videoService.pollForVideoStatus(jobId: jobId, token: token)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateView(theme: "wildlife")
            }
            .overlay(alignment: .bottom) {
                 // Floating Action Button for "Create"
                 Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus")
                        .font(.title)
                        .padding()
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
                .padding(.bottom, 20)
            }
        }
    }
}

// Helper: Full Screen Player
struct FullScreenPlayer: View {
    let videoURL: URL
    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                 // Auto-play when opened
                 AVPlayer(url: videoURL).play()
            }
    }
}
