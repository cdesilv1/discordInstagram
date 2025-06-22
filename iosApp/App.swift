"""
Main App entry point for Instagram to Discord iOS application.
"""

import SwiftUI

@main
struct InstagramDiscordApp: App {
    
    init() {
        // Configure app on launch
        configureApp()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Handle URL schemes (like Instagram OAuth callback)
                    handleIncomingURL(url)
                }
        }
    }
    
    private func configureApp() {
        // Any app-wide configuration can be done here
        print("Instagram to Discord app launched")
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Handle Instagram OAuth callback and other URL schemes
        print("Received URL: \(url)")
        
        if url.scheme == "instagram-discord-app" {
            // Instagram OAuth callback is handled in InstagramManager
            print("Instagram OAuth callback received")
        }
    }
}