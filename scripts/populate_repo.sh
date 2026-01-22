#!/bin/bash
set -e

PROJECT_ROOT=$(pwd)
BUILD_DIR="$PROJECT_ROOT/build"
REPO_DIR="$PROJECT_ROOT/repo/core"
AUBUILD="$BUILD_DIR/utils/aubuild"

if [ ! -f "$AUBUILD" ]; then
    echo "aubuild not found. Please build it first."
    exit 1
fi

mkdir -p "$REPO_DIR"

# Helper to build package
build_pkg() {
    local name=$1
    local version=$2
    local src=$3
    local desc=$4

    echo "Building package $name $version..."
    "$AUBUILD" -src "$src" -out "$REPO_DIR" -name "$name" -version "$version" -desc "$desc"
}

# 1. Base files (init, shell)
PKG_BASE="$PROJECT_ROOT/pkg_tmp/base"
rm -rf "$PKG_BASE"
mkdir -p "$PKG_BASE/sbin" "$PKG_BASE/bin" "$PKG_BASE/etc"

if [ -f "$BUILD_DIR/init/au-init" ]; then
    cp "$BUILD_DIR/init/au-init" "$PKG_BASE/sbin/init"
fi
if [ -f "$BUILD_DIR/shell/aush" ]; then
    cp "$BUILD_DIR/shell/aush" "$PKG_BASE/bin/aush"
    # Use relative link for packaging or just copy it
    # Go's os.Walk follows symlinks? Or tar follows it?
    # If the link target doesn't exist on host, it might fail to open if we try to read it.
    # Let's just cp it again for simplicity in packaging script
    cp "$BUILD_DIR/shell/aush" "$PKG_BASE/bin/sh"
fi

build_pkg "base-system" "1.0.0" "$PKG_BASE" "Base system with init and shell"

# 2. Core Utils
PKG_UTILS="$PROJECT_ROOT/pkg_tmp/coreutils"
rm -rf "$PKG_UTILS"
mkdir -p "$PKG_UTILS/bin"
if [ -d "$BUILD_DIR/utils" ]; then
    cp "$BUILD_DIR/utils/"* "$PKG_UTILS/bin/" 2>/dev/null || true
fi
# Remove aubuild from coreutils if present, it's a dev tool
rm -f "$PKG_UTILS/bin/aubuild"

build_pkg "coreutils" "1.0.0" "$PKG_UTILS" "Core utilities"

# 3. Package Manager
PKG_AUPKG="$PROJECT_ROOT/pkg_tmp/aupkg"
rm -rf "$PKG_AUPKG"
mkdir -p "$PKG_AUPKG/bin"
if [ -f "$BUILD_DIR/pkg-manager/aupkg" ]; then
    cp "$BUILD_DIR/pkg-manager/aupkg" "$PKG_AUPKG/bin/aupkg"
fi

build_pkg "aupkg" "0.1.0" "$PKG_AUPKG" "AuLinux Package Manager"

# Cleanup
rm -rf "$PROJECT_ROOT/pkg_tmp"

echo "Repository populated at $REPO_DIR"
ls -l "$REPO_DIR"
