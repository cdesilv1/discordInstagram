"""
Main content view for the Instagram to Discord iOS app.
Handles Instagram OAuth authentication and image posting functionality.
"""

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var instagramManager = InstagramManager()
    @StateObject private var s3Manager = S3Manager()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isUploading = false
    @State private var uploadStatus = ""
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text("Instagram to Discord")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Post your Instagram content and sync to Discord")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Authentication Section
                VStack(spacing: 15) {
                    if instagramManager.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected to Instagram")
                                .fontWeight(.medium)
                        }
                        
                        Button("Disconnect") {
                            instagramManager.logout()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        Text("Connect your Instagram account to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Connect Instagram") {
                            instagramManager.authenticate()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(12)
                
                // Image Selection and Upload Section
                if instagramManager.isAuthenticated {
                    VStack(spacing: 15) {
                        // Photo Picker
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 10,
                            matching: .images
                        ) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Select Photos")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .onChange(of: selectedItems) { items in
                            Task {
                                await loadSelectedImages(from: items)
                            }
                        }
                        
                        // Selected Images Preview
                        if !selectedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(selectedImages.indices, id: \.self) { index in
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                            .cornerRadius(8)
                                            .overlay(
                                                Button(action: {
                                                    selectedImages.remove(at: index)
                                                    selectedItems.remove(at: index)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.white)
                                                        .background(Color.black.opacity(0.7))
                                                        .clipShape(Circle())
                                                }
                                                .offset(x: 8, y: -8),
                                                alignment: .topTrailing
                                            )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Upload Button
                        Button(action: uploadImages) {
                            HStack {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "icloud.and.arrow.up")
                                }
                                Text(isUploading ? "Uploading..." : "Upload to Instagram & Discord")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedImages.isEmpty || isUploading)
                        
                        // Upload Status
                        if !uploadStatus.isEmpty {
                            Text(uploadStatus)
                                .font(.caption)
                                .foregroundColor(uploadStatus.contains("Error") ? .red : .green)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Instagram Sync")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Upload Complete", isPresented: .constant(!uploadStatus.isEmpty && uploadStatus.contains("Success"))) {
            Button("OK") {
                uploadStatus = ""
                selectedImages.removeAll()
                selectedItems.removeAll()
            }
        } message: {
            Text(uploadStatus)
        }
        .alert("Upload Error", isPresented: .constant(!uploadStatus.isEmpty && uploadStatus.contains("Error"))) {
            Button("OK") {
                uploadStatus = ""
            }
        } message: {
            Text(uploadStatus)
        }
    }
    
    // Load selected images from PhotosPicker
    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        selectedImages.removeAll()
        
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    selectedImages.append(image)
                }
            }
        }
    }
    
    // Upload images to Instagram and S3
    private func uploadImages() {
        guard !selectedImages.isEmpty else { return }
        
        isUploading = true
        uploadStatus = "Preparing upload..."
        
        Task {
            do {
                // Post to Instagram first
                await MainActor.run {
                    uploadStatus = "Posting to Instagram..."
                }
                
                let instagramResults = try await instagramManager.postImages(selectedImages)
                
                // Upload to S3 for Discord processing
                await MainActor.run {
                    uploadStatus = "Syncing to Discord..."
                }
                
                let s3Results = try await s3Manager.uploadImages(selectedImages)
                
                await MainActor.run {
                    uploadStatus = "Success! Posted \(instagramResults.count) images to Instagram and synced to Discord."
                    isUploading = false
                }
                
            } catch {
                await MainActor.run {
                    uploadStatus = "Error: \(error.localizedDescription)"
                    isUploading = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}