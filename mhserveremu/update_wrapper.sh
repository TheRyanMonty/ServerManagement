#!/bin/bash

#Stop the mhserveremu
echo "$(date) Stopping the marvel heroes service..."
/usr/bin/systemctl stop mhserveremu

#Start the update process
echo "$(date) Calling update script..."
/usr/bin/sudo -u mhserver /opt/mhserver/downloads/update_mhserveremu.sh

#Restart the mhserveremu service
echo "$(date) Starting marvel heroes service..."
/usr/bin/systemctl start mhserveremu

echo "$(date) Script complete"
