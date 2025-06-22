"""
Discord bot that processes SQS queue messages and posts Instagram images to Discord channels.
Designed to run on an EC2 instance with appropriate IAM roles.
"""

import asyncio
import json
import logging
import os
import signal
import sys
from typing import Dict, Any, Optional
from datetime import datetime
import aiohttp
import boto3
import discord
from discord.ext import tasks


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DiscordInstagramBot:
    """Discord bot for posting Instagram images from SQS queue."""
    
    def __init__(self):
        """Initialize the Discord bot with required configurations."""
        self.bot_token = self._get_discord_token()
        self.channel_id = self._get_channel_id()
        self.sqs_queue_url = self._get_sqs_queue_url()
        self.environment = os.environ.get('ENVIRONMENT', 'dev')
        
        # Initialize AWS clients
        self.sqs_client = boto3.client('sqs')
        
        # Initialize Discord client
        intents = discord.Intents.default()
        intents.message_content = True
        self.discord_client = discord.Client(intents=intents)
        
        # Setup event handlers
        self._setup_discord_events()
        
        # Control flags
        self.running = True
        self.processing_active = False
        
        logger.info("Discord Instagram Bot initialized")
    
    def _get_discord_token(self) -> str:
        """Get Discord bot token from environment or SSM Parameter Store."""
        token = os.environ.get('DISCORD_BOT_TOKEN')
        if token:
            return token
        
        # Try to get from SSM Parameter Store
        try:
            ssm_client = boto3.client('ssm')
            environment = os.environ.get('ENVIRONMENT', 'dev')
            parameter_name = f'/{environment}/discord/bot-token'
            
            response = ssm_client.get_parameter(
                Name=parameter_name,
                WithDecryption=True
            )
            return response['Parameter']['Value']
            
        except Exception as e:
            logger.error(f"Could not retrieve Discord token: {e}")
            raise ValueError("Discord bot token not found in environment or SSM")
    
    def _get_channel_id(self) -> int:
        """Get Discord channel ID from environment or SSM Parameter Store."""
        channel_id = os.environ.get('DISCORD_CHANNEL_ID')
        if channel_id:
            return int(channel_id)
        
        # Try to get from SSM Parameter Store
        try:
            ssm_client = boto3.client('ssm')
            environment = os.environ.get('ENVIRONMENT', 'dev')
            parameter_name = f'/{environment}/discord/channel-id'
            
            response = ssm_client.get_parameter(Name=parameter_name)
            return int(response['Parameter']['Value'])
            
        except Exception as e:
            logger.error(f"Could not retrieve Discord channel ID: {e}")
            raise ValueError("Discord channel ID not found in environment or SSM")
    
    def _get_sqs_queue_url(self) -> str:
        """Get SQS queue URL from environment."""
        queue_url = os.environ.get('SQS_QUEUE_URL')
        if not queue_url:
            raise ValueError("SQS_QUEUE_URL environment variable is required")
        return queue_url
    
    def _setup_discord_events(self):
        """Setup Discord client event handlers."""
        
        @self.discord_client.event
        async def on_ready():
            """Handle Discord client ready event."""
            logger.info(f'Discord bot logged in as {self.discord_client.user}')
            
            # Verify channel access
            channel = self.discord_client.get_channel(self.channel_id)
            if not channel:
                logger.error(f"Could not access Discord channel {self.channel_id}")
                await self.shutdown()
                return
            
            logger.info(f'Connected to Discord channel: {channel.name}')
            
            # Start SQS processing task
            if not self.process_sqs_messages.is_running():
                self.process_sqs_messages.start()
        
        @self.discord_client.event
        async def on_error(event, *args, **kwargs):
            """Handle Discord client errors."""
            logger.error(f'Discord error in {event}: {args}, {kwargs}')
    
    @tasks.loop(seconds=10)
    async def process_sqs_messages(self):
        """Process messages from SQS queue and post to Discord."""
        if not self.running or self.processing_active:
            return
        
        self.processing_active = True
        
        try:
            # Receive messages from SQS
            response = self.sqs_client.receive_message(
                QueueUrl=self.sqs_queue_url,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=5,  # Long polling
                MessageAttributeNames=['All']
            )
            
            messages = response.get('Messages', [])
            if not messages:
                self.processing_active = False
                return
            
            logger.info(f"Processing {len(messages)} SQS messages")
            
            for message in messages:
                try:
                    await self._process_single_message(message)
                    
                    # Delete message from queue after successful processing
                    self.sqs_client.delete_message(
                        QueueUrl=self.sqs_queue_url,
                        ReceiptHandle=message['ReceiptHandle']
                    )
                    
                except Exception as e:
                    logger.error(f"Error processing message {message.get('MessageId', 'unknown')}: {e}")
                    # Message will remain in queue and be retried or sent to DLQ
                    
        except Exception as e:
            logger.error(f"Error processing SQS messages: {e}")
        
        finally:
            self.processing_active = False
    
    async def _process_single_message(self, message: Dict[str, Any]):
        """
        Process a single SQS message and post image to Discord.
        
        Args:
            message: SQS message dictionary
        """
        try:
            # Parse message body
            message_body = json.loads(message['Body'])
            
            image_url = message_body.get('image_url')
            object_key = message_body.get('object_key', 'unknown')
            timestamp = message_body.get('timestamp', '')
            metadata = message_body.get('metadata', {})
            
            if not image_url:
                logger.warning(f"No image URL in message: {message_body}")
                return
            
            logger.info(f"Processing image: {object_key}")
            
            # Get Discord channel
            channel = self.discord_client.get_channel(self.channel_id)
            if not channel:
                raise ValueError(f"Could not access Discord channel {self.channel_id}")
            
            # Create Discord embed
            embed = await self._create_discord_embed(
                image_url, object_key, timestamp, metadata
            )
            
            # Post to Discord
            await channel.send(embed=embed)
            logger.info(f"Posted image to Discord: {object_key}")
            
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in message body: {e}")
            raise
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            raise
    
    async def _create_discord_embed(
        self, 
        image_url: str, 
        object_key: str, 
        timestamp: str, 
        metadata: Dict[str, Any]
    ) -> discord.Embed:
        """
        Create Discord embed for Instagram image.
        
        Args:
            image_url: URL of the image
            object_key: S3 object key
            timestamp: Upload timestamp
            metadata: Image metadata
            
        Returns:
            Discord embed object
        """
        # Create embed
        embed = discord.Embed(
            title="📸 New Instagram Post",
            description=f"Image uploaded from Instagram",
            color=0xE4405F,  # Instagram brand color
            timestamp=datetime.fromisoformat(timestamp.replace('Z', '+00:00')) if timestamp else datetime.utcnow()
        )
        
        # Set image
        embed.set_image(url=image_url)
        
        # Add fields with metadata
        if metadata.get('size'):
            file_size = self._format_file_size(metadata['size'])
            embed.add_field(name="File Size", value=file_size, inline=True)
        
        if metadata.get('content_type'):
            embed.add_field(name="Type", value=metadata['content_type'], inline=True)
        
        # Add filename
        filename = object_key.split('/')[-1] if '/' in object_key else object_key
        embed.add_field(name="Filename", value=filename, inline=True)
        
        # Footer
        embed.set_footer(
            text=f"Environment: {self.environment}",
            icon_url="https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/instagram.png"
        )
        
        return embed
    
    def _format_file_size(self, size_bytes: int) -> str:
        """
        Format file size in human readable format.
        
        Args:
            size_bytes: Size in bytes
            
        Returns:
            Formatted size string
        """
        if size_bytes < 1024:
            return f"{size_bytes} B"
        elif size_bytes < 1024**2:
            return f"{size_bytes / 1024:.1f} KB"
        elif size_bytes < 1024**3:
            return f"{size_bytes / (1024**2):.1f} MB"
        else:
            return f"{size_bytes / (1024**3):.1f} GB"
    
    async def start(self):
        """Start the Discord bot."""
        logger.info("Starting Discord Instagram Bot...")
        
        try:
            await self.discord_client.start(self.bot_token)
        except Exception as e:
            logger.error(f"Failed to start Discord bot: {e}")
            raise
    
    async def shutdown(self):
        """Gracefully shutdown the bot."""
        logger.info("Shutting down Discord Instagram Bot...")
        
        self.running = False
        
        # Stop background tasks
        if self.process_sqs_messages.is_running():
            self.process_sqs_messages.cancel()
        
        # Close Discord client
        if not self.discord_client.is_closed():
            await self.discord_client.close()
        
        logger.info("Discord Instagram Bot stopped")


class BotManager:
    """Manager for the Discord bot with signal handling."""
    
    def __init__(self):
        self.bot = DiscordInstagramBot()
        self.setup_signal_handlers()
    
    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown."""
        def signal_handler(signum, frame):
            logger.info(f"Received signal {signum}, initiating shutdown...")
            asyncio.create_task(self.bot.shutdown())
            sys.exit(0)
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    async def run(self):
        """Run the bot manager."""
        try:
            await self.bot.start()
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received")
        except Exception as e:
            logger.error(f"Bot manager error: {e}")
        finally:
            await self.bot.shutdown()


async def main():
    """Main entry point."""
    logger.info("Initializing Discord Instagram Bot Manager...")
    
    manager = BotManager()
    await manager.run()


if __name__ == "__main__":
    asyncio.run(main())