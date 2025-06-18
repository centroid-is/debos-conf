#!/bin/bash -x
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Check for required environment variables
if [ -z "${ROOT_PWD:-}" ] || [ -z "${CENTROID_PWD:-}" ]; then
    echo "Error: ROOT_PWD and CENTROID_PWD environment variables must be set"
    exit 1
fi

# Create a 4G empty file
echo "Creating empty image file..."
dd if=/dev/zero of=usb-installer.img bs=1M count=4096

# Create GPT partition table
echo "Creating GPT partition table..."
parted usb-installer.img mklabel gpt

# Create EFI System Partition (ESP) and root partition
echo "Creating partitions..."
parted usb-installer.img mkpart ESP fat32 1MiB 512MiB
parted usb-installer.img mkpart primary ext4 512MiB 100%
parted usb-installer.img set 1 esp on

# Get the loop device
echo "Setting up loop device..."
LOOP=$(losetup -f --show usb-installer.img)

# Wait for the loop device to be available
echo "Waiting for partition table to be recognized..."
sleep 1
partprobe $LOOP

# Create filesystems
echo "Creating filesystems..."
mkfs.fat -F32 ${LOOP}p1
mkfs.ext4 ${LOOP}p2

# Mount it
echo "Mounting image..."
mkdir -p /tmp/usb-mount
mount ${LOOP}p2 /tmp/usb-mount
mkdir -p /tmp/usb-mount/boot
mount ${LOOP}p1 /tmp/usb-mount/boot

# Bootstrap Debian
echo "Bootstrapping Debian..."
debootstrap --arch amd64 bookworm /tmp/usb-mount http://deb.debian.org/debian

# Verify basic system installation
echo "Verifying basic system installation..."
if [ ! -f /tmp/usb-mount/bin/dpkg ]; then
    echo "Error: Basic system installation failed - dpkg not found"
    exit 1
fi

# Mount necessary filesystems
echo "Mounting necessary filesystems..."
mount --bind /dev /tmp/usb-mount/dev
mount --bind /sys /tmp/usb-mount/sys
mount --bind /proc /tmp/usb-mount/proc

# Configure apt
echo "Configuring apt..."
chroot /tmp/usb-mount /bin/bash -c "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin dpkg --configure -a"
chroot /tmp/usb-mount /bin/bash -c "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin apt-get clean"
chroot /tmp/usb-mount /bin/bash -c "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin apt-get update"

# Create necessary directories
echo "Creating directories..."
mkdir -p /tmp/usb-mount/boot/loader/entries
mkdir -p /tmp/usb-mount/usr/local/bin
mkdir -p /tmp/usb-mount/etc/systemd/system

# Install systemd-boot
echo "Installing systemd-boot..."
chroot /tmp/usb-mount /bin/bash -c "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin dpkg -l | grep systemd-boot || PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin apt-get install -y systemd-boot"

# Copy splash screen
echo "Copying splash screen..."
cp files/splash.bmp /tmp/usb-mount/boot/loader/splash.bmp

# Install systemd-boot
echo "Installing systemd-boot..."
chroot /tmp/usb-mount /bin/bash -c "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bootctl --path=/boot install || true"

# Create loader.conf
echo "Creating loader.conf..."
cat > /tmp/usb-mount/boot/loader/loader.conf <<EOF
default debian
timeout 3
console-mode max
EOF

# Create debian.conf
echo "Creating debian.conf..."
cat > /tmp/usb-mount/boot/loader/entries/debian.conf <<EOF
title   Debian USB Installer
linux   /vmlinuz
initrd  /initrd.img
options quiet splash \
        splash.image=/loader/splash.bmp
EOF

# Verify bootloader installation
echo "Verifying bootloader installation..."
if [ ! -f /tmp/usb-mount/boot/EFI/BOOT/BOOTX64.EFI ]; then
    echo "Error: systemd-boot installation failed - BOOTX64.EFI not found"
    exit 1
fi

# Create installer.conf
echo "Creating installer.conf..."
cat > /tmp/usb-mount/etc/installer.conf <<EOF
ROOT_PWD=$ROOT_PWD
CENTROID_PWD=$CENTROID_PWD
EOF

# Copy firstboot installation script
echo "Copying firstboot installation script..."
cp files/firstboot-install.sh /tmp/usb-mount/usr/local/bin/firstboot-install.sh
chmod +x /tmp/usb-mount/usr/local/bin/firstboot-install.sh

# Copy firstboot service
echo "Copying firstboot service..."
cp files/firstboot-install.service /tmp/usb-mount/etc/systemd/system/firstboot-install.service

# Copy ansible playbook
echo "Copying ansible playbook..."
cp ansible-playbook.yml /tmp/usb-mount/root/ansible-playbook.yml

# Enable firstboot service
echo "Enabling firstboot service..."
chroot /tmp/usb-mount systemctl enable firstboot-install.service

# Cleanup
echo "Cleaning up..."
umount /tmp/usb-mount/proc
umount /tmp/usb-mount/sys
umount /tmp/usb-mount/dev
umount /tmp/usb-mount/boot
umount /tmp/usb-mount
losetup -d $LOOP
rm -rf /tmp/usb-mount

echo "Image created successfully: usb-installer.img"
echo "You can now write it to a USB drive with:"
echo "sudo dd if=usb-installer.img of=/dev/sdX bs=4M status=progress"