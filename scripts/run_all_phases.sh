#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  AULinux Phase Integration Script
#  Runs all phase install scripts in order during make_rootfs.sh
#  Called with: source scripts/run_all_phases.sh "$ROOTFS_DIR"
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail
ROOTFS_DIR="${1:-${ROOTFS_DIR:-}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
CACHE_DIR="$PROJECT_ROOT/build/cache"

mkdir -p "$CACHE_DIR"

if [ -z "$ROOTFS_DIR" ]; then
    echo "[phases] ERROR: ROOTFS_DIR not set" >&2
    exit 1
fi

run_phase() {
    local num="$1"
    local script="$SCRIPTS_DIR/$2"
    local desc="$3"

    echo ""
    echo "══════════════════════════════════════════════"
    echo "  Phase $num: $desc"
    echo "══════════════════════════════════════════════"

    if [ ! -f "$script" ]; then
        echo "[Phase $num] SKIP — script not found: $script"
        return 0
    fi

    bash "$script" "$ROOTFS_DIR" 2>&1 | sed "s/^/  [P$num] /"
    echo "[Phase $num] ✅ $desc complete"
}

run_phase 1 "install_phase1_cli.sh"      "Real CLI tools (git, curl, vim, wget...)"
run_phase 2 "install_phase2_ssh.sh"      "Real OpenSSH (ssh, sshd, scp)"
run_phase 3 "install_phase3_devruntime.sh" "Dev runtime (Neovim, Node.js, Python3)"
run_phase 4 "install_phase4_desktop.sh"  "X11 Desktop (Xorg, WM, xterm)"
run_phase 5 "install_phase5_browser_audio.sh" "Browser (Firefox) + Audio (PipeWire)"

echo ""
echo "══════════════════════════════════════════════"
echo "  All phases complete ✅"
echo "══════════════════════════════════════════════"
echo ""
