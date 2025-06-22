"""
AWS Lambda function to process S3 uploads and send image URLs to SQS queue.
Triggered when images are uploaded to the Instagram images S3 bucket.
"""

import json
import boto3
import urllib.parse
import os
import logging
from typing import Dict, Any, List
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

class ImageProcessor:
    """Handles processing of uploaded Instagram images."""
    
    def __init__(self):
        """Initialize the ImageProcessor with AWS clients."""
        self.s3_client = boto3.client('s3')
        self.sqs_client = boto3.client('sqs')
        self.queue_url = os.environ.get('SQS_QUEUE_URL')
        self.environment = os.environ.get('ENVIRONMENT', 'dev')
        
        if not self.queue_url:
            raise ValueError("SQS_QUEUE_URL environment variable is required")
    
    def process_s3_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process S3 event and send image URLs to SQS queue.
        
        Args:
            event: AWS Lambda event from S3 trigger
            
        Returns:
            Response dictionary with processing results
        """
        processed_images = []
        errors = []
        
        try:
            records = event.get('Records', [])
            logger.info(f"Processing {len(records)} S3 records")
            
            for record in records:
                try:
                    # Extract S3 information
                    s3_info = record.get('s3', {})
                    bucket_name = s3_info.get('bucket', {}).get('name')
                    object_key = urllib.parse.unquote_plus(
                        s3_info.get('object', {}).get('key', ''),
                        encoding='utf-8'
                    )
                    
                    if not bucket_name or not object_key:
                        logger.warning(f"Missing bucket name or object key in record: {record}")
                        continue
                    
                    logger.info(f"Processing image: {bucket_name}/{object_key}")
                    
                    # Validate image file extension
                    if not self._is_valid_image_file(object_key):
                        logger.warning(f"Skipping non-image file: {object_key}")
                        continue
                    
                    # Get object metadata
                    object_metadata = self._get_object_metadata(bucket_name, object_key)
                    
                    # Generate image URL
                    image_url = self._generate_image_url(bucket_name, object_key)
                    
                    # Prepare message for SQS
                    message_body = self._create_sqs_message(
                        image_url, object_key, object_metadata
                    )
                    
                    # Send to SQS queue
                    self._send_to_sqs(message_body)
                    
                    processed_images.append({
                        'bucket': bucket_name,
                        'key': object_key,
                        'url': image_url
                    })
                    
                except Exception as e:
                    error_msg = f"Error processing record {record}: {str(e)}"
                    logger.error(error_msg)
                    errors.append(error_msg)
                    
        except Exception as e:
            error_msg = f"Error processing S3 event: {str(e)}"
            logger.error(error_msg)
            errors.append(error_msg)
        
        # Prepare response
        response = {
            'statusCode': 200 if not errors else 207,  # 207 for partial success
            'processed_count': len(processed_images),
            'error_count': len(errors),
            'processed_images': processed_images
        }
        
        if errors:
            response['errors'] = errors
            
        logger.info(f"Processing complete: {response}")
        return response
    
    def _is_valid_image_file(self, object_key: str) -> bool:
        """
        Check if the file is a valid image based on extension.
        
        Args:
            object_key: S3 object key
            
        Returns:
            True if valid image file, False otherwise
        """
        valid_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'}
        file_extension = os.path.splitext(object_key.lower())[1]
        return file_extension in valid_extensions
    
    def _get_object_metadata(self, bucket_name: str, object_key: str) -> Dict[str, Any]:
        """
        Get S3 object metadata.
        
        Args:
            bucket_name: S3 bucket name
            object_key: S3 object key
            
        Returns:
            Object metadata dictionary
        """
        try:
            response = self.s3_client.head_object(Bucket=bucket_name, Key=object_key)
            return {
                'size': response.get('ContentLength', 0),
                'last_modified': response.get('LastModified', '').isoformat() if response.get('LastModified') else '',
                'content_type': response.get('ContentType', ''),
                'etag': response.get('ETag', '').strip('"'),
                'metadata': response.get('Metadata', {})
            }
        except Exception as e:
            logger.warning(f"Could not get metadata for {bucket_name}/{object_key}: {e}")
            return {}
    
    def _generate_image_url(self, bucket_name: str, object_key: str) -> str:
        """
        Generate a pre-signed URL for the image.
        
        Args:
            bucket_name: S3 bucket name
            object_key: S3 object key
            
        Returns:
            Pre-signed URL for the image
        """
        try:
            # Generate pre-signed URL valid for 24 hours
            url = self.s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': bucket_name, 'Key': object_key},
                ExpiresIn=86400  # 24 hours
            )
            return url
        except Exception as e:
            logger.error(f"Error generating pre-signed URL: {e}")
            # Fallback to public URL format (if bucket allows public access)
            return f"https://{bucket_name}.s3.amazonaws.com/{urllib.parse.quote(object_key)}"
    
    def _create_sqs_message(self, image_url: str, object_key: str, metadata: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create SQS message body for Discord bot processing.
        
        Args:
            image_url: URL of the image
            object_key: S3 object key
            metadata: Object metadata
            
        Returns:
            Message body dictionary
        """
        return {
            'image_url': image_url,
            'object_key': object_key,
            'timestamp': datetime.utcnow().isoformat(),
            'environment': self.environment,
            'metadata': metadata
        }
    
    def _send_to_sqs(self, message_body: Dict[str, Any]) -> str:
        """
        Send message to SQS queue.
        
        Args:
            message_body: Message body to send
            
        Returns:
            SQS message ID
        """
        try:
            response = self.sqs_client.send_message(
                QueueUrl=self.queue_url,
                MessageBody=json.dumps(message_body),
                MessageAttributes={
                    'Environment': {
                        'StringValue': self.environment,
                        'DataType': 'String'
                    },
                    'MessageType': {
                        'StringValue': 'InstagramImageUpload',
                        'DataType': 'String'
                    }
                }
            )
            
            message_id = response.get('MessageId')
            logger.info(f"Sent message to SQS: {message_id}")
            return message_id
            
        except Exception as e:
            logger.error(f"Error sending message to SQS: {e}")
            raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function.
    
    Args:
        event: AWS Lambda event
        context: AWS Lambda context
        
    Returns:
        Response dictionary
    """
    logger.info(f"Lambda invoked with event: {json.dumps(event, default=str)}")
    
    try:
        processor = ImageProcessor()
        return processor.process_s3_event(event)
        
    except Exception as e:
        error_msg = f"Lambda execution failed: {str(e)}"
        logger.error(error_msg)
        
        return {
            'statusCode': 500,
            'error': error_msg
        }