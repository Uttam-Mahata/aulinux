#!/bin/bash
set -e

PROJECT_ROOT=$(pwd)
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS_DIR="$PROJECT_ROOT/rootfs"

echo "Creating rootfs in $ROOTFS_DIR..."

# Create directories
mkdir -p "$ROOTFS_DIR"/{bin,sbin,etc,usr,var,proc,sys,dev,tmp,run,boot,home,root,lib,lib64}
mkdir -p "$ROOTFS_DIR"/etc/aulinux
mkdir -p "$ROOTFS_DIR"/usr/{bin,sbin,lib}
chmod 1777 "$ROOTFS_DIR/tmp"

# Copy essential shared libraries and dynamic loader
echo "Copying shared libraries..."
cp -L /lib64/ld-linux-x86-64.so.2 "$ROOTFS_DIR/lib64/"
cp -L /lib/x86_64-linux-gnu/libc.so.6 "$ROOTFS_DIR/lib/"
cp -L /lib/x86_64-linux-gnu/libm.so.6 "$ROOTFS_DIR/lib/"
cp -L /lib/x86_64-linux-gnu/libresolv.so.2 "$ROOTFS_DIR/lib/"
cp -L /lib/x86_64-linux-gnu/librt.so.1 "$ROOTFS_DIR/lib/"
cp -L /lib/x86_64-linux-gnu/libdl.so.2 "$ROOTFS_DIR/lib/"
cp -L /lib/x86_64-linux-gnu/libpthread.so.0 "$ROOTFS_DIR/lib/"

# Copy extra libraries required by host utilities (like tar)
cp -L /usr/lib/x86_64-linux-gnu/libacl.so.1 "$ROOTFS_DIR/lib/"
cp -L /usr/lib/x86_64-linux-gnu/libselinux.so.1 "$ROOTFS_DIR/lib/"
cp -L /usr/lib/x86_64-linux-gnu/libpcre2-8.so.0 "$ROOTFS_DIR/lib/"

# Copy REAL Mesa / OpenGL / DRM / input libraries directly into rootfs/lib
# so graphical applications can find them immediately at boot (no aupkg install needed)
echo "Copying real Mesa/GL/DRM/input libraries..."
HLIB="/usr/lib/x86_64-linux-gnu"

# Core GL dispatcher and Mesa GLX implementation
for lib in \
    libGL.so.1.7.0 libGLX_mesa.so.0.0.0 libGLdispatch.so.0.0.0 \
    libGLESv2.so.2.1.0 libGLESv1_CM.so.1.2.0 libGLX.so.0.0.0 \
    libdrm.so.2.131.0 libdrm_intel.so.1.131.0 libdrm_amdgpu.so.1.131.0 \
    libdrm_nouveau.so.2.131.0 libdrm_radeon.so.1.131.0 \
    libpixman-1.so.0.46.4 libinput.so.10.13.0 \
    libgbm.so.1.0.0 libxcb.so.1.1.0 libffi.so.8; do
    [ -f "$HLIB/$lib" ] && cp -L "$HLIB/$lib" "$ROOTFS_DIR/lib/" && echo "  + $lib"
done

# Create canonical versioned symlinks so dynamic linker resolves them
cd "$ROOTFS_DIR/lib"
for pair in \
    "libGL.so.1:libGL.so.1.7.0" "libGLX_mesa.so.0:libGLX_mesa.so.0.0.0" \
    "libGLdispatch.so.0:libGLdispatch.so.0.0.0" \
    "libGLESv2.so.2:libGLESv2.so.2.1.0" "libGLX.so.0:libGLX.so.0.0.0" \
    "libdrm.so.2:libdrm.so.2.131.0" "libdrm_intel.so.1:libdrm_intel.so.1.131.0" \
    "libdrm_amdgpu.so.1:libdrm_amdgpu.so.1.131.0" \
    "libdrm_nouveau.so.2:libdrm_nouveau.so.2.131.0" \
    "libdrm_radeon.so.1:libdrm_radeon.so.1.131.0" \
    "libpixman-1.so.0:libpixman-1.so.0.46.4" \
    "libinput.so.10:libinput.so.10.13.0" "libgbm.so.1:libgbm.so.1.0.0"; do
    link="${pair%%:*}"; target="${pair##*:}"
    [ -f "$target" ] && [ ! -e "$link" ] && ln -sf "$target" "$link"
done
cd "$PROJECT_ROOT"

# Stage DRI hardware drivers in rootfs/lib/dri (Mesa needs LIBGL_DRIVERS_PATH)
mkdir -p "$ROOTFS_DIR/lib/dri"
for drv in swrast_dri.so kms_swrast_dri.so virtio_gpu_dri.so vkms_dri.so i915_dri.so iris_dri.so; do
    [ -f "$HLIB/dri/$drv" ] && cp "$HLIB/dri/$drv" "$ROOTFS_DIR/lib/dri/" && echo "  + dri/$drv"
done

# Copy real Xorg binary into rootfs/usr/bin
mkdir -p "$ROOTFS_DIR/usr/bin"
[ -f "/usr/bin/Xorg" ] && cp -L /usr/bin/Xorg "$ROOTFS_DIR/usr/bin/" && \
    ln -sf /usr/bin/Xorg "$ROOTFS_DIR/usr/bin/X" && echo "  + Xorg (real binary)"

# BUG FIX: Add bare libGL.so symlink (some apps look for unversioned name)
cd "$ROOTFS_DIR/lib"
[ -f "libGL.so.1" ] && [ ! -e "libGL.so" ] && ln -sf libGL.so.1 libGL.so && echo "  + libGL.so (bare symlink fixed)"
[ -f "libGLESv2.so.2" ] && [ ! -e "libGLESv2.so" ] && ln -sf libGLESv2.so.2 libGLESv2.so
[ -f "libGLdispatch.so.0" ] && [ ! -e "libGLdispatch.so" ] && ln -sf libGLdispatch.so.0 libGLdispatch.so
[ -f "libdrm.so.2" ] && [ ! -e "libdrm.so" ] && ln -sf libdrm.so.2 libdrm.so
[ -f "libinput.so.10" ] && [ ! -e "libinput.so" ] && ln -sf libinput.so.10 libinput.so
cd "$PROJECT_ROOT"

# Copy real modprobe binary (for loading kernel modules inside AULinux)
echo "Copying modprobe..."
mkdir -p "$ROOTFS_DIR/sbin"
for mb in /sbin/modprobe /usr/sbin/modprobe; do
    if [ -f "$mb" ]; then
        cp -L "$mb" "$ROOTFS_DIR/sbin/modprobe"
        # Also copy kmod symlinks: insmod, rmmod, lsmod, depmod
        for tool in insmod rmmod lsmod depmod modinfo; do
            ln -sf modprobe "$ROOTFS_DIR/sbin/$tool" 2>/dev/null || true
        done
        echo "  + modprobe (+ insmod, rmmod, lsmod, depmod, modinfo symlinks)"
        break
    fi
done

# BUG FIX: Remove stale mock mesa archive (replaced by real mesa-23.2.1)
STALE="$ROOTFS_DIR/var/lib/aupkg/packages/mesa-23.1.3.tar.gz"
[ -f "$STALE" ] && rm -f "$STALE" && echo "  + Removed stale mock mesa-23.1.3.tar.gz"

echo "Real graphics libraries installed."

# Copy real DHCP client (dhcpcd/dhclient) and dependencies
echo "Locating and copying real DHCP client..."
DHCP_CLIENT=""
if [ -f "/usr/sbin/dhcpcd" ]; then
    DHCP_CLIENT="/usr/sbin/dhcpcd"
elif [ -f "/sbin/dhcpcd" ]; then
    DHCP_CLIENT="/sbin/dhcpcd"
elif [ -f "/sbin/dhclient" ]; then
    DHCP_CLIENT="/sbin/dhclient"
elif [ -f "/usr/sbin/dhclient" ]; then
    DHCP_CLIENT="/usr/sbin/dhclient"
fi

if [ -n "$DHCP_CLIENT" ]; then
    echo "Found DHCP client at $DHCP_CLIENT. Copying to rootfs..."
    cp -L "$DHCP_CLIENT" "$ROOTFS_DIR/sbin/dhcpcd"
    chmod +x "$ROOTFS_DIR/sbin/dhcpcd"
    
    # Copy resolved library dependencies of dhcpcd
    [ -f "/usr/lib/x86_64-linux-gnu/libcrypto.so.3" ] && cp -L /usr/lib/x86_64-linux-gnu/libcrypto.so.3 "$ROOTFS_DIR/lib/"
    [ -f "/usr/lib/x86_64-linux-gnu/libz.so.1" ] && cp -L /usr/lib/x86_64-linux-gnu/libz.so.1 "$ROOTFS_DIR/lib/"
    [ -f "/usr/lib/x86_64-linux-gnu/libzstd.so.1" ] && cp -L /usr/lib/x86_64-linux-gnu/libzstd.so.1 "$ROOTFS_DIR/lib/"
    
    # Also resolve dependencies for dhclient if that was chosen
    [ -f "/lib/x86_64-linux-gnu/libdns-export.so" ] && cp -L /lib/x86_64-linux-gnu/libdns-export.so* "$ROOTFS_DIR/lib/"
    [ -f "/lib/x86_64-linux-gnu/libisc-export.so" ] && cp -L /lib/x86_64-linux-gnu/libisc-export.so* "$ROOTFS_DIR/lib/"
    
    echo "DHCP client and dependencies copied successfully."
else
    echo "Warning: No real DHCP client found on the host system."
fi

# Create symbolic link for loader in /lib as well
ln -sf /lib64/ld-linux-x86-64.so.2 "$ROOTFS_DIR/lib/ld-linux-x86-64.so.2"

# Copy essential host archiving utilities (tar and gzip)
echo "Copying archiving utilities..."
cp -L /usr/bin/tar "$ROOTFS_DIR/bin/"
cp -L /usr/bin/gzip "$ROOTFS_DIR/bin/"


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
elif [ -f "$BUILD_DIR/utils/aush" ]; then
    echo "Shell is integrated into utilities"
else
    echo "Warning: aush not found in build/"
fi

# Copy utilities
if [ -d "$BUILD_DIR/utils" ]; then
    cp -d "$BUILD_DIR/utils/"* "$ROOTFS_DIR/bin/" 2>/dev/null || true
    # Create auctl symlink (points to auutils multicall binary)
    [ -f "$ROOTFS_DIR/bin/auutils" ] && ln -sf auutils "$ROOTFS_DIR/bin/auctl" && echo "  + auctl symlink"
    echo "Installed utilities"
else
    echo "Warning: utils not found in build/"
fi

# Copy package manager
if [ -f "$BUILD_DIR/pkg-manager/aupkg" ]; then
    cp "$BUILD_DIR/pkg-manager/aupkg" "$ROOTFS_DIR/usr/bin/aupkg"
    ln -sf /usr/bin/aupkg "$ROOTFS_DIR/bin/aupkg"
    echo "Installed package manager"
else
    echo "Warning: aupkg not found in build/"
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

# Set up /etc/resolv.conf in the rootfs with standard public DNS
echo "Configuring /etc/resolv.conf with public DNS..."
cat > "$ROOTFS_DIR/etc/resolv.conf" << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Write new INI-format services.conf for au-init v2.0
echo "Configuring /etc/aulinux/services.conf (INI format, au-init v2.0)..."
cat > "$ROOTFS_DIR/etc/aulinux/services.conf" << 'EOF'
# ══════════════════════════════════════════════════════════════════════
#  AULinux Services Configuration  —  au-init v2.0 INI format
#
#  Syntax:
#    [ServiceName]         — start a new service block
#    Type=simple|target|timer|oneshot
#    Exec=<cmd> [args]     — main command
#    ExecStartPre=<cmd>    — run before Exec (must exit 0)
#    ExecStop=<cmd>        — run on stop before SIGTERM
#    After=a, b, c         — start after these services/targets are active
#    Requires=x            — hard dep: fail if x fails
#    Wants=y               — soft dep: start x but ignore failure
#    PartOf=z              — stop when z stops
#    Provides=name         — declare this service satisfies a virtual target
#    User=username         — drop privileges to this user
#    Group=groupname       — drop privileges to this group
#    Environment=KEY=val   — set environment variable
#    EnvironmentFile=/path — load environment from file
#    ListenStream=/path    — socket activation (UNIX socket)
#    Restart=always|on-failure|never
#    OnBootSec=30s         — timer: fire 30s after boot
#    OnUnitActiveSec=5m    — timer: repeat every 5 minutes
#    Unit=myservice        — timer: which service to fire
# ══════════════════════════════════════════════════════════════════════

# ── Virtual targets (synchronization points) ──────────────────────────

[network-pre.target]
Type=target

[network.target]
Type=target
After=network-pre.target

[filesystem.target]
Type=target

# ── Core networking ───────────────────────────────────────────────────

[dhcpcd]
Exec=/sbin/dhcpcd -B
After=network-pre.target
Provides=network.target
Restart=always
Environment=PATH=/sbin:/usr/sbin:/bin:/usr/bin

# ── Interactive shell ─────────────────────────────────────────────────

[shell]
Exec=/bin/aush -l
Restart=always

# ── Example: add your own services below ─────────────────────────────
#
# [sshd]
# Exec=/usr/sbin/sshd -D
# After=network.target
# Requires=network.target
# ExecStartPre=/usr/sbin/sshd -t
# ExecStop=/usr/sbin/sshd -O stop
# Restart=on-failure
# User=root
#
# [redis]
# Exec=/usr/bin/redis-server /etc/redis.conf
# After=network.target
# User=redis
# Group=redis
# Restart=on-failure
# ListenStream=/run/redis.sock
#
# [logrotate.timer]
# Type=timer
# OnBootSec=1m
# OnUnitActiveSec=1d
# Unit=logrotate
#
# [logrotate]
# Type=oneshot
# Exec=/usr/sbin/logrotate /etc/logrotate.conf
# Restart=never
EOF

# Populate local package repository with graphics packages (mock skeleton first)
if [ -f "$PROJECT_ROOT/scripts/populate_graphics_repo.sh" ]; then
    "$PROJECT_ROOT/scripts/populate_graphics_repo.sh"
else
    echo "Warning: scripts/populate_graphics_repo.sh not found."
fi

# Replace mock graphics packages with REAL compiled binaries from the host
# (overwrites xorg-server, mesa, libinput, libdrm, openbox entries in repo.db)
if [ -f "$PROJECT_ROOT/scripts/build_real_graphics_packages.py" ]; then
    echo "Extracting real graphics binaries from host (Xorg, Mesa, libdrm, libinput)..."
    python3 "$PROJECT_ROOT/scripts/build_real_graphics_packages.py"
else
    echo "Warning: scripts/build_real_graphics_packages.py not found."
fi

# Populate local package repository with networking and SSH packages
if [ -f "$PROJECT_ROOT/scripts/build_networking_packages.py" ]; then
    python3 "$PROJECT_ROOT/scripts/build_networking_packages.py"
else
    echo "Warning: scripts/build_networking_packages.py not found."
fi

# Populate local package repository with GNOME and Plasma desktop environment packages
if [ -f "$PROJECT_ROOT/scripts/build_desktop_environments.py" ]; then
    python3 "$PROJECT_ROOT/scripts/build_desktop_environments.py"
else
    echo "Warning: scripts/build_desktop_environments.py not found."
fi

# Copy start_desktop.sh to rootfs
if [ -f "$PROJECT_ROOT/scripts/start_desktop.sh" ]; then
    cp "$PROJECT_ROOT/scripts/start_desktop.sh" "$ROOTFS_DIR/bin/start_desktop.sh"
    chmod +x "$ROOTFS_DIR/bin/start_desktop.sh"
    ln -sf start_desktop.sh "$ROOTFS_DIR/bin/start_desktop"
    echo "Installed desktop startup helper script"
fi

# Copy installer script to rootfs
if [ -f "$PROJECT_ROOT/scripts/install_os.sh" ]; then
    cp "$PROJECT_ROOT/scripts/install_os.sh" "$ROOTFS_DIR/bin/au-install"
    chmod +x "$ROOTFS_DIR/bin/au-install"
    ln -sf au-install "$ROOTFS_DIR/bin/install-os"
    echo "Installed OS installation wizard"
fi

# Deploy sound and video kernel modules and run depmod
if [ -f "$PROJECT_ROOT/scripts/deploy_drivers.py" ]; then
    python3 "$PROJECT_ROOT/scripts/deploy_drivers.py"
else
    echo "Warning: scripts/deploy_drivers.py not found, skipping kernel modules deployment."
fi

# ══════════════════════════════════════════════════════════════════════
#  Run all real-binary phase install scripts (Phase 1–5)
#  Each phase copies real binaries from the host and resolves .so deps.
#  If a phase script doesn't exist yet it is silently skipped.
# ══════════════════════════════════════════════════════════════════════
if [ -f "$PROJECT_ROOT/scripts/run_all_phases.sh" ]; then
    echo ""
    echo "Running real-binary phase installers..."
    bash "$PROJECT_ROOT/scripts/run_all_phases.sh" "$ROOTFS_DIR"
else
    echo "Warning: scripts/run_all_phases.sh not found — skipping phase installers."
fi

echo "Rootfs created successfully at $ROOTFS_DIR"


