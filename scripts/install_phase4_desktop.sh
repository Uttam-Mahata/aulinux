#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  AULinux Phase 4 Integration: X11 Desktop (Xorg + Openbox + Xterm)
# ══════════════════════════════════════════════════════════════════════

set -e
ROOTFS_DIR="${1:-}"

if [ -z "$ROOTFS_DIR" ]; then
    echo "ERROR: ROOTFS_DIR argument is required" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[Phase 4] Integrating real X11 Desktop environment into $ROOTFS_DIR..."

# Shared Library Resolver
resolve_deps() {
    local binary="$1"
    local rootfs="$2"
    local seen_file="$rootfs/.resolved_libs"
    touch "$seen_file"

    local libs=""
    # Temporarily allow commands to fail to prevent shell scripts from crashing ldd
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

copy_binary() {
    local name="$1"
    local dest_dir="$2"
    local src_path
    src_path="$(which "$name" 2>/dev/null || true)"

    if [ -z "$src_path" ]; then
        for p in "/usr/bin/$name" "/bin/$name" "/usr/sbin/$name" "/sbin/$name"; do
            if [ -f "$p" ]; then
                src_path="$p"
                break
            fi
        done
    fi

    if [ -n "$src_path" ] && [ -f "$src_path" ]; then
        echo "  + $name ($src_path) -> $dest_dir"
        mkdir -p "$ROOTFS_DIR$dest_dir"
        cp -L "$src_path" "$ROOTFS_DIR$dest_dir/"
        resolve_deps "$src_path" "$ROOTFS_DIR"
    else
        echo "  - WARNING: $name not found on host"
    fi
}

# 1. Deploy Xorg Server from Host
echo "  + Deploying Xorg Server and modules..."
copy_binary "Xorg" "/usr/bin"
ln -sf Xorg "$ROOTFS_DIR/usr/bin/X" 2>/dev/null || true

if [ -d "/usr/lib/xorg" ]; then
    mkdir -p "$ROOTFS_DIR/usr/lib"
    cp -rP /usr/lib/xorg "$ROOTFS_DIR/usr/lib/"
    # Resolve deps for all .so files in usr/lib/xorg
    find "$ROOTFS_DIR/usr/lib/xorg" -name "*.so" | while read -r lib; do
        resolve_deps "$lib" "$ROOTFS_DIR"
    done
fi

if [ -d "/usr/share/X11" ]; then
    mkdir -p "$ROOTFS_DIR/usr/share"
    cp -rP /usr/share/X11 "$ROOTFS_DIR/usr/share/"
fi

# 2. Extract Real Openbox from pre-built archive
OPENBOX_ARCHIVE="$ROOTFS_DIR/var/lib/aupkg/packages/openbox-3.6.1.tar.gz"
if [ -f "$OPENBOX_ARCHIVE" ]; then
    echo "  + Extracting pre-built Openbox package..."
    tar -xf "$OPENBOX_ARCHIVE" -C "$ROOTFS_DIR"
    # Mark openbox as installed in DB
else
    echo "  - WARNING: Openbox pre-built package not found in rootfs packages. Trying host copy."
    copy_binary "openbox" "/usr/bin"
fi

# 3. Extract and Deploy Xterm from Debian/Ubuntu package
CACHE_DIR="$PROJECT_ROOT/build/cache"
mkdir -p "$CACHE_DIR"
XTERM_DEB="$(find "$CACHE_DIR" -name "xterm_*.deb" | head -n 1)"

if [ -z "$XTERM_DEB" ] || [ ! -f "$XTERM_DEB" ]; then
    echo "  + Downloading xterm deb package..."
    (cd "$CACHE_DIR" && apt-get download xterm 2>/dev/null || true)
    XTERM_DEB="$(find "$CACHE_DIR" -name "xterm_*.deb" | head -n 1)"
fi

if [ -n "$XTERM_DEB" ] && [ -f "$XTERM_DEB" ]; then
    echo "  + Extracting downloaded xterm deb package ($XTERM_DEB)..."
    EXTRACT_DIR="$PROJECT_ROOT/build/xterm-extracted"
    mkdir -p "$EXTRACT_DIR"
    dpkg-deb -x "$XTERM_DEB" "$EXTRACT_DIR"
    
    if [ -f "$EXTRACT_DIR/usr/bin/xterm" ]; then
        echo "  + Installing xterm binary..."
        cp -L "$EXTRACT_DIR/usr/bin/xterm" "$ROOTFS_DIR/usr/bin/"
        resolve_deps "$ROOTFS_DIR/usr/bin/xterm" "$ROOTFS_DIR"
        
        # Copy terminfo or resources if present
        if [ -d "$EXTRACT_DIR/usr/share/doc/xterm" ]; then
            mkdir -p "$ROOTFS_DIR/usr/share/doc"
            cp -r "$EXTRACT_DIR/usr/share/doc/xterm" "$ROOTFS_DIR/usr/share/doc/"
        fi
    fi
else
    echo "  - WARNING: xterm.deb not found. Trying host copy."
    copy_binary "xterm" "/usr/bin"
fi

# 4. Copy display utilities
DISPLAY_UTILS=(xrandr xdpyinfo xauth xmodmap xinit startx xsetroot)
for util in "${DISPLAY_UTILS[@]}"; do
    copy_binary "$util" "/usr/bin"
done

# 5. Copy minimal fonts set
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

# 6. Configure Xorg configuration for QEMU
echo "  + Creating /etc/X11/xorg.conf for QEMU..."
mkdir -p "$ROOTFS_DIR/etc/X11"
cat > "$ROOTFS_DIR/etc/X11/xorg.conf" << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "fbdev"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Card0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1280x720" "1024x768" "800x600"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen "Screen0"
EndSection
EOF

# 7. Update start_desktop.sh to be a real working script
echo "  + Re-writing start_desktop script in rootfs..."
mkdir -p "$ROOTFS_DIR/bin"
cat > "$ROOTFS_DIR/bin/start_desktop.sh" << 'EOF'
#!/bin/sh
# Start X11 desktop session
export DISPLAY=:0
export HOME=/root
export USER=root
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export LD_LIBRARY_PATH=/lib:/usr/lib:/usr/lib/$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Start Xorg with fbdev driver
echo "Starting Xorg Display Server..."
Xorg :0 -config /etc/X11/xorg.conf -logfile /var/log/Xorg.0.log &
XORG_PID=$!
sleep 2

# Set a blue background
xsetroot -solid '#1e3a5f' 2>/dev/null

# Start window manager
if command -v openbox >/dev/null 2>&1; then
    echo "Starting Openbox Window Manager..."
    openbox &
elif command -v i3 >/dev/null 2>&1; then
    echo "Starting i3 Window Manager..."
    i3 &
fi

# Start terminal
if command -v xterm >/dev/null 2>&1; then
    echo "Starting xterm terminal..."
    xterm -geometry 120x40 -fa 'Monospace:size=11' -title 'AULinux Terminal' &
fi

echo "Desktop started. Press Ctrl+C to quit."
wait $XORG_PID
EOF
chmod +x "$ROOTFS_DIR/bin/start_desktop.sh"
ln -sf start_desktop.sh "$ROOTFS_DIR/bin/start_desktop" 2>/dev/null || true

# 8. Create a separate fragment for the desktop service
echo "  + Writing desktop_service_fragment.conf..."
cat > "$PROJECT_ROOT/scripts/desktop_service_fragment.conf" << 'EOF'
[desktop]
Exec=/bin/start_desktop
Type=oneshot
After=shell
Restart=never
EOF

# 9. Register openbox, xorg-server, libinput as installed in repo.db
REPO_DB="$ROOTFS_DIR/var/lib/aupkg/repo.db"
if [ -f "$REPO_DB" ]; then
    echo "  + Updating package registry repo.db..."
    python3 - <<EOF
import json
repo_path = "$REPO_DB"
try:
    with open(repo_path, 'r') as f:
        db = json.load(f)
except Exception:
    db = {}

# Set openbox, xorg-server, libinput, libdrm to installed = True since we deployed them
for pkg in ["openbox", "xorg-server", "libinput", "libdrm", "xf86-video-fbdev", "mesa"]:
    if pkg in db:
        db[pkg]["installed"] = True
        db[pkg]["real_package"] = True

with open(repo_path, 'w') as f:
    json.dump(db, f, indent=2)
print("  + repo.db updated successfully.")
EOF
fi

echo "[Phase 4] COMPLETE."
