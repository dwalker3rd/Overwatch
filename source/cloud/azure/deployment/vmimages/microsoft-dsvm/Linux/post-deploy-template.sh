#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

PD_SOURCE_REPO=${passed_values[0]} 
PD_STORAGE_ACCOUNT_NAME=${passed_values[1]}
PD_SAS_TOKEN=${passed_values[2]}
PD_CONTAINER_NAME=${passed_values[3]} 
PD_VM_FQDN="${passed_values[4]}"
PD_INITIAL_USER_UPN="${passed_values[5]}"
PD_INITIAL_JHUB_USER_NAME="${passed_values[6]}"
PD_CLIENT_ID=${passed_values[7]} 
PD_CLIENT_SECRET=${passed_values[8]}
PD_TENANT_ID=${passed_values[9]}
PD_SKIP_CERT=${passed_values[10]}

rm logs.txt

echo '*************************************************' >> logs.txt
echo 'This are the variables passed in to the script:' >> logs.txt
echo ''  >> logs.txt >> logs.txt
echo "PD_SOURCE_REPO:               ${PD_SOURCE_REPO}" >> logs.txt
echo "PD_STORAGE_ACCOUNT_NAME:      ${PD_STORAGE_ACCOUNT_NAME}" >> logs.txt
echo "PD_SAS_TOKEN:                 ${PD_SAS_TOKEN}" >> logs.txt
echo "PD_CONTAINER_NAME:            ${PD_CONTAINER_NAME}" >> logs.txt
echo "PD_VM_FQDN:                   ${PD_VM_FQDN}" >> logs.txt
echo "PD_INITIAL_USER_UPN:          ${PD_INITIAL_USER_UPN}" >> logs.txt
echo "PD_INITIAL_JHUB_USER_NAME:    ${PD_INITIAL_JHUB_USER_NAME}" >> logs.txt
echo "PD_CLIENT_ID:                 ${PD_CLIENT_ID}" >> logs.txt
echo "PD_CLIENT_SECRET:             ${PD_CLIENT_SECRET}" >> logs.txt
echo "PD_TENANT_ID:                 ${PD_TENANT_ID}" >> logs.txt
echo "PD_SKIP_CERT:                 ${PD_SKIP_CERT}" >> logs.txt
echo ''  >> logs.txt >> logs.txt
echo 'This script is being run from: '>> logs.txt
echo $pwd>> logs.txt
echo ''  >> logs.txt >> logs.txt
echo '*************************************************' >> logs.txt



# Fix expired GPG key for tensorflow and R
echo 'Fixing expired GPG key for tensorflow and R...' >> logs.txt
curl https://storage.googleapis.com/tensorflow-serving-apt/tensorflow-serving.release.pub.gpg | sudo apt-key add -
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9
echo 'Done'  >> logs.txt
echo ''  >> logs.txt


# Update package indexes
echo 'Updating package indexes...' >> logs.txt
sudo apt-get update
# Ensure intallation tools are installed
sudo apt-get install jq -y
sudo apt-get install zip unzip -y
sudo apt-get install curl -y
sudo apt install dos2unix -y
# Ensure git is installed
sudo apt-get install git -y
echo 'Done'  >> logs.txt
echo ''  >> logs.txt


# Update OS security packages
echo 'Updating OS security packages...' >> logs.txt
# Update package indexes
sudo apt-get update
echo 'Done'  >> logs.txt
echo ''  >> logs.txt


# Create vmusers group (use for setting permissions for applicable users)
echo 'Creating vmusers group...' >> logs.txt
sudo addgroup vmusers --gid 4000
echo "%vmusers  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
echo 'Done'  >> logs.txt
echo ''  >> logs.txt


# Mount data disk (https://docs.microsoft.com/en-us/azure/virtual-machines/linux/attach-disk-portal) ###
echo 'Mounting data disk...' >> logs.txt
disk_to_format=$(lsblk --fs --json | jq -r '.blockdevices[] | select(.children == null and .fstype == null) | .name' | grep "sd")

echo 'Creating partition /datadrive...' >> logs.txt
sudo mkdir -p /datadrive
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

if [ -z "$disk_to_format" ]; then

    # Mount DataDrive
    disk_to_mount=$(lsblk --json | jq -r '.blockdevices[] | select(.children != null and .children[0].mountpoint == null and .children[0].type=="part") | .name' | grep "sd")
    UUID_MOUNT=$(blkid -o value -s UUID /dev/${disk_to_mount}1)

    if [ -z "$(grep $UUID_MOUNT\ /datadrive /etc/fstab)" ]; then
        echo 'Mounting /datadrive...' >> logs.txt
        sudo echo "UUID=$(blkid -o value -s UUID /dev/${disk_to_mount}1) /datadrive   ext4   defaults,nofail   1   2"  >> /etc/fstab
    else
        echo "/etc/fstab was not modified. ${disk_to_mount}1 is already in fstab"
    fi
    
    sudo mount -a
    echo 'Done'  >> logs.txt
    echo ''  >> logs.txt
else
    echo 'Formatting disk...' >> logs.txt
    sudo parted --script /dev/$disk_to_format mklabel gpt mkpart primary ext4 0% 100%

    # Wait until format disk is done ###
    sleep 5
    
    sudo mkfs.ext4 /dev/${disk_to_format}1

    sudo partprobe /dev/${disk_to_format}1
    
    sudo lsblk -o NAME,HCTL,SIZE,MOUNTPOINT | grep -i "sd"
    
    echo 'Mounting /datadrive...' >> logs.txt
    sudo mount /dev/${disk_to_format}1 /datadrive
    
    sudo echo "UUID=$(blkid -o value -s UUID /dev/${disk_to_format}1) /datadrive   ext4   defaults,nofail   1   2"  >> /etc/fstab
    echo 'Done'  >> logs.txt
    echo ''  >> logs.txt
fi

# Create blobfuse mount point and set permissions
echo 'Creating blobfuse mount point and setting permissions...' >> logs.txt
sudo mkdir /datadrive/blobfusemnt
sudo mkdir -p /data/blobfuse
sudo chown root:vmusers /datadrive/blobfusemnt
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

echo 'Downloading post-deploy files in ~/post-deploy...' >> logs.txt
sudo mkdir -p ~/post-deploy
cd ~/post-deploy

sudo curl -o config.zip "$PD_SOURCE_REPO"
echo 'Done'  >> logs.txt
echo ''  >> logs.txt
echo 'Unzipping post-deploy files...' >> logs.txt
sudo unzip -u config.zip -d multi-user-process-jhub
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

# Copy files to destination locations
echo 'Copying files to destination locations...' >> logs.txt
sudo cp -Rv ~/post-deploy/multi-user-process-jhub/configuration-files/etc/* /etc
sudo cp -Rv ~/post-deploy/multi-user-process-jhub/configuration-files/lib/* /lib
sudo cp -Rv ~/post-deploy/multi-user-process-jhub/configuration-files/usr/* /usr
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

# Update configuration files
echo 'Updating configuration files...' >> logs.txt
sudo sed -i "s/{storage_account_name}/"$PD_STORAGE_ACCOUNT_NAME"/g" /etc/blobfuse/configuration.cfg
sudo sed -i "s {SAS_token} "$PD_SAS_TOKEN" g" /etc/blobfuse/configuration.cfg
sudo sed -i "s/{container_name}/"$PD_CONTAINER_NAME"/g" /etc/blobfuse/configuration.cfg

sudo sed -i "s/{vm_fqdn}/"$PD_VM_FQDN"/g" /etc/jupyterhub/jupyterhub_config.py
sudo sed -i "s/{client_id}/"$PD_CLIENT_ID"/g" /etc/jupyterhub/jupyterhub_config.py
sudo sed -i "s {client_secret} "$PD_CLIENT_SECRET" g" /etc/jupyterhub/jupyterhub_config.py
sudo sed -i "s/{initialJHubUserName}/"$PD_INITIAL_JHUB_USER_NAME"/g" /etc/jupyterhub/jupyterhub_config.py

sudo sed -i "s/{tenant_id}/"$PD_TENANT_ID"/g" /lib/systemd/system/jupyterhub.service
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

# update scripts and permissions
echo 'Updating scripts and permissions...' >> logs.txt
sudo sed -i "s/{vm_fqdn}/"$PD_VM_FQDN"/g" /usr/bin/revoke-cert.sh
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

# Check files unix format and permissions
echo 'Checking files unix format and permissions...' >> logs.txt
sudo dos2unix /etc/blobfuse/configuration.cfg
sudo chown root:root /etc/blobfuse/configuration.cfg
sudo chmod 600 /etc/blobfuse/configuration.cfg

sudo chown root:root /etc/jupyterhub/jupyterhub_config.py
sudo chmod 600 /etc/jupyterhub/jupyterhub_config.py
sudo chown root:root /lib/systemd/system/jupyterhub.service
sudo chmod 600 /lib/systemd/system/jupyterhub.service

sudo chown root:root /usr/bin/revoke-cert.sh
sudo chmod 600 /usr/bin/revoke-cert.sh

sudo chown root:root /usr/bin/blobfuse-mount.sh
sudo chmod 700 /usr/bin/blobfuse-mount.sh
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

# Install oauthenticator
echo 'Installing oauthenticator...' >> logs.txt
sudo /anaconda/bin/pip install oauthenticator==0.12.0
sudo /anaconda/bin/pip install pyjwt==1.7.1
sudo /anaconda/bin/pip install pycurl==7.45.1
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

# Mount storage
echo 'Mounting storage...' >> logs.txt
sudo sh /usr/bin/blobfuse-mount.sh /data/blobfuse fuse _netdev
echo 'Done'  >> logs.txt
echo ''  >> logs.txt

# Backup fstab
echo 'Backing up fstab...' >> logs.txt
if [ -f "/etc/fstab.bak" ]; then
    sudo cp /etc/fstab.bak /etc/fstab
else
    sudo cp /etc/fstab /etc/fstab.bak
    sudo echo "/usr/bin/blobfuse-mount.sh /data/blobfuse fuse _netdev" >>/etc/fstab
fi

if [ -f "/etc/rc.local.bak" ]; then
    sudo cp /etc/rc.local.bak /etc/rc.local
else
    sudo echo 'sh /usr/bin/blobfuse-mount.sh /data/blobfuse fuse _netdev' >> /etc/rc.local
fi
echo 'Done'  >> logs.txt >> logs.txt
echo ''  >> logs.txt >> logs.txt


# Install certbot
echo 'Installing certbot...' >> logs.txt
if [ "$PD_SKIP_CERT" = "TRUE" ]; then
    echo "Skipped acquiring Let's Encrypt SSL certificate via certbot."

    # Generate ssl certificate (currently self-signed)
    sudo mkdir -p /etc/letsencrypt/live/$PD_VM_FQDN
    sudo openssl req -x509 -newkey rsa:4096 -subj "/C=US/ST=Washington/L=Redmond/O=Microsoft/OU=MS/CN=$PD_VM_FQDN" -nodes -keyout /etc/letsencrypt/live/$PD_VM_FQDN/privkey.pem -out /etc/letsencrypt/live/$PD_VM_FQDN/fullchain.pem -days 365
else
    sudo apt-get install software-properties-common -y
    sudo add-apt-repository universe -y
    sudo add-apt-repository ppa:certbot/certbot -y
    sudo apt-get update -y
    sudo apt-get install certbot -y

    sleep 120
    # Request certificate
    sudo certbot certonly --standalone --non-interactive --agree-tos --domains $PD_VM_FQDN --email $PD_INITIAL_USER_UPN
fi
echo 'Done'  >> logs.txt > logs.txt
echo ''  >> logs.txt >> logs.txt
# Set a cron job that runs security updates without restarting, on a 15 day basis 
(crontab -l 2>/dev/null; echo "0 5 */15 * * sudo unattended-upgrade -d") | crontab -

# Set a cron job that requests a new certificate, every 360 days. 
(crontab -l 2>/dev/null; echo "0 5 */360 * * sudo certbot renew --force-renewal -d") | crontab -

# Remove the old database if any and run the update databse command:
sudo rm -f /etc/jupyterhub/jupyterhub.sqlite
sudo /anaconda/bin/jupyterhub upgrade-db

# Reload systemd and restart Jupyterhub
sudo systemctl restart jupyterhub
sudo systemctl daemon-reload