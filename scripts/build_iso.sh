#!/bin/bash
# scripts/build_iso.sh
# Automates compiling all AULinux components, staging files, and creating a bootable Live Installation ISO.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS_DIR="$PROJECT_ROOT/rootfs"
KERNEL_FILE="$BUILD_DIR/vmlinuz"
INITRAMFS_FILE="$BUILD_DIR/initramfs.img"
ISO_TMP_DIR="$BUILD_DIR/iso_tmp"
ISO_OUTPUT="$BUILD_DIR/aulinux.iso"

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Build and verify tools are present
info "Checking for ISO generation tools..."
if ! command -v grub-mkrescue >/dev/null && ! command -v xorriso >/dev/null; then
    error "Missing required ISO creation tools (grub-mkrescue or xorriso). Please install 'grub-common', 'grub-pc-bin', and 'xorriso'."
    exit 1
fi

# 2. Build all components
info "Compiling all OS components (C kernel modules/init, Go utilities, Rust package manager)..."
"$PROJECT_ROOT/scripts/build.sh" all

# 3. Generate the fresh rootfs containing the installer & desktop environment packages
info "Generating AULinux rootfs..."
rm -rf "$ROOTFS_DIR"
"$PROJECT_ROOT/scripts/make_rootfs.sh"

# 4. Handle obtaining the kernel (aligned with run_qemu.sh)
mkdir -p "$BUILD_DIR"
if [ ! -f "$KERNEL_FILE" ]; then
    info "No kernel found at $KERNEL_FILE. Attempting to obtain one..."
    if [ -f "$BUILD_DIR/vmlinuz-virt" ]; then
        info "Using pre-downloaded Alpine virtual kernel at $BUILD_DIR/vmlinuz-virt"
        cp "$BUILD_DIR/vmlinuz-virt" "$KERNEL_FILE"
    elif cp /boot/vmlinuz "$KERNEL_FILE" 2>/dev/null; then
        success "Copied host kernel from /boot/vmlinuz"
    elif cp "/boot/vmlinuz-$(uname -r)" "$KERNEL_FILE" 2>/dev/null; then
        success "Copied host kernel from /boot/vmlinuz-$(uname -r)"
    else
        warn "Could not read host kernel directly from /boot. Downloading Alpine fallback..."
        if curl -Lo "$KERNEL_FILE" "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/netboot/vmlinuz-virt"; then
            success "Successfully downloaded minimal Alpine kernel to $KERNEL_FILE"
        else
            error "Failed to obtain kernel through all available methods."
            exit 1
        fi
    fi
else
    info "Using existing kernel at $KERNEL_FILE"
fi

# 5. Packaging the rootfs into initramfs
info "Packaging rootfs into initramfs..."
cd "$ROOTFS_DIR"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$INITRAMFS_FILE"
cd "$PROJECT_ROOT"
success "Successfully packaged initramfs to $INITRAMFS_FILE"

# 6. Stage files for ISO creation
info "Staging bootable GRUB ISO files..."
rm -rf "$ISO_TMP_DIR"
mkdir -p "$ISO_TMP_DIR"/boot/grub

# Copy Kernel and Initrd to ISO structure
cp "$KERNEL_FILE" "$ISO_TMP_DIR"/boot/vmlinuz
cp "$INITRAMFS_FILE" "$ISO_TMP_DIR"/boot/initramfs.img

# Write custom GRUB Configuration
cat > "$ISO_TMP_DIR"/boot/grub/grub.cfg << 'EOF'
set default=0
set timeout=15

# Visual aesthetics
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "AULinux Live OS (Console Mode)" {
    linux /boot/vmlinuz init=/sbin/init console=ttyS0 console=tty0 quiet
    initrd /boot/initramfs.img
}

menuentry "AULinux Live OS (Graphical Mode - Openbox)" {
    linux /boot/vmlinuz init=/sbin/init quiet
    initrd /boot/initramfs.img
}

menuentry "Install AULinux to Hard Disk (Interactive Wizard)" {
    linux /boot/vmlinuz init=/bin/install-os quiet
    initrd /boot/initramfs.img
}
EOF

# 7. Generate bootable ISO using grub-mkrescue
info "Running grub-mkrescue to build the bootable ISO..."
if grub-mkrescue -o "$ISO_OUTPUT" "$ISO_TMP_DIR"; then
    success "AULinux Bootable ISO successfully created at: $ISO_OUTPUT"
    info "ISO Size: $(du -sh "$ISO_OUTPUT" | cut -f1)"
else
    error "Failed to build ISO using grub-mkrescue!"
    exit 1
fi

# 8. Cleanup staging
rm -rf "$ISO_TMP_DIR"
info "Staging directory cleaned up."
