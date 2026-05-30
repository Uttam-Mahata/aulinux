#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  AULinux Phase 1 Integration: Real CLI Development Tools
# ══════════════════════════════════════════════════════════════════════

set -e
ROOTFS_DIR="${1:-}"

if [ -z "$ROOTFS_DIR" ]; then
    echo "ERROR: ROOTFS_DIR argument is required" >&2
    exit 1
fi

echo "[Phase 1] Integrating real CLI dev tools into $ROOTFS_DIR..."

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
        # Try common paths if not in PATH
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

# 1. Ensure ld-linux exists
_gnu_triple="$(gcc -dumpmachine 2>/dev/null || dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "x86_64-linux-gnu")"
case "$(uname -m)" in
    x86_64)  _ld_path="/lib64/ld-linux-x86-64.so.2"; _ld_name="ld-linux-x86-64.so.2" ;;
    aarch64) _ld_path="/lib/ld-linux-aarch64.so.1";  _ld_name="ld-linux-aarch64.so.1" ;;
    armv7l)  _ld_path="/lib/ld-linux-armhf.so.3";    _ld_name="ld-linux-armhf.so.3"   ;;
    *)       _ld_path="$(find /lib64 /lib -maxdepth 1 -name 'ld-linux*.so*' 2>/dev/null | head -1)"
             _ld_name="$(basename "$_ld_path")" ;;
esac
mkdir -p "$ROOTFS_DIR/lib64"
[ -f "$_ld_path" ] && cp -L "$_ld_path" "$ROOTFS_DIR/lib64/" || true
mkdir -p "$ROOTFS_DIR/lib/$_gnu_triple"
ln -sf "$_ld_path" "$ROOTFS_DIR/lib/$_ld_name" 2>/dev/null || true

# 2. Copy binaries to /usr/bin
CLI_BINARIES=(git curl wget vim nano rsync less find grep sed awk diff patch which)
for bin in "${CLI_BINARIES[@]}"; do
    copy_binary "$bin" "/usr/bin"
done

# 3. Copy essential shells/utils to /bin if not already present
copy_binary "bash" "/bin"
copy_binary "grep" "/bin"
copy_binary "sed" "/bin"
copy_binary "awk" "/bin"
copy_binary "less" "/bin"

# 4. Create profile and configuration files
echo "  + Configuring profile.d/devtools.sh..."
mkdir -p "$ROOTFS_DIR/etc/profile.d"
cat > "$ROOTFS_DIR/etc/profile.d/devtools.sh" << 'EOF'
#!/bin/sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export GIT_AUTHOR_NAME="AULinux Developer"
export GIT_COMMITTER_NAME="AULinux Developer"
export GIT_AUTHOR_EMAIL="dev@aulinux.org"
export GIT_COMMITTER_EMAIL="dev@aulinux.org"
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
EOF
chmod +x "$ROOTFS_DIR/etc/profile.d/devtools.sh"

echo "  + Configuring /etc/gitconfig..."
cat > "$ROOTFS_DIR/etc/gitconfig" << 'EOF'
[user]
	name = AULinux Developer
	email = dev@aulinux.org
[core]
	editor = vim
	pager = less
[color]
	ui = true
EOF

# 5. Update repo.db package registry if it exists
REPO_DB="$ROOTFS_DIR/var/lib/aupkg/repo.db"
if [ -f "$REPO_DB" ]; then
    echo "  + Updating package registry repo.db..."
    python3 - <<EOF
import json
import os

repo_path = "$REPO_DB"
try:
    with open(repo_path, 'r') as f:
        db = json.load(f)
except Exception as e:
    print("Warning: failed to load repo.db:", e)
    db = {}

packages_to_update = {
    "git": {"description": "Real Git version control system", "url": "file:///usr/bin/git", "version": "2.43.0", "installed": False},
    "curl": {"description": "Real Curl command line tool", "url": "file:///usr/bin/curl", "version": "8.5.0", "installed": False},
    "wget": {"description": "Real Wget command line tool", "url": "file:///usr/bin/wget", "version": "1.21.4", "installed": False},
    "vim": {"description": "Real Vim text editor", "url": "file:///usr/bin/vim", "version": "9.1.0", "installed": False}
}

for name, info in packages_to_update.items():
    if name in db:
        db[name]["url"] = info["url"]
        db[name]["installed"] = info["installed"]
        db[name]["description"] = info["description"]
        db[name]["real_package"] = True
    else:
        db[name] = {
            "name": name,
            "version": info["version"],
            "description": info["description"],
            "maintainer": "AULinux Core Team",
            "architecture": "x86_64",
            "installed_size": 2048000,
            "dependencies": [],
            "optional_deps": [],
            "conflicts": [],
            "provides": [],
            "url": info["url"],
            "license": "GPL",
            "installed": info["installed"],
            "install_date": 0,
            "files": [],
            "real_package": True
        }

with open(repo_path, 'w') as f:
    json.dump(db, f, indent=2)
print("  + repo.db updated successfully.")
EOF
fi

echo "[Phase 1] COMPLETE."
