#!/bin/bash
set -e

PROJECT_ROOT=$(pwd)
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS_DIR="$PROJECT_ROOT/rootfs"
REPO_DIR="$ROOTFS_DIR/var/lib/aupkg"
PACKAGES_DIR="$REPO_DIR/packages"

echo "Populating Graphics Repository in rootfs..."

# Ensure target directories exist in rootfs
mkdir -p "$REPO_DIR"
mkdir -p "$PACKAGES_DIR"

# Create a temporary directory for packaging
TMP_DIR="$PROJECT_ROOT/pkg_tmp_graphics"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Helper function to create mock package structure and archive it
# Arguments: name, version, description, license, dependencies (as comma-separated string)
create_graphics_package() {
    local name=$1
    local version=$2
    local desc=$3
    local lic=$4
    local deps=$5

    echo "Building graphics package: $name ($version)..."
    local pkg_src="$TMP_DIR/$name"
    mkdir -p "$pkg_src"

    # Create mock directories and files depending on the package
    if [ "$name" = "libinput" ]; then
        mkdir -p "$pkg_src/usr/lib" "$pkg_src/usr/bin"
        echo "#!/bin/sh" > "$pkg_src/usr/bin/libinput-list-devices"
        echo "echo 'Mock Input Devices list'" >> "$pkg_src/usr/bin/libinput-list-devices"
        chmod +x "$pkg_src/usr/bin/libinput-list-devices"
        echo "/* Mock shared library */" > "$pkg_src/usr/lib/libinput.so.10"
    elif [ "$name" = "xorg-server" ]; then
        mkdir -p "$pkg_src/usr/bin" "$pkg_src/etc/X11"
        echo "#!/bin/sh" > "$pkg_src/usr/bin/Xorg"
        echo "echo 'Mock X.Org Server running'" >> "$pkg_src/usr/bin/Xorg"
        chmod +x "$pkg_src/usr/bin/Xorg"
        ln -sf Xorg "$pkg_src/usr/bin/xorg-server"
        echo "# Mock X11 configuration" > "$pkg_src/etc/X11/xorg.conf"
    elif [ "$name" = "xf86-video-fbdev" ]; then
        mkdir -p "$pkg_src/usr/lib/xorg/modules/drivers"
        echo "/* Mock fbdev driver */" > "$pkg_src/usr/lib/xorg/modules/drivers/fbdev_drv.so"
    elif [ "$name" = "openbox" ]; then
        mkdir -p "$pkg_src/usr/bin" "$pkg_src/etc/xdg/openbox"
        echo "#!/bin/sh" > "$pkg_src/usr/bin/openbox"
        echo "echo 'Mock Openbox Window Manager running'" >> "$pkg_src/usr/bin/openbox"
        chmod +x "$pkg_src/usr/bin/openbox"
        echo "<openbox_config></openbox_config>" > "$pkg_src/etc/xdg/openbox/rc.xml"
    fi

    # Package into a .tar.gz archive directly
    local archive_name="$name-$version.tar.gz"
    local archive_path="$PACKAGES_DIR/$archive_name"
    
    cd "$pkg_src"
    tar -czf "$archive_path" .
    cd "$PROJECT_ROOT"

    # Get installed size in bytes
    local size=$(du -sb "$pkg_src" | cut -f1)

    # Let's save metadata for this package to be merged into repo.db
    # We will write temporary JSON files to merge them later using Python
    cat > "$TMP_DIR/$name.json" <<EOF
{
  "name": "$name",
  "version": "$version",
  "description": "$desc",
  "maintainer": "AuLinux Graphics Team",
  "architecture": "$(uname -m)",
  "installed_size": $size,
  "dependencies": [$(echo "$deps" | sed 's/,/", "/g' | sed 's/^/&"/;s/$/&"/' | sed 's/""//g')],
  "optional_deps": [],
  "conflicts": [],
  "provides": [],
  "url": "file:///var/lib/aupkg/packages/$archive_name",
  "license": "$lic",
  "installed": false,
  "install_date": 0,
  "files": []
}
EOF
}

# Create each of the four graphics packages
create_graphics_package "libinput" "1.23.0" "Library to handle input devices in Wayland compositors and X servers" "MIT" ""
create_graphics_package "xorg-server" "21.1.8" "X.Org X Server" "MIT" "libinput"
create_graphics_package "xf86-video-fbdev" "0.5.0" "X.Org X server fbdev display driver" "MIT" "xorg-server"
create_graphics_package "openbox" "3.6.1" "Standards-compliant, lightweight window manager" "GPL-2.0" "xorg-server"

# Generate repo.db by merging the JSONs
echo "Generating repo.db registry..."
python3 -c "
import json, glob, os
db = {}
if os.path.exists('$REPO_DIR/repo.db'):
    try:
        with open('$REPO_DIR/repo.db') as f:
            db = json.load(f)
    except:
        pass
for f in glob.glob('$TMP_DIR/*.json'):
    with open(f) as jf:
        data = json.load(jf)
        db[data['name']] = data
with open('$REPO_DIR/repo.db', 'w') as out:
    json.dump(db, out, indent=2)
"

# Build extra GUI and Library packages and append them to repo.db registry
if [ -f "$PROJECT_ROOT/scripts/build_gui_packages.py" ]; then
    echo "Building and registering GUI frameworks and applications..."
    python3 "$PROJECT_ROOT/scripts/build_gui_packages.py"
else
    echo "Warning: $PROJECT_ROOT/scripts/build_gui_packages.py not found!"
fi

# Build Wayland packages and append them to repo.db registry
if [ -f "$PROJECT_ROOT/scripts/build_wayland_packages.py" ]; then
    echo "Building and registering Wayland graphics stack packages..."
    python3 "$PROJECT_ROOT/scripts/build_wayland_packages.py"
else
    echo "Warning: $PROJECT_ROOT/scripts/build_wayland_packages.py not found!"
fi

# Build extra XFCE desktop packages and append them to repo.db registry
if [ -f "$PROJECT_ROOT/scripts/build_xfce_desktop_packages.py" ]; then
    echo "Building and registering XFCE desktop packages..."
    python3 "$PROJECT_ROOT/scripts/build_xfce_desktop_packages.py"
else
    echo "Warning: $PROJECT_ROOT/scripts/build_xfce_desktop_packages.py not found!"
fi

# Cleanup
rm -rf "$TMP_DIR"
echo "Graphics repository successfully created at $REPO_DIR"
ls -la "$REPO_DIR"
