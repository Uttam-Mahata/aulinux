#!/bin/bash
# scripts/install_grub.sh
# Installs GRUB to a disk image

set -e

IMAGE_FILE=${1:-"aulinux.img"}
KERNEL_FILE=${2:-"build/vmlinuz"}
INITRAMFS_FILE=${3:-"build/initramfs.img"}
ROOTFS_DIR=${4:-"rootfs"}

# Note: This script assumes the user has tools like loops setup.

echo "Installing GRUB to $IMAGE_FILE..."

# Check dependencies
if ! command -v grub-install &> /dev/null; then
    echo "Error: grub-install could not be found."
    exit 1
fi

cat << EOF
This script requires root privileges and loop devices.
Execute the following manually if this script is not running as root:

1. Create disk image:
   dd if=/dev/zero of=$IMAGE_FILE bs=1M count=512

2. Partition image:
   parted $IMAGE_FILE --script mklabel msdos mkpart primary ext4 1MiB 100% set 1 boot on

3. Format partition:
   LOOPDEV=\$(losetup -fP --show $IMAGE_FILE)
   mkfs.ext4 \${LOOPDEV}p1
   mount \${LOOPDEV}p1 /mnt

4. Copy rootfs:
   cp -a $ROOTFS_DIR/* /mnt/

5. Copy kernel:
   cp $KERNEL_FILE /mnt/boot/vmlinuz
   cp $INITRAMFS_FILE /mnt/boot/initramfs.img

6. Install GRUB:
   grub-install --target=i386-pc --boot-directory=/mnt/boot \${LOOPDEV}
   cp bootloader/grub.cfg /mnt/boot/grub/grub.cfg

7. Cleanup:
   umount /mnt
   losetup -d \${LOOPDEV}
EOF

# If running as root and tools available, we could attempt to run these commands.
if [ "$EUID" -eq 0 ]; then
    read -p "Run these commands now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        dd if=/dev/zero of="$IMAGE_FILE" bs=1M count=512
        parted "$IMAGE_FILE" --script mklabel msdos mkpart primary ext4 1MiB 100% set 1 boot on
        LOOPDEV=$(losetup -fP --show "$IMAGE_FILE")
        mkfs.ext4 "${LOOPDEV}p1"
        mkdir -p /mnt/aulinux_mnt
        mount "${LOOPDEV}p1" /mnt/aulinux_mnt

        cp -a "$ROOTFS_DIR"/* /mnt/aulinux_mnt/

        mkdir -p /mnt/aulinux_mnt/boot
        if [ -f "$KERNEL_FILE" ]; then
            cp "$KERNEL_FILE" /mnt/aulinux_mnt/boot/vmlinuz
        fi
        if [ -f "$INITRAMFS_FILE" ]; then
            cp "$INITRAMFS_FILE" /mnt/aulinux_mnt/boot/initramfs.img
        fi

        grub-install --target=i386-pc --boot-directory=/mnt/aulinux_mnt/boot "$LOOPDEV"
        mkdir -p /mnt/aulinux_mnt/boot/grub
        cp bootloader/grub.cfg /mnt/aulinux_mnt/boot/grub/grub.cfg

        umount /mnt/aulinux_mnt
        losetup -d "$LOOPDEV"
        rmdir /mnt/aulinux_mnt
        echo "Done."
    fi
fi
