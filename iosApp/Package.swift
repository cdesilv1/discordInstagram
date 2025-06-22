// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InstagramDiscordApp",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "InstagramDiscordApp",
            targets: ["InstagramDiscordApp"]),
    ],
    dependencies: [
        // AWS SDK for iOS
        .package(
            url: "https://github.com/aws-amplify/aws-sdk-ios.git",
            from: "2.33.0"
        ),
        // For JSON parsing and networking if needed
        .package(
            url: "https://github.com/Alamofire/Alamofire.git",
            from: "5.8.0"
        )
    ],
    targets: [
        .target(
            name: "InstagramDiscordApp",
            dependencies: [
                .product(name: "AWSS3", package: "aws-sdk-ios"),
                .product(name: "AWSCore", package: "aws-sdk-ios"),
                "Alamofire"
            ]
        ),
        .testTarget(
            name: "InstagramDiscordAppTests",
            dependencies: ["InstagramDiscordApp"]
        ),
    ]
)