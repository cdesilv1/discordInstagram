# discordInstagram

Description:

There are several components to this project. There is a side-loaded iOS 18 App that oauths with Instagram to post Instagram content and also pushes any images posted to an S3 bucket. There is a lambda component that then put the image URL in an SQS queue. A discord bot deployed to an EC2 instance processes the queue and posts any image URLs to a discord channel.

