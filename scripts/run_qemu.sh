#!/bin/bash
# scripts/run_qemu.sh
# Automated build, rootfs generation, initramfs packaging, kernel retrieval, and QEMU booting script for AULinux.

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

# 1. Build all components
info "Building AULinux components..."
"$PROJECT_ROOT/scripts/build.sh" all

# 2. Recreate rootfs
info "Generating rootfs..."
rm -rf "$ROOTFS_DIR"
"$PROJECT_ROOT/scripts/make_rootfs.sh"

# 3. Handle obtaining a kernel
mkdir -p "$BUILD_DIR"
if [ ! -f "$KERNEL_FILE" ]; then
    info "No kernel found at $KERNEL_FILE. Attempting to obtain one..."

    # Method A: Try copying the test Alpine kernel if already downloaded as vmlinuz-virt
    if [ -f "$BUILD_DIR/vmlinuz-virt" ]; then
        info "Found pre-downloaded Alpine virtual kernel at $BUILD_DIR/vmlinuz-virt. Using it."
        cp "$BUILD_DIR/vmlinuz-virt" "$KERNEL_FILE"
    # Method B: Try copying the host kernel from /boot
    elif cp /boot/vmlinuz "$KERNEL_FILE" 2>/dev/null; then
        success "Successfully copied host kernel from /boot/vmlinuz"
    elif cp "/boot/vmlinuz-$(uname -r)" "$KERNEL_FILE" 2>/dev/null; then
        success "Successfully copied host kernel from /boot/vmlinuz-$(uname -r)"
    else
        warn "Could not read host kernel directly from /boot (Permission Denied or not found)."
        
        # Method C: Try apt-get download for host kernel (requires no root)
        if command -v apt-get >/dev/null; then
            info "Attempting to download and extract host kernel package using apt-get..."
            cd "$BUILD_DIR"
            if apt-get download "linux-image-unsigned-$(uname -r)" || apt-get download "linux-image-$(uname -r)"; then
                DEB_FILE=$(ls linux-image-*.deb 2>/dev/null | head -n 1)
                if [ -n "$DEB_FILE" ]; then
                    info "Extracting $DEB_FILE to extract vmlinuz..."
                    mkdir -p tmp_kernel_ext
                    dpkg-deb -x "$DEB_FILE" tmp_kernel_ext
                    EXT_VMLINUZ=$(find tmp_kernel_ext -name "vmlinuz*" | head -n 1)
                    if [ -n "$EXT_VMLINUZ" ]; then
                        cp "$EXT_VMLINUZ" "$KERNEL_FILE"
                        success "Successfully extracted kernel from deb package to $KERNEL_FILE"
                    fi
                    rm -rf tmp_kernel_ext "$DEB_FILE"
                fi
            fi
            cd "$PROJECT_ROOT"
        fi
        
        # Method D: Fallback to downloading a minimal virtualized Alpine kernel
        if [ ! -f "$KERNEL_FILE" ]; then
            info "Falling back to downloading minimal Alpine virtualized kernel..."
            _alpine_arch="$(uname -m | sed 's/armv7l/armv7/')"
            if curl -Lo "$KERNEL_FILE" "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/${_alpine_arch}/netboot/vmlinuz-virt"; then
                success "Successfully downloaded minimal Alpine kernel to $KERNEL_FILE"
            else
                error "Failed to obtain kernel through all available methods."
                exit 1
            fi
        fi
    fi
else
    info "Using existing kernel at $KERNEL_FILE"
fi

# 4. Packaging the rootfs into initramfs
info "Packaging rootfs into initramfs.img..."
cd "$ROOTFS_DIR"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$INITRAMFS_FILE"
cd "$PROJECT_ROOT"
success "Successfully packaged initramfs to $INITRAMFS_FILE ($(du -sh "$INITRAMFS_FILE" | cut -f1))"

# 5. Boot inside QEMU
case "$(uname -m)" in
    aarch64) QEMU_BIN="qemu-system-aarch64"; QEMU_MACHINE="-machine virt -cpu cortex-a57" ;;
    armv7l)  QEMU_BIN="qemu-system-arm";     QEMU_MACHINE="-machine virt -cpu cortex-a15" ;;
    *)       QEMU_BIN="qemu-system-x86_64";  QEMU_MACHINE="" ;;
esac

if ! command -v "$QEMU_BIN" >/dev/null; then
    error "$QEMU_BIN is not installed. Please install QEMU."
    exit 1
fi

info "Booting AULinux in QEMU ($QEMU_BIN)..."
if [ "$1" == "--gui" ]; then
    info "Launching QEMU with graphical output..."
    $QEMU_BIN $QEMU_MACHINE \
        -kernel "$KERNEL_FILE" \
        -initrd "$INITRAMFS_FILE" \
        -append "init=/sbin/init quiet" \
        -net nic,model=virtio -net user \
        -m 512M
else
    info "Launching QEMU in non-graphical mode..."
    info "--------------------------------------------------------"
    info "To exit QEMU, press Ctrl+A then X"
    info "--------------------------------------------------------"
    sleep 2
    $QEMU_BIN $QEMU_MACHINE \
        -kernel "$KERNEL_FILE" \
        -initrd "$INITRAMFS_FILE" \
        -append "init=/sbin/init console=ttyS0 quiet" \
        -net nic,model=virtio -net user \
        -nographic \
        -m 512M
fi
