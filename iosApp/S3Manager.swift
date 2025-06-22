"""
S3Manager for uploading images to AWS S3 bucket.
Images uploaded here trigger the Lambda function that processes them for Discord.
"""

import Foundation
import UIKit
import AWSS3

@MainActor
class S3Manager: ObservableObject {
    @Published var uploadProgress: Double = 0.0
    @Published var isUploading = false
    
    private let bucketName: String
    private let region: String
    private let accessKeyId: String
    private let secretAccessKey: String
    
    private var s3Client: AWSS3?
    
    init() {
        // Get AWS configuration from Info.plist or environment
        self.bucketName = Bundle.main.object(forInfoDictionaryKey: "AWS_S3_BUCKET") as? String ?? ""
        self.region = Bundle.main.object(forInfoDictionaryKey: "AWS_REGION") as? String ?? "us-east-1"
        self.accessKeyId = Bundle.main.object(forInfoDictionaryKey: "AWS_ACCESS_KEY_ID") as? String ?? ""
        self.secretAccessKey = Bundle.main.object(forInfoDictionaryKey: "AWS_SECRET_ACCESS_KEY") as? String ?? ""
        
        setupAWSConfiguration()
    }
    
    private func setupAWSConfiguration() {
        // Configure AWS credentials
        let credentialsProvider = AWSStaticCredentialsProvider(
            accessKey: accessKeyId,
            secretKey: secretAccessKey
        )
        
        let configuration = AWSServiceConfiguration(
            region: AWSRegionType(rawValue: region) ?? .USEast1,
            credentialsProvider: credentialsProvider
        )
        
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        s3Client = AWSS3.default()
    }
    
    // MARK: - Image Upload
    
    func uploadImages(_ images: [UIImage]) async throws -> [S3UploadResult] {
        guard !images.isEmpty else {
            throw S3Error.noImages
        }
        
        guard !bucketName.isEmpty else {
            throw S3Error.missingConfiguration
        }
        
        isUploading = true
        uploadProgress = 0.0
        
        var results: [S3UploadResult] = []
        let totalImages = Double(images.count)
        
        for (index, image) in images.enumerated() {
            do {
                let result = try await uploadSingleImage(image, index: index)
                results.append(result)
                
                // Update progress
                uploadProgress = Double(index + 1) / totalImages
                
            } catch {
                print("Error uploading image \(index): \(error)")
                throw error
            }
        }
        
        isUploading = false
        uploadProgress = 1.0
        
        return results
    }
    
    private func uploadSingleImage(_ image: UIImage, index: Int) async throws -> S3UploadResult {
        // Convert image to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw S3Error.imageProcessingFailed
        }
        
        // Generate unique filename
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "instagram-images/\(timestamp)-\(index).jpg"
        
        // Create upload request
        let uploadRequest = AWSS3PutObjectRequest()
        uploadRequest?.bucket = bucketName
        uploadRequest?.key = fileName
        uploadRequest?.body = imageData
        uploadRequest?.contentType = "image/jpeg"
        
        // Add metadata
        uploadRequest?.metadata = [
            "source": "instagram-ios-app",
            "upload-timestamp": String(timestamp),
            "image-index": String(index)
        ]
        
        // Set server-side encryption
        uploadRequest?.serverSideEncryption = .aes256
        
        guard let request = uploadRequest, let s3 = s3Client else {
            throw S3Error.invalidRequest
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            s3.putObject(request) { result, error in
                if let error = error {
                    continuation.resume(throwing: S3Error.uploadFailed(error.localizedDescription))
                } else if let result = result {
                    let uploadResult = S3UploadResult(
                        fileName: fileName,
                        bucketName: self.bucketName,
                        etag: result.eTag ?? "",
                        size: imageData.count,
                        uploadedAt: Date()
                    )
                    continuation.resume(returning: uploadResult)
                } else {
                    continuation.resume(throwing: S3Error.unknownError)
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    func generatePreSignedURL(for fileName: String, expirationTime: TimeInterval = 3600) async -> String? {
        let getPreSignedURLRequest = AWSS3GetPreSignedURLRequest()
        getPreSignedURLRequest?.bucket = bucketName
        getPreSignedURLRequest?.key = fileName
        getPreSignedURLRequest?.httpMethod = .GET
        getPreSignedURLRequest?.expires = Date(timeIntervalSinceNow: expirationTime)
        
        guard let request = getPreSignedURLRequest, let s3 = s3Client else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            s3.getPreSignedURL(request) { url, error in
                if let url = url {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    func deleteImage(fileName: String) async throws {
        let deleteRequest = AWSS3DeleteObjectRequest()
        deleteRequest?.bucket = bucketName
        deleteRequest?.key = fileName
        
        guard let request = deleteRequest, let s3 = s3Client else {
            throw S3Error.invalidRequest
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            s3.deleteObject(request) { result, error in
                if let error = error {
                    continuation.resume(throwing: S3Error.deleteFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func listUploadedImages(limit: Int = 100) async throws -> [String] {
        let listRequest = AWSS3ListObjectsV2Request()
        listRequest?.bucket = bucketName
        listRequest?.prefix = "instagram-images/"
        listRequest?.maxKeys = NSNumber(value: limit)
        
        guard let request = listRequest, let s3 = s3Client else {
            throw S3Error.invalidRequest
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            s3.listObjectsV2(request) { result, error in
                if let error = error {
                    continuation.resume(throwing: S3Error.listFailed(error.localizedDescription))
                } else if let result = result {
                    let fileNames = result.contents?.compactMap { $0.key } ?? []
                    continuation.resume(returning: fileNames)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

// MARK: - Models

struct S3UploadResult {
    let fileName: String
    let bucketName: String
    let etag: String
    let size: Int
    let uploadedAt: Date
    
    var url: String {
        return "https://\(bucketName).s3.amazonaws.com/\(fileName)"
    }
}

enum S3Error: LocalizedError {
    case noImages
    case missingConfiguration
    case imageProcessingFailed
    case invalidRequest
    case uploadFailed(String)
    case deleteFailed(String)
    case listFailed(String)
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .noImages:
            return "No images to upload"
        case .missingConfiguration:
            return "AWS S3 configuration is missing"
        case .imageProcessingFailed:
            return "Failed to process image data"
        case .invalidRequest:
            return "Invalid S3 request"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .deleteFailed(let message):
            return "Delete failed: \(message)"
        case .listFailed(let message):
            return "List operation failed: \(message)"
        case .unknownError:
            return "Unknown S3 error occurred"
        }
    }
}