#!/bin/bash
#
# AULinux Build Script
# Builds all components of the AULinux distribution.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

# Print colored message
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

# Print banner
print_banner() {
    echo ""
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║     AULinux Build System v1.0.0       ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo ""
}

# Build kernel modules
build_kernel() {
    info "Building kernel modules..."
    cd "$PROJECT_ROOT/kernel"
    if make; then
        success "Kernel modules built"
    else
        warn "Kernel modules build failed (may require kernel headers)"
    fi
}

# Build init system
build_init() {
    info "Building init system..."
    cd "$PROJECT_ROOT/init"
    make
    success "Init system built"
}

# Build shell (Wrapper for utils since shell is now integrated)
build_shell() {
    info "Building shell (integrated into utils)..."
    build_utils
}

# Build utilities (Multicall Binary)
build_utils() {
    info "Building utilities (Multicall Binary)..."

    # Ensure build directory exists
    mkdir -p "$BUILD_DIR/utils"

    # Build from root to pick up go.mod
    cd "$PROJECT_ROOT"

    info "Compiling auutils..."
    CGO_ENABLED=0 GOOS=linux GOARCH="${GOARCH:-$(go env GOHOSTARCH)}" \
        go build -ldflags="-s -w -buildid=" -trimpath \
        -o "$BUILD_DIR/utils/auutils" ./utils/

    # Compression (Optional)
    if command -v upx >/dev/null; then
        info "Compressing binary with UPX..."
        upx --best --lzma "$BUILD_DIR/utils/auutils"
    else
        warn "UPX not found, skipping compression."
    fi

    # Create Link Farm
    local UTILS=("ls" "cat" "cp" "mv" "mkdir" "rm" "chmod" "echo" "pwd" "ps" "ip" "useradd" "groupadd" "aubuild" "aush" "sh")
    info "Creating symlinks..."
    for tool in "${UTILS[@]}"; do
        ln -sf auutils "$BUILD_DIR/utils/$tool"
    done

    success "Utilities built and linked."
}

# Build package manager
build_pkgmanager() {
    info "Building package manager (aupkg)..."
    cd "$PROJECT_ROOT/pkg-manager"
    local target="${RUST_TARGET:-}"
    if [ -n "$target" ]; then
        cargo build --release --target "$target"
        mkdir -p "$BUILD_DIR/pkg-manager"
        cp "target/$target/release/aupkg" "$BUILD_DIR/pkg-manager/"
    else
        cargo build --release
        mkdir -p "$BUILD_DIR/pkg-manager"
        cp target/release/aupkg "$BUILD_DIR/pkg-manager/"
    fi
    success "Package manager built"
}

# Clean all build artifacts
clean() {
    info "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    cd "$PROJECT_ROOT/kernel" && make clean 2>/dev/null || true
    cd "$PROJECT_ROOT/init" && make clean 2>/dev/null || true
    cd "$PROJECT_ROOT/pkg-manager" && cargo clean 2>/dev/null || true
    success "Clean complete"
}

# Build all components
build_all() {
    print_banner
    mkdir -p "$BUILD_DIR"
    
    build_init
    # build_shell is covered by build_utils now
    build_utils
    build_pkgmanager
    build_kernel
    
    echo ""
    success "All components built successfully!"
    echo ""
    echo "Build artifacts in: $BUILD_DIR"
    ls -la "$BUILD_DIR"
}

# Show help
show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all        Build all components (default)"
    echo "  kernel     Build kernel modules only"
    echo "  init       Build init system only"
    echo "  shell      Build shell only (via utils)"
    echo "  utils      Build utilities only"
    echo "  pkgmanager Build package manager only"
    echo "  clean      Clean all build artifacts"
    echo "  help       Show this help message"
}

# Main
case "${1:-all}" in
    all)
        build_all
        ;;
    kernel)
        build_kernel
        ;;
    init)
        build_init
        ;;
    shell)
        build_shell
        ;;
    utils)
        build_utils
        ;;
    pkgmanager|pkg-manager)
        build_pkgmanager
        ;;
    clean)
        clean
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
