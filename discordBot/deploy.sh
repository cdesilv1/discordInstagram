#!/bin/bash

"""
Deployment script for Discord Instagram Bot on EC2.
This script sets up the bot as a systemd service.
"""

set -e

# Configuration
SERVICE_NAME="discord-instagram-bot"
SERVICE_USER="ec2-user"
INSTALL_DIR="/home/$SERVICE_USER/$SERVICE_NAME"
PYTHON_VERSION="python3.12"

echo "Starting deployment of Discord Instagram Bot..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root for security reasons."
   echo "Please run as the service user ($SERVICE_USER) or with sudo for specific commands."
   exit 1
fi

# Create installation directory
echo "Creating installation directory..."
sudo mkdir -p $INSTALL_DIR
sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

# Copy bot files
echo "Copying bot files..."
cp bot.py $INSTALL_DIR/
cp requirements.txt $INSTALL_DIR/
cp systemd-service.service /tmp/discord-instagram-bot.service

# Create Python virtual environment
echo "Setting up Python virtual environment..."
cd $INSTALL_DIR
$PYTHON_VERSION -m venv venv
source venv/bin/activate

# Install Python dependencies
echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Install systemd service
echo "Installing systemd service..."
sudo cp /tmp/discord-instagram-bot.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable and start service
echo "Enabling and starting service..."
sudo systemctl enable discord-instagram-bot
sudo systemctl start discord-instagram-bot

# Check service status
echo "Checking service status..."
sudo systemctl status discord-instagram-bot --no-pager

echo "Deployment completed successfully!"
echo "Use 'sudo systemctl status discord-instagram-bot' to check status"
echo "Use 'sudo journalctl -u discord-instagram-bot -f' to view logs"