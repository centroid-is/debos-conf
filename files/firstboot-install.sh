#!/bin/bash
set -euo pipefail

# 1) detect the first non-floppy, non-mounted disk
echo "Detecting target disk…"
DEVICE_MAIN=""
for dev in $(lsblk -pln -o NAME,TYPE | awk '$2=="disk"{print $1}'); do
  # skip floppy
  [[ "$dev" == "/dev/fd0" ]] && continue
  # skip any partition or device currently mounted
  if mount | grep -q "^$dev"; then
    continue
  fi
  DEVICE_MAIN="$dev"
  break
done

if [[ -z "$DEVICE_MAIN" ]]; then
  echo "ERROR: No unused disk found!"
  exit 1
fi

echo "→ Installing to $DEVICE_MAIN"
EFI_PART="${DEVICE_MAIN}1"
ROOT_PART="${DEVICE_MAIN}2"


MARKER=/var/firstboot.done
TARGET=/mnt/target
DISK=$DEVICE_MAIN

# only once
if [ -f "$MARKER" ]; then
  exit 0
fi

# load passwords
source /etc/installer.conf

# 1) Warn user
echo
echo -e "\033[31m**************************************************"
echo "* WARNING: in 60 seconds this installer will      *"
echo "*   ERASE and re-format $DISK on this PC.         *"
echo "**************************************************\033[0m"
echo
sleep 60

# 2) Partition
parted --script "$DISK" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1GiB \
  set 1 esp on \
  mkpart primary ext4 1GiB 100%

echo "Done creating partitions"

# 3) Format
mkfs.vfat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

echo "Done formatting partitions"

# 4) Mount
mkdir -p "$TARGET" "$TARGET/boot"
mount "$ROOT_PART" "$TARGET"
mount "$EFI_PART" "$TARGET/boot"

echo "Mounted root and boot partition"

# 5) Bootstrap Debian
debootstrap --arch amd64 bookworm "$TARGET" http://deb.debian.org/debian

echo "Bootstrapped root partition"

# 6) Copy installer assets into new root
cp /root/ansible-playbook.yml "$TARGET/root/"
cp /etc/installer.conf "$TARGET/etc/"
cp /boot/loader/splash.bmp "$TARGET/boot/loader/"

# 7) Bind‐mount for chroot
for fs in dev sys proc; do
  mount --bind /$fs "$TARGET/$fs"
done

echo "Install ansible and run it"

# 8) Install ansible & run playbook inside the new system
chroot "$TARGET" /bin/bash -lc "
  apt-get update
  apt-get install -y sudo ansible curl ca-certificates
  ANSIBLE_HOST_KEY_CHECKING=False \
    ansible-playbook /root/ansible-playbook.yml \
      -c local \
      --extra-vars \"root_password=$ROOT_PWD centroid_password=$CENTROID_PWD\"
"

echo "Done with ansible"
echo "Installing bootloader"

# 9) Install systemd-boot on target disk
chroot "$TARGET" /bin/bash -lc "bootctl --path=/boot install"

# 10) Clean up
for fs in dev sys proc; do
  umount "$TARGET/$fs"
done
touch "$TARGET/$MARKER"
umount "$TARGET/boot"
umount "$TARGET"

echo "Done, cleaning up"
echo
echo -e "\033[31m**************************************************"
echo "* WARNING: Be ready to remove the USB stick now.  *"
echo "*   This system will reboot in 60 seconds.        *"
echo "**************************************************\033[0m"
echo
sleep 60

reboot
