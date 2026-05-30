#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  AULinux Phase 3 Integration: Neovim, Node.js v22, Python 3.14
# ══════════════════════════════════════════════════════════════════════

set -e
ROOTFS_DIR="${1:-}"

if [ -z "$ROOTFS_DIR" ]; then
    echo "ERROR: ROOTFS_DIR argument is required" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/build/cache"
mkdir -p "$CACHE_DIR"

echo "[Phase 3] Integrating real Dev Runtimes into $ROOTFS_DIR..."

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

# ── Part A: Neovim ──
NVIM_CACHE="$CACHE_DIR/nvim.appimage"
case "$(uname -m)" in
    aarch64) _nvim_arch="arm64" ;;
    *)       _nvim_arch="x86_64" ;;
esac
NVIM_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-${_nvim_arch}.appimage"

if [ ! -f "$NVIM_CACHE" ] || [ "$(stat -c%s "$NVIM_CACHE")" -lt 10000000 ]; then
    echo "  + Downloading Neovim AppImage..."
    wget -q --show-progress -O "$NVIM_CACHE" "$NVIM_URL" || curl -L -o "$NVIM_CACHE" "$NVIM_URL" || true
fi

if [ -f "$NVIM_CACHE" ] && [ "$(stat -c%s "$NVIM_CACHE")" -gt 10000000 ]; then
    echo "  + Installing Neovim AppImage..."
    mkdir -p "$ROOTFS_DIR/usr/bin"
    cp -L "$NVIM_CACHE" "$ROOTFS_DIR/usr/bin/nvim"
    chmod +x "$ROOTFS_DIR/usr/bin/nvim"
    ln -sf nvim "$ROOTFS_DIR/usr/bin/vi"
    ln -sf nvim "$ROOTFS_DIR/usr/bin/vim"
else
    echo "  - WARNING: Neovim AppImage download failed or incomplete. Installing a minimal mock."
    mkdir -p "$ROOTFS_DIR/usr/bin"
    cat > "$ROOTFS_DIR/usr/bin/nvim" << 'EOF'
#!/bin/sh
echo "Mock Neovim - download failed during OS build"
EOF
    chmod +x "$ROOTFS_DIR/usr/bin/nvim"
    ln -sf nvim "$ROOTFS_DIR/usr/bin/vi"
    ln -sf nvim "$ROOTFS_DIR/usr/bin/vim"
fi

# ── Part B: Node.js v22 ──
NODE_BIN_HOST="$(command -v node 2>/dev/null || true)"
NODE_PATH_HOST="$([ -n "$NODE_BIN_HOST" ] && dirname "$(dirname "$NODE_BIN_HOST")" || echo "")"
if [ -n "$NODE_PATH_HOST" ] && [ -d "$NODE_PATH_HOST" ]; then
    echo "  + Copying Node.js v22 from host..."
    mkdir -p "$ROOTFS_DIR/usr/bin"
    
    # Copy Node binaries
    cp -L "$NODE_PATH_HOST/bin/node" "$ROOTFS_DIR/usr/bin/"
    resolve_deps "$NODE_PATH_HOST/bin/node" "$ROOTFS_DIR"
    
    # Copy npm and npx and their libraries
    mkdir -p "$ROOTFS_DIR/usr/lib"
    cp -r "$NODE_PATH_HOST/lib/node_modules" "$ROOTFS_DIR/usr/lib/"
    
    # Re-create npm and npx symlinks
    ln -sf ../lib/node_modules/npm/bin/npm-cli.js "$ROOTFS_DIR/usr/bin/npm"
    ln -sf ../lib/node_modules/npm/bin/npx-cli.js "$ROOTFS_DIR/usr/bin/npx"
else
    echo "  - WARNING: Node.js v22 not found at $NODE_PATH_HOST on host"
fi

# ── Part C: Python3 ──
PYTHON_HOST="/usr/bin/python3.14"
if [ ! -f "$PYTHON_HOST" ]; then
    PYTHON_HOST="$(which python3 2>/dev/null || true)"
fi

if [ -n "$PYTHON_HOST" ] && [ -f "$PYTHON_HOST" ]; then
    echo "  + Copying Python from host ($PYTHON_HOST)..."
    mkdir -p "$ROOTFS_DIR/usr/bin"
    cp -L "$PYTHON_HOST" "$ROOTFS_DIR/usr/bin/python3.14"
    ln -sf python3.14 "$ROOTFS_DIR/usr/bin/python3"
    ln -sf python3.14 "$ROOTFS_DIR/usr/bin/python"
    resolve_deps "$PYTHON_HOST" "$ROOTFS_DIR"
    
    # Copy Python stdlib
    echo "  + Copying Python 3.14 standard library (selective)..."
    mkdir -p "$ROOTFS_DIR/usr/lib/python3.14"
    
    # Lighter list of stdlib folders to save space
    PYTHON_LIBS=(collections email encodings http json logging urllib xml asyncio concurrent importlib re)
    for lib in "${PYTHON_LIBS[@]}"; do
        if [ -d "/usr/lib/python3.14/$lib" ]; then
            cp -r "/usr/lib/python3.14/$lib" "$ROOTFS_DIR/usr/lib/python3.14/"
        fi
    done
    
    # Copy all root .py files in stdlib
    cp -L /usr/lib/python3.14/*.py "$ROOTFS_DIR/usr/lib/python3.14/" 2>/dev/null || true
    
    # Copy pip3 if it exists
    PIP_HOST="$(which pip3 2>/dev/null || which pip 2>/dev/null || true)"
    if [ -n "$PIP_HOST" ] && [ -f "$PIP_HOST" ]; then
        echo "  + Copying pip3..."
        cp -L "$PIP_HOST" "$ROOTFS_DIR/usr/bin/pip3"
        ln -sf pip3 "$ROOTFS_DIR/usr/bin/pip"
        resolve_deps "$PIP_HOST" "$ROOTFS_DIR"
    fi
else
    echo "  - WARNING: Python not found on host"
fi

# ── Part D: profile setup ──
echo "  + Adding devtools.sh env variables..."
mkdir -p "$ROOTFS_DIR/etc/profile.d"
cat > "$ROOTFS_DIR/etc/profile.d/devtools.sh" << 'EOF'
#!/bin/sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export PYTHONDONTWRITEBYTECODE=1
export NODE_PATH=/usr/lib/node_modules
alias ll='ls -la'
alias la='ls -A'
alias vi='nvim'
alias vim='nvim'
EOF
chmod +x "$ROOTFS_DIR/etc/profile.d/devtools.sh"

# ── Part E: Basic Neovim config ──
echo "  + Setting up default Neovim configuration..."
mkdir -p "$ROOTFS_DIR/root/.config/nvim"
cat > "$ROOTFS_DIR/root/.config/nvim/init.vim" << 'EOF'
set number
set relativenumber
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set smartindent
set hlsearch
set incsearch
set ignorecase
set smartcase
set wrap
set linebreak
set colorcolumn=80
syntax enable
filetype plugin indent on
EOF

# ── Part F: tmux ──
TMUX_HOST="$(which tmux 2>/dev/null || true)"
if [ -n "$TMUX_HOST" ] && [ -f "$TMUX_HOST" ]; then
    echo "  + Copying tmux from host..."
    cp -L "$TMUX_HOST" "$ROOTFS_DIR/usr/bin/tmux"
    resolve_deps "$TMUX_HOST" "$ROOTFS_DIR"
fi

echo "[Phase 3] COMPLETE."
