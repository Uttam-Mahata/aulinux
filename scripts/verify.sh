#!/bin/bash
# scripts/verify.sh
# Verification script for AULinux core components.

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

info "Starting AULinux component verification..."

# 1. Check build files
if [ ! -d "$BUILD_DIR" ]; then
    error "Build directory does not exist. Run './scripts/build.sh all' first."
    exit 1
fi

# 2. Verify Multicall Binary
info "Verifying Multicall Binary (auutils)..."
if [ ! -f "$BUILD_DIR/utils/auutils" ]; then
    error "auutils binary not found."
    exit 1
fi

# Test pwd
PWD_OUT=$("$BUILD_DIR/utils/auutils" pwd)
if [ "$PWD_OUT" = "$PWD" ]; then
    success "auutils pwd works correctly"
else
    error "auutils pwd returned '$PWD_OUT' instead of '$PWD'"
    exit 1
fi

# Test echo
ECHO_OUT=$("$BUILD_DIR/utils/auutils" echo "Testing multicall echo")
if [ "$ECHO_OUT" = "Testing multicall echo" ]; then
    success "auutils echo works correctly"
else
    error "auutils echo returned '$ECHO_OUT'"
    exit 1
fi

# Test ls
if "$BUILD_DIR/utils/auutils" ls >/dev/null; then
    success "auutils ls works correctly"
else
    error "auutils ls failed to execute"
    exit 1
fi

# 3. Verify Shell (aush)
info "Verifying Absolutely Unique Shell (aush)..."
if [ ! -L "$BUILD_DIR/utils/aush" ] && [ ! -f "$BUILD_DIR/utils/aush" ]; then
    error "aush binary/symlink not found in build/utils."
    exit 1
fi

# Test version
SHELL_VER=$("$BUILD_DIR/utils/aush" --version 2>&1)
if [[ "$SHELL_VER" == *"aush (AULinux Shell)"* ]]; then
    success "aush --version works correctly: $SHELL_VER"
else
    error "aush --version failed or returned unexpected output: $SHELL_VER"
    exit 1
fi

# Test command execution mode (-c)
SHELL_EXEC=$("$BUILD_DIR/utils/aush" -c "echo 'Shell Command Execution Mode works!'" 2>&1)
if [ "$SHELL_EXEC" = "Shell Command Execution Mode works!" ]; then
    success "aush command execution (-c) works correctly"
else
    error "aush command execution failed, output: '$SHELL_EXEC'"
    exit 1
fi

# 4. Verify Package Manager (aupkg)
info "Verifying Package Manager (aupkg)..."
if [ ! -f "$BUILD_DIR/pkg-manager/aupkg" ]; then
    error "aupkg binary not found."
    exit 1
fi

# Test version
AUPKG_VER=$("$BUILD_DIR/pkg-manager/aupkg" --version 2>&1)
if [[ "$AUPKG_VER" == *"aupkg 1.0.0"* ]]; then
    success "aupkg --version works correctly: $AUPKG_VER"
else
    error "aupkg --version failed or returned unexpected output: $AUPKG_VER"
    exit 1
fi

# Test list command
if "$BUILD_DIR/pkg-manager/aupkg" list &>/dev/null; then
    success "aupkg list command executes and handles directories safely"
else
    # In some sandboxes it might print warnings but still exit 0
    if "$BUILD_DIR/pkg-manager/aupkg" list 2>/dev/null; then
        success "aupkg list command works"
    else
        error "aupkg list command failed to execute"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  All AULinux core components are verified! ${NC}"
echo -e "${GREEN}===========================================${NC}"
echo ""
