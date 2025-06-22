# Instagram to Discord iOS App

A side-loaded iOS 18 app that connects to Instagram and automatically syncs posted images to Discord via AWS infrastructure.

## Features

- **Instagram OAuth Authentication**: Secure login with Instagram using OAuth 2.0
- **Image Selection**: Pick multiple images from photo library
- **Instagram Posting**: Post images directly to Instagram
- **AWS S3 Integration**: Automatically upload images to S3 bucket
- **Discord Integration**: Images are processed by Lambda and posted to Discord

## Architecture

```
iOS App → Instagram API (Post) → AWS S3 (Upload) → Lambda (Process) → SQS → EC2 Discord Bot → Discord
```

## Setup Instructions

### 1. Instagram App Configuration

1. Create an Instagram App at [Facebook for Developers](https://developers.facebook.com/)
2. Configure OAuth redirect URI: `instagram-discord-app://auth`
3. Get your `Client ID` and `Client Secret`

### 2. AWS Configuration

1. Deploy the CloudFormation template from `../awsCloudformation/`
2. Note the S3 bucket name and other resources created
3. Create IAM user with S3 upload permissions for mobile app

### 3. iOS App Configuration

1. Update `Info.plist` with your actual values:
   ```xml
   <key>INSTAGRAM_CLIENT_ID</key>
   <string>YOUR_ACTUAL_INSTAGRAM_CLIENT_ID</string>
   <key>INSTAGRAM_CLIENT_SECRET</key>
   <string>YOUR_ACTUAL_INSTAGRAM_CLIENT_SECRET</string>
   <key>AWS_S3_BUCKET</key>
   <string>YOUR_S3_BUCKET_NAME</string>
   <key>AWS_ACCESS_KEY_ID</key>
   <string>YOUR_AWS_ACCESS_KEY</string>
   <key>AWS_SECRET_ACCESS_KEY</key>
   <string>YOUR_AWS_SECRET_KEY</string>
   ```

### 4. Dependencies

The app uses Swift Package Manager. Dependencies are defined in `Package.swift`:
- AWS SDK for iOS (S3 operations)
- Alamofire (HTTP networking)

### 5. Side-loading

Since this app requires Instagram API access and custom OAuth, it needs to be side-loaded:

1. Use Xcode to build and install on your device
2. Or use tools like AltStore, Sideloadly, or similar
3. Ensure your Apple Developer account allows app installation

## Usage

1. **Launch the app** and tap "Connect Instagram"
2. **Authenticate** with your Instagram account
3. **Select images** from your photo library
4. **Tap "Upload"** to post to Instagram and sync to Discord
5. **Monitor progress** through the app's status updates

## Security Notes

- Keep your Instagram Client Secret secure
- Use IAM roles with minimal required permissions
- Consider using AWS Cognito for more secure mobile authentication
- Images are encrypted in transit and at rest in S3

## File Structure

```
iosApp/
├── App.swift                 # Main app entry point
├── ContentView.swift         # Main UI view
├── InstagramManager.swift    # Instagram OAuth and API
├── S3Manager.swift          # AWS S3 upload functionality
├── Info.plist              # App configuration
├── Package.swift           # Swift dependencies
└── README.md              # This file
```

## Troubleshooting

### Instagram Authentication Issues
- Verify Client ID and Secret are correct
- Check redirect URI matches exactly
- Ensure Instagram app is not in sandbox mode for production

### AWS Upload Issues
- Verify S3 bucket exists and is accessible
- Check IAM permissions for S3 operations
- Confirm AWS credentials are valid

### App Installation Issues
- Ensure device allows installation of unsigned apps
- Check Apple Developer account status
- Verify app signing certificate

## Development

To modify the app:

1. Open in Xcode
2. Update dependencies if needed: `swift package update`
3. Test Instagram OAuth in simulator or device
4. Test S3 upload functionality
5. Build and side-load for testing

## Production Considerations

- Use environment-specific configuration
- Implement proper error handling and retry logic
- Add analytics and crash reporting
- Consider app store distribution (requires Instagram partnership)
- Implement proper secrets management (AWS Secrets Manager)