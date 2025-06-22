# Instagram to Discord Deployment Guide

Complete deployment guide for the Instagram to Discord image syncing system.

## System Architecture

```
iOS App → Instagram API → AWS S3 → Lambda → SQS → EC2 Discord Bot → Discord Channel
```

## Prerequisites

- AWS Account with appropriate permissions
- Discord Server and Bot Token
- Instagram Developer Account
- iOS Developer Account (for side-loading)
- Domain name (optional, for custom endpoints)

## Step 1: Instagram App Setup

### 1.1 Create Instagram App

1. Go to [Facebook for Developers](https://developers.facebook.com/)
2. Create a new app and add Instagram Basic Display product
3. Configure OAuth redirect URI: `instagram-discord-app://auth`
4. Note your `App ID` and `App Secret`

### 1.2 Instagram Configuration

```bash
# Required scopes
user_profile,user_media

# Redirect URI
instagram-discord-app://auth

# Webhook URL (optional)
https://your-domain.com/instagram-webhook
```

## Step 2: Discord Bot Setup

### 2.1 Create Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create new application
3. Go to Bot section and create bot
4. Copy bot token
5. Get channel ID where images will be posted

### 2.2 Bot Permissions

Required bot permissions:
- Send Messages
- Embed Links
- Attach Files
- Use External Emojis

## Step 3: AWS Infrastructure Deployment

### 3.1 Deploy CloudFormation Stack

```bash
# Navigate to CloudFormation directory
cd awsCloudformation/

# Deploy the stack
aws cloudformation deploy \
  --template-file template.yml \
  --stack-name instagram-discord-dev \
  --parameter-overrides \
    EnvironmentName=dev \
    DiscordBotToken=YOUR_DISCORD_BOT_TOKEN \
    DiscordChannelId=YOUR_DISCORD_CHANNEL_ID \
  --capabilities CAPABILITY_NAMED_IAM
```

### 3.2 Deploy Lambda Function

```bash
# Package Lambda function
zip -r lambda-deployment.zip lambda_function.py requirements.txt

# Update Lambda function
aws lambda update-function-code \
  --function-name dev-instagram-image-processor \
  --zip-file fileb://lambda-deployment.zip
```

### 3.3 Verify Infrastructure

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name instagram-discord-dev

# Test S3 bucket
aws s3 ls s3://dev-instagram-images-YOUR_ACCOUNT_ID

# Check SQS queue
aws sqs get-queue-attributes --queue-url YOUR_QUEUE_URL --attribute-names All
```

## Step 4: EC2 Discord Bot Deployment

### 4.1 Launch EC2 Instance

```bash
# Launch EC2 instance with the created IAM role
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --iam-instance-profile Name=dev-discord-bot-instance-profile \
  --security-group-ids sg-YOUR_SECURITY_GROUP \
  --subnet-id subnet-YOUR_SUBNET \
  --user-data file://user-data.sh
```

### 4.2 Install Discord Bot

```bash
# SSH into EC2 instance
ssh -i your-key.pem ec2-user@YOUR_EC2_IP

# Clone or copy bot files
sudo yum update -y
sudo yum install -y python3 python3-pip git

# Copy bot files to instance
scp -i your-key.pem discordBot/* ec2-user@YOUR_EC2_IP:/home/ec2-user/

# Run deployment script
cd /home/ec2-user/
chmod +x deploy.sh
./deploy.sh
```

### 4.3 Configure Environment Variables

```bash
# Set environment variables for the service
sudo systemctl edit discord-instagram-bot

# Add environment variables:
[Service]
Environment=SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/ACCOUNT/dev-instagram-image-queue
Environment=ENVIRONMENT=dev
```

## Step 5: iOS App Configuration

### 5.1 Update App Configuration

Edit `iosApp/Info.plist`:
```xml
<key>INSTAGRAM_CLIENT_ID</key>
<string>YOUR_INSTAGRAM_CLIENT_ID</string>
<key>INSTAGRAM_CLIENT_SECRET</key>
<string>YOUR_INSTAGRAM_CLIENT_SECRET</string>
<key>AWS_S3_BUCKET</key>
<string>dev-instagram-images-YOUR_ACCOUNT_ID</string>
<key>AWS_ACCESS_KEY_ID</key>
<string>YOUR_AWS_ACCESS_KEY</string>
<key>AWS_SECRET_ACCESS_KEY</key>
<string>YOUR_AWS_SECRET_KEY</string>
```

### 5.2 Build and Side-load App

```bash
# Build app in Xcode
xcodebuild -project InstagramDiscord.xcodeproj -scheme InstagramDiscord -configuration Release

# Side-load using your preferred method:
# - Xcode direct installation
# - AltStore
# - Sideloadly
# - TestFlight (if you have developer account)
```

## Step 6: Testing and Verification

### 6.1 End-to-End Test

1. Open iOS app
2. Authenticate with Instagram
3. Select test images
4. Upload images
5. Verify images appear in Discord channel

### 6.2 Component Testing

```bash
# Test Lambda function
aws lambda invoke \
  --function-name dev-instagram-image-processor \
  --payload file://test-event.json \
  --output-file response.json

# Test SQS queue
aws sqs send-message \
  --queue-url YOUR_QUEUE_URL \
  --message-body '{"image_url":"test-url","object_key":"test-key"}'

# Test Discord bot logs
sudo journalctl -u discord-instagram-bot -f
```

## Step 7: Monitoring and Maintenance

### 7.1 CloudWatch Monitoring

```bash
# Lambda function metrics
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/dev-instagram

# SQS queue metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name NumberOfMessagesSent \
  --dimensions Name=QueueName,Value=dev-instagram-image-queue \
  --statistics Sum \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600
```

### 7.2 Backup and Recovery

```bash
# Backup S3 bucket
aws s3 sync s3://dev-instagram-images-YOUR_ACCOUNT_ID s3://backup-bucket/

# Export SQS messages (for debugging)
aws sqs receive-message --queue-url YOUR_QUEUE_URL --max-number-of-messages 10
```

## Security Considerations

### 7.1 AWS Security

- Use IAM roles instead of access keys where possible
- Enable S3 bucket encryption
- Use VPC endpoints for private communication
- Enable CloudTrail logging

### 7.2 Application Security

- Store secrets in AWS Systems Manager Parameter Store
- Use HTTPS for all API communications
- Implement proper error handling (don't expose sensitive info)
- Regular security updates for all components

## Troubleshooting

### Common Issues

1. **Instagram OAuth Fails**
   - Check redirect URI exactly matches
   - Verify app is not in sandbox mode
   - Check Instagram app permissions

2. **Lambda Function Errors**
   - Check CloudWatch logs: `/aws/lambda/dev-instagram-image-processor`
   - Verify IAM permissions for S3 and SQS
   - Check environment variables

3. **Discord Bot Not Posting**
   - Check EC2 instance logs: `journalctl -u discord-instagram-bot`
   - Verify bot permissions in Discord server
   - Check SQS queue for pending messages

4. **S3 Upload Failures**
   - Verify AWS credentials in iOS app
   - Check S3 bucket policies and CORS settings
   - Verify network connectivity

### Log Locations

- Lambda: CloudWatch Logs `/aws/lambda/dev-instagram-image-processor`
- Discord Bot: `journalctl -u discord-instagram-bot`
- iOS App: Xcode Console when connected
- CloudFormation: AWS Console > CloudFormation > Events

## Production Deployment

For production deployment:

1. Use separate environment (change `EnvironmentName` parameter)
2. Implement proper secrets management
3. Set up monitoring and alerting
4. Use Auto Scaling Groups for Discord bot
5. Implement blue/green deployment for updates
6. Add comprehensive error handling and retry logic

## Cost Optimization

- Use S3 Intelligent Tiering for image storage
- Implement SQS message batching
- Use spot instances for non-critical Discord bot
- Set up lifecycle policies for old images
- Monitor AWS costs with budgets and alerts