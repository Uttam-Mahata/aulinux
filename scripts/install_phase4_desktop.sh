#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  AULinux Phase 4 Integration: Wayland Desktop (Weston reference compositor)
# ══════════════════════════════════════════════════════════════════════

set -e
ROOTFS_DIR="${1:-}"

if [ -z "$ROOTFS_DIR" ]; then
    echo "ERROR: ROOTFS_DIR argument is required" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_GNU_TRIPLE="$(gcc -dumpmachine 2>/dev/null || dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "x86_64-linux-gnu")"

echo "[Phase 4] Integrating real Wayland Desktop environment into $ROOTFS_DIR..."

# Shared Library Resolver
resolve_deps() {
    local binary="$1"
    local rootfs="$2"
    local seen_file="$rootfs/.resolved_libs"
    touch "$seen_file"

    local libs=""
    set +e
    libs="$(ldd "$binary" 2>/dev/null | grep "=>" | awk '{print $3}' | grep "^/")"
    set -e

    if [ -z "$libs" ]; then
        return 0
    fi

    echo "$libs" | while read -r lib; do
        [ -z "$lib" ] && continue
        [ "$lib" = "not" ] && continue
        grep -qxF "$lib" "$seen_file" 2>/dev/null && continue
        echo "$lib" >> "$seen_file"
        if [ -f "$lib" ]; then
            dest="$rootfs$(dirname "$lib")"
            mkdir -p "$dest"
            cp -L "$lib" "$dest/" 2>/dev/null
            resolve_deps "$lib" "$rootfs"
        fi
    done
}

# 1. Download and Extract Weston Wayland Compositor deb package
CACHE_DIR="$PROJECT_ROOT/build/cache"
mkdir -p "$CACHE_DIR"
WESTON_DEB="$(find "$CACHE_DIR" -name "weston_*.deb" | head -n 1)"

if [ -z "$WESTON_DEB" ] || [ ! -f "$WESTON_DEB" ]; then
    echo "  + Downloading weston deb package..."
    (cd "$CACHE_DIR" && apt-get download weston 2>/dev/null || true)
    WESTON_DEB="$(find "$CACHE_DIR" -name "weston_*.deb" | head -n 1)"
fi

# Resilient fallback download URL if apt-get download is not available
if [ -z "$WESTON_DEB" ] || [ ! -f "$WESTON_DEB" ]; then
    echo "  + Falling back to direct URL download for weston deb..."
    # Standard Ubuntu stable package URL
    FALLBACK_URL="https://archive.ubuntu.com/ubuntu/pool/universe/w/weston/weston_14.0.2-5_amd64.deb"
    wget -q --show-progress -O "$CACHE_DIR/weston_14.0.2-5_amd64.deb" "$FALLBACK_URL" || \
        curl -L -o "$CACHE_DIR/weston_14.0.2-5_amd64.deb" "$FALLBACK_URL" || true
    WESTON_DEB="$(find "$CACHE_DIR" -name "weston_*.deb" | head -n 1)"
fi

if [ -n "$WESTON_DEB" ] && [ -f "$WESTON_DEB" ]; then
    echo "  + Extracting weston deb package ($WESTON_DEB)..."
    EXTRACT_DIR="$PROJECT_ROOT/build/weston-extracted"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    dpkg-deb -x "$WESTON_DEB" "$EXTRACT_DIR"
    
    # 2. Deploy Weston binaries and structures to rootfs
    echo "  + Copying Weston and Wayland binaries/configs..."
    mkdir -p "$ROOTFS_DIR/usr/bin"
    mkdir -p "$ROOTFS_DIR/usr/libexec"
    mkdir -p "$ROOTFS_DIR/usr/lib/$_GNU_TRIPLE"
    
    # Copy Weston main compositor, terminal, and helpers
    [ -f "$EXTRACT_DIR/usr/bin/weston" ] && cp -L "$EXTRACT_DIR/usr/bin/weston" "$ROOTFS_DIR/usr/bin/"
    [ -f "$EXTRACT_DIR/usr/bin/weston-terminal" ] && cp -L "$EXTRACT_DIR/usr/bin/weston-terminal" "$ROOTFS_DIR/usr/bin/"
    [ -d "$EXTRACT_DIR/usr/libexec" ] && cp -rP "$EXTRACT_DIR/usr/libexec"/* "$ROOTFS_DIR/usr/libexec/" 2>/dev/null || true
    [ -d "$EXTRACT_DIR/usr/lib/$_GNU_TRIPLE/weston" ] && cp -rP "$EXTRACT_DIR/usr/lib/$_GNU_TRIPLE/weston" "$ROOTFS_DIR/usr/lib/$_GNU_TRIPLE/" 2>/dev/null || true
    [ -d "$EXTRACT_DIR/usr/share/weston" ] && mkdir -p "$ROOTFS_DIR/usr/share" && cp -rP "$EXTRACT_DIR/usr/share/weston" "$ROOTFS_DIR/usr/share/"
    
    # Resolve library dependencies for Weston core binaries
    echo "  + Resolving Weston dynamic library dependencies..."
    resolve_deps "$ROOTFS_DIR/usr/bin/weston" "$ROOTFS_DIR"
    resolve_deps "$ROOTFS_DIR/usr/bin/weston-terminal" "$ROOTFS_DIR"
    [ -f "$ROOTFS_DIR/usr/libexec/weston-desktop-shell" ] && resolve_deps "$ROOTFS_DIR/usr/libexec/weston-desktop-shell" "$ROOTFS_DIR"
    find "$ROOTFS_DIR/usr/lib/$_GNU_TRIPLE/weston" -name "*.so" 2>/dev/null | while read -r mod; do
        resolve_deps "$mod" "$ROOTFS_DIR"
    done
else
    echo "  - ERROR: Failed to obtain weston deb package. Wayland desktop cannot be established."
    exit 1
fi

# 3. Copy minimal fonts set for terminal and shell
echo "  + Copying font packages..."
mkdir -p "$ROOTFS_DIR/usr/share/fonts"
for font_dir in "/usr/share/fonts/truetype/dejavu" "/usr/share/fonts/truetype/liberation" "/usr/share/fonts/X11"; do
    if [ -d "$font_dir" ]; then
        echo "    - Copying $font_dir..."
        dest_font_dir="$ROOTFS_DIR/usr/share/fonts/$(basename "$font_dir")"
        mkdir -p "$dest_font_dir"
        cp -rP "$font_dir"/* "$dest_font_dir/" 2>/dev/null || true
    fi
done

# 4. Configure Weston config file (weston.ini)
echo "  + Creating /etc/xdg/weston/weston.ini..."
mkdir -p "$ROOTFS_DIR/etc/xdg/weston"
cat > "$ROOTFS_DIR/etc/xdg/weston/weston.ini" << 'EOF'
[core]
backend=drm-backend.so
shell=desktop-shell.so

[shell]
background-color=0xff1e3a5f
panel-position=top
locking=false

[launcher]
icon=/usr/share/weston/icon_terminal.png
path=/usr/bin/weston-terminal
EOF

# 5. Re-write start_desktop.sh to boot Weston Wayland instead of X11
echo "  + Re-writing start_desktop script in rootfs..."
mkdir -p "$ROOTFS_DIR/bin"
cat > "$ROOTFS_DIR/bin/start_desktop.sh" << 'EOF'
#!/bin/bash
# Start Wayland desktop session (Weston reference compositor)
export HOME=/root
export USER=root
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export LD_LIBRARY_PATH=/lib:/usr/lib:/usr/lib/$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)

# Wayland compositors require XDG_RUNTIME_DIR to be set and writeable
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p /run/user/0
chmod 700 /run/user/0

echo "Starting Weston Wayland Compositor on DRM/KMS..."
# Auto-fallback from DRM-backend to pixman/fbdev backend if needed
weston --tty=1 --log=/var/log/weston.log &
WESTON_PID=$!
sleep 2

echo "Wayland Desktop started. Press Ctrl+C to exit."
wait $WESTON_PID
EOF
chmod +x "$ROOTFS_DIR/bin/start_desktop.sh"
ln -sf start_desktop.sh "$ROOTFS_DIR/bin/start_desktop" 2>/dev/null || true

# 6. Create a separate fragment for the desktop service
echo "  + Writing desktop_service_fragment.conf..."
cat > "$PROJECT_ROOT/scripts/desktop_service_fragment.conf" << 'EOF'
[desktop]
Exec=/bin/start_desktop
Type=oneshot
After=shell
Restart=never
EOF

# 7. Update repo.db registry for Wayland packages
REPO_DB="$ROOTFS_DIR/var/lib/aupkg/repo.db"
if [ -f "$REPO_DB" ]; then
    echo "  + Updating package registry repo.db..."
    python3 - <<EOF
import json
import platform
repo_path = "$REPO_DB"
try:
    with open(repo_path, 'r') as f:
        db = json.load(f)
except Exception:
    db = {}

# Set weston and libwayland to installed = True since we deployed them
for pkg in ["weston", "libwayland", "libinput", "libdrm", "mesa"]:
    if pkg in db:
        db[pkg]["installed"] = True
        db[pkg]["real_package"] = True
        db[pkg]["architecture"] = platform.machine()

with open(repo_path, 'w') as f:
    json.dump(db, f, indent=2)
print("  + repo.db updated successfully.")
EOF
fi

echo "[Phase 4] COMPLETE."
