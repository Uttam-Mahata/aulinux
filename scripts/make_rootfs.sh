#!/bin/bash
set -e

PROJECT_ROOT=$(pwd)
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS_DIR="$PROJECT_ROOT/rootfs"

echo "Creating rootfs in $ROOTFS_DIR..."

# Create directories
mkdir -p "$ROOTFS_DIR"/{bin,sbin,etc,usr,var,proc,sys,dev,tmp,run,boot,home,root}
mkdir -p "$ROOTFS_DIR"/etc/aulinux
mkdir -p "$ROOTFS_DIR"/usr/{bin,sbin,lib}
chmod 1777 "$ROOTFS_DIR/tmp"

# Copy init
if [ -f "$BUILD_DIR/init/au-init" ]; then
    cp "$BUILD_DIR/init/au-init" "$ROOTFS_DIR/sbin/init"
    ln -sf /sbin/init "$ROOTFS_DIR/init"
    echo "Installed init"
else
    echo "Warning: au-init not found in build/"
fi

# Copy shell
if [ -f "$BUILD_DIR/shell/aush" ]; then
    cp "$BUILD_DIR/shell/aush" "$ROOTFS_DIR/bin/aush"
    ln -sf /bin/aush "$ROOTFS_DIR/bin/sh"
    echo "Installed shell"
else
    echo "Warning: aush not found in build/"
fi

# Copy utilities
if [ -d "$BUILD_DIR/utils" ]; then
    cp "$BUILD_DIR/utils/"* "$ROOTFS_DIR/bin/" 2>/dev/null || true
    echo "Installed utilities"
else
    echo "Warning: utils not found in build/"
fi

# Config files
echo "aulinux" > "$ROOTFS_DIR/etc/hostname"

if [ ! -f "$ROOTFS_DIR/etc/passwd" ]; then
    cat > "$ROOTFS_DIR/etc/passwd" << EOF
root:x:0:0:root:/root:/bin/aush
guest:x:1000:1000:guest:/home/guest:/bin/aush
EOF
fi

if [ ! -f "$ROOTFS_DIR/etc/group" ]; then
    cat > "$ROOTFS_DIR/etc/group" << EOF
root:x:0:
guest:x:1000:
EOF
fi

cat > "$ROOTFS_DIR/etc/fstab" << EOF
# file system    mount point   type    options    dump pass
proc             /proc         proc    defaults   0    0
sysfs            /sys          sysfs   defaults   0    0
EOF

touch "$ROOTFS_DIR/etc/aulinux/services.conf"

echo "Rootfs created successfully at $ROOTFS_DIR"
