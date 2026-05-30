#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  AULinux Phase 2 Integration: Real OpenSSH (Client + Server)
# ══════════════════════════════════════════════════════════════════════

set -e
ROOTFS_DIR="${1:-}"

if [ -z "$ROOTFS_DIR" ]; then
    echo "ERROR: ROOTFS_DIR argument is required" >&2
    exit 1
fi

echo "[Phase 2] Integrating real OpenSSH into $ROOTFS_DIR..."

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

# 1. Copy SSH binaries from the host
mkdir -p "$ROOTFS_DIR/usr/bin"
mkdir -p "$ROOTFS_DIR/usr/sbin"
mkdir -p "$ROOTFS_DIR/usr/lib/openssh"

BINARIES=(
    "/usr/bin/ssh"
    "/usr/bin/scp"
    "/usr/sbin/sshd"
)

for bin in "${BINARIES[@]}"; do
    if [ -f "$bin" ]; then
        echo "  + Copying $bin..."
        cp -L "$bin" "$ROOTFS_DIR$(dirname "$bin")/"
        resolve_deps "$bin" "$ROOTFS_DIR"
    else
        echo "  - WARNING: $bin not found on host"
    fi
done

# Copy OpenSSH helper files
OPENSSH_HELPERS=(
    "/usr/lib/openssh/sftp-server"
    "/usr/lib/openssh/ssh-keysign"
    "/usr/lib/openssh/sshd-session"
    "/usr/lib/openssh/sshd-auth"
)

for helper in "${OPENSSH_HELPERS[@]}"; do
    if [ -f "$helper" ]; then
        echo "  + Copying OpenSSH helper: $helper..."
        cp -L "$helper" "$ROOTFS_DIR/usr/lib/openssh/"
        resolve_deps "$helper" "$ROOTFS_DIR"
    fi
done

# 2. Configure SSH directory & configs
mkdir -p "$ROOTFS_DIR/etc/ssh"
echo "  + Creating /etc/ssh/sshd_config..."
cat > "$ROOTFS_DIR/etc/ssh/sshd_config" << 'EOF'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords yes
PrintMotd yes
Subsystem sftp /usr/lib/openssh/sftp-server
PidFile /run/sshd.pid
UsePAM no
X11Forwarding yes
EOF

echo "  + Creating /etc/ssh/ssh_config..."
cat > "$ROOTFS_DIR/etc/ssh/ssh_config" << 'EOF'
Host *
    SendEnv LANG LC_*
    HashKnownHosts yes
    GSSAPIAuthentication yes
EOF

# 3. Privilege separation directory (REQUIRED by sshd)
mkdir -p "$ROOTFS_DIR/var/empty"
chmod 755 "$ROOTFS_DIR/var/empty"

# 4. Host key generation script
echo "  + Creating host key generation script..."
cat > "$ROOTFS_DIR/etc/ssh/generate_host_keys.sh" << 'EOF'
#!/bin/sh
set -eu
mkdir -p /etc/ssh
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH Host RSA key..."
    ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
fi
if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
    echo "Generating SSH Host ECDSA key..."
    ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ""
fi
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    echo "Generating SSH Host ED25519 key..."
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
fi
chmod 600 /etc/ssh/ssh_host_*_key
chmod 644 /etc/ssh/ssh_host_*_key.pub
EOF
chmod +x "$ROOTFS_DIR/etc/ssh/generate_host_keys.sh"

# Ensure we have ssh-keygen binary copied so it can generate keys
ssh_keygen_path="$(which ssh-keygen 2>/dev/null || true)"
if [ -n "$ssh_keygen_path" ] && [ -f "$ssh_keygen_path" ]; then
    cp -L "$ssh_keygen_path" "$ROOTFS_DIR/usr/bin/"
    resolve_deps "$ssh_keygen_path" "$ROOTFS_DIR"
fi

# 5. Create a minimal pam config for sshd in case it wants it
mkdir -p "$ROOTFS_DIR/etc/pam.d"
cat > "$ROOTFS_DIR/etc/pam.d/sshd" << 'EOF'
auth       required     pam_permit.so
account    required     pam_permit.so
session    required     pam_permit.so
EOF

# 6. Add PAM permit library if PAM is resolved
_gnu_triple="$(gcc -dumpmachine 2>/dev/null || dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "x86_64-linux-gnu")"
pam_permit_path="/lib/$_gnu_triple/security/pam_permit.so"
if [ -f "$pam_permit_path" ]; then
    mkdir -p "$ROOTFS_DIR/lib/$_gnu_triple/security"
    cp -L "$pam_permit_path" "$ROOTFS_DIR/lib/$_gnu_triple/security/"
    resolve_deps "$pam_permit_path" "$ROOTFS_DIR"
fi

# 7. Add OpenSSH/sshd to repo.db
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

db["openssh"] = {
    "name": "openssh",
    "version": "9.6p1",
    "description": "Real OpenSSH client and daemon server",
    "maintainer": "AULinux Core Team",
    "architecture": "x86_64",
    "installed_size": 4096000,
    "dependencies": [],
    "optional_deps": [],
    "conflicts": [],
    "provides": [],
    "url": "file:///usr/sbin/sshd",
    "license": "BSD",
    "installed": True,
    "install_date": 1780109466,
    "files": ["/usr/bin/ssh", "/usr/bin/scp", "/usr/sbin/sshd", "/etc/ssh/sshd_config"],
    "real_package": True
}

with open(repo_path, 'w') as f:
    json.dump(db, f, indent=2)
print("  + repo.db updated successfully.")
EOF
fi

echo "[Phase 2] COMPLETE."
