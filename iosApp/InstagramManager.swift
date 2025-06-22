"""
Instagram Manager for handling OAuth authentication and posting images.
Uses Instagram Basic Display API for authentication and Instagram Graph API for posting.
"""

import Foundation
import SwiftUI
import AuthenticationServices

@MainActor
class InstagramManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userProfile: InstagramUser?
    
    private let clientId = Bundle.main.object(forInfoDictionaryKey: "INSTAGRAM_CLIENT_ID") as? String ?? ""
    private let clientSecret = Bundle.main.object(forInfoDictionaryKey: "INSTAGRAM_CLIENT_SECRET") as? String ?? ""
    private let redirectUri = "instagram-discord-app://auth"
    
    private var accessToken: String? {
        get {
            UserDefaults.standard.string(forKey: "instagram_access_token")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "instagram_access_token")
            isAuthenticated = newValue != nil
        }
    }
    
    private var userID: String? {
        get {
            UserDefaults.standard.string(forKey: "instagram_user_id")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "instagram_user_id")
        }
    }
    
    init() {
        // Check if user is already authenticated
        isAuthenticated = accessToken != nil
        if isAuthenticated {
            Task {
                await loadUserProfile()
            }
        }
    }
    
    // MARK: - Authentication
    
    func authenticate() {
        let authURL = buildAuthURL()
        
        if let url = URL(string: authURL) {
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "instagram-discord-app"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    if let error = error {
                        print("Authentication error: \(error)")
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        print("No callback URL received")
                        return
                    }
                    
                    await self?.handleAuthCallback(callbackURL)
                }
            }
            
            session.presentationContextProvider = AuthenticationContextProvider()
            session.start()
        }
    }
    
    private func buildAuthURL() -> String {
        let baseURL = "https://api.instagram.com/oauth/authorize"
        let scope = "user_profile,user_media"
        
        return "\(baseURL)?client_id=\(clientId)&redirect_uri=\(redirectUri)&scope=\(scope)&response_type=code"
    }
    
    private func handleAuthCallback(_ url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("Invalid callback URL")
            return
        }
        
        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            print("Authentication error: \(error)")
            return
        }
        
        // Get authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            print("No authorization code received")
            return
        }
        
        // Exchange code for access token
        await exchangeCodeForToken(code)
    }
    
    private func exchangeCodeForToken(_ code: String) async {
        let tokenURL = "https://api.instagram.com/oauth/access_token"
        
        guard let url = URL(string: tokenURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri,
            "code": code
        ]
        
        let bodyString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String,
               let userId = json["user_id"] as? Int {
                
                accessToken = token
                userID = String(userId)
                
                // Get long-lived token
                await getLongLivedToken(token)
                
                // Load user profile
                await loadUserProfile()
            }
        } catch {
            print("Token exchange error: \(error)")
        }
    }
    
    private func getLongLivedToken(_ shortLivedToken: String) async {
        let baseURL = "https://graph.instagram.com/access_token"
        let urlString = "\(baseURL)?grant_type=ig_exchange_token&client_secret=\(clientSecret)&access_token=\(shortLivedToken)"
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let longLivedToken = json["access_token"] as? String {
                accessToken = longLivedToken
            }
        } catch {
            print("Long-lived token error: \(error)")
        }
    }
    
    // MARK: - User Profile
    
    private func loadUserProfile() async {
        guard let token = accessToken else { return }
        
        let fields = "id,username,account_type,media_count"
        let urlString = "https://graph.instagram.com/me?fields=\(fields)&access_token=\(token)"
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let profile = try JSONDecoder().decode(InstagramUser.self, from: data)
            userProfile = profile
        } catch {
            print("Profile loading error: \(error)")
        }
    }
    
    // MARK: - Image Posting
    
    func postImages(_ images: [UIImage]) async throws -> [String] {
        guard let token = accessToken, let userId = userID else {
            throw InstagramError.notAuthenticated
        }
        
        var mediaIds: [String] = []
        
        // Upload each image as media
        for (index, image) in images.enumerated() {
            do {
                let mediaId = try await uploadSingleImage(image, token: token, userId: userId)
                mediaIds.append(mediaId)
            } catch {
                print("Error uploading image \(index): \(error)")
                throw error
            }
        }
        
        // Publish media
        var publishedIds: [String] = []
        for mediaId in mediaIds {
            do {
                let publishedId = try await publishMedia(mediaId: mediaId, token: token, userId: userId)
                publishedIds.append(publishedId)
            } catch {
                print("Error publishing media \(mediaId): \(error)")
                throw error
            }
        }
        
        return publishedIds
    }
    
    private func uploadSingleImage(_ image: UIImage, token: String, userId: String) async throws -> String {
        // Convert image to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw InstagramError.imageProcessingFailed
        }
        
        // Upload to temporary storage (you'd typically use your own server or cloud storage)
        let imageUrl = try await uploadImageToTemporaryStorage(imageData)
        
        // Create Instagram media container
        let baseURL = "https://graph.instagram.com/\(userId)/media"
        let urlString = "\(baseURL)?image_url=\(imageUrl)&access_token=\(token)"
        
        guard let url = URL(string: urlString) else {
            throw InstagramError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw InstagramError.uploadFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let mediaId = json?["id"] as? String else {
            throw InstagramError.invalidResponse
        }
        
        return mediaId
    }
    
    private func publishMedia(mediaId: String, token: String, userId: String) async throws -> String {
        let baseURL = "https://graph.instagram.com/\(userId)/media_publish"
        let urlString = "\(baseURL)?creation_id=\(mediaId)&access_token=\(token)"
        
        guard let url = URL(string: urlString) else {
            throw InstagramError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw InstagramError.publishFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let publishedId = json?["id"] as? String else {
            throw InstagramError.invalidResponse
        }
        
        return publishedId
    }
    
    private func uploadImageToTemporaryStorage(_ imageData: Data) async throws -> String {
        // This is a placeholder implementation
        // In a real app, you'd upload to your own server or cloud storage
        // and return the public URL
        
        // For now, we'll simulate this process
        let fileName = "\(UUID().uuidString).jpg"
        let imageUrl = "https://your-temp-storage.com/\(fileName)"
        
        // Here you would implement actual upload logic
        // For example, upload to your server, AWS S3, etc.
        
        return imageUrl
    }
    
    // MARK: - Logout
    
    func logout() {
        accessToken = nil
        userID = nil
        userProfile = nil
        isAuthenticated = false
    }
}

// MARK: - Models

struct InstagramUser: Codable {
    let id: String
    let username: String
    let accountType: String?
    let mediaCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, username
        case accountType = "account_type"
        case mediaCount = "media_count"
    }
}

enum InstagramError: LocalizedError {
    case notAuthenticated
    case imageProcessingFailed
    case invalidURL
    case uploadFailed
    case publishFailed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Instagram"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .invalidURL:
            return "Invalid URL"
        case .uploadFailed:
            return "Failed to upload image"
        case .publishFailed:
            return "Failed to publish media"
        case .invalidResponse:
            return "Invalid response from Instagram"
        }
    }
}

// MARK: - Authentication Context Provider

class AuthenticationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}