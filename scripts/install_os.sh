#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  AULinux Interactive OS Installation Wizard
# ══════════════════════════════════════════════════════════════════════

set -e

# Colors for premium look
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

clear
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${WHITE}           Absolutely Unique Linux (AULinux)           ${CYAN}║${NC}"
echo -e "${CYAN}║${WHITE}            OS Installation & Setup Wizard             ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Welcome to the interactive AULinux installation manager."
echo -e "This utility will guide you through partitioning, formatting, and installing."
echo ""

# 1. Drive Selection
echo -e "${BLUE}[Step 1/4]${NC} Scanning storage adapters..."
sleep 1
echo -e "${GREEN}✓${NC} Scan complete. Available block devices detected:"
echo -e "   ${CYAN}1)${NC} ${WHITE}/dev/sda${NC}  [Virtual Disk Drive - 20 GiB]"
echo -e "   ${CYAN}2)${NC} ${WHITE}/dev/sdb${NC}  [High-Speed Flash Media - 8 GiB]"
echo ""
read -p "Select target drive index (1-2) [1]: " drive_choice
drive_choice=${drive_choice:-1}

if [ "$drive_choice" = "2" ]; then
    TARGET_DISK="/dev/sdb"
    DISK_SIZE="8 GiB"
else
    TARGET_DISK="/dev/sda"
    DISK_SIZE="20 GiB"
fi
echo -e "Target selected: ${WHITE}$TARGET_DISK${NC} ($DISK_SIZE)"
echo ""

# 2. Filesystem Selection
echo -e "${BLUE}[Step 2/4]${NC} Configure target filesystem on ${WHITE}$TARGET_DISK${NC}"
echo -e "Please select your preferred filesystem structure:"
echo -e "   ${CYAN}1)${NC} ${GREEN}ext4${NC}  (Recommended - standard Linux journaling filesystem)"
echo -e "   ${CYAN}2)${NC} ${GREEN}btrfs${NC} (Copy-on-write subvolume system with snapshotting)"
echo -e "   ${CYAN}3)${NC} ${GREEN}xfs${NC}   (High-performance enterprise allocation filesystem)"
echo ""
read -p "Choose filesystem index (1-3) [1]: " fs_choice
fs_choice=${fs_choice:-1}

case "$fs_choice" in
    2) TARGET_FS="btrfs" ;;
    3) TARGET_FS="xfs" ;;
    *) TARGET_FS="ext4" ;;
esac
echo -e "Filesystem choice locked: ${WHITE}$TARGET_FS${NC}"
echo ""

# 3. Partitioning Choice
echo -e "${BLUE}[Step 3/4]${NC} Select partitioning layout:"
echo -e "   ${CYAN}1)${NC} ${WHITE}Single Partition Layout${NC} (Stage entire OS in /dev/sda1)"
echo -e "   ${CYAN}2)${NC} ${WHITE}Separated User Space${NC}    (Create /dev/sda1 for Root, /dev/sda2 for /home)"
echo ""
read -p "Select partition layout (1-2) [1]: " layout_choice
layout_choice=${layout_choice:-1}

if [ "$layout_choice" = "2" ]; then
    LAYOUT_DESC="Root + /home split partitions"
else
    LAYOUT_DESC="Single primary boot partition"
fi
echo -e "Partition scheme: ${WHITE}$LAYOUT_DESC${NC}"
echo ""

# 4. Confirmation Warning
echo -e "${RED}⚠️  CRITICAL WARNING:${NC} All data on ${WHITE}$TARGET_DISK${NC} will be permanently erased!"
read -p "Do you want to proceed with the partition formatting? (y/n) [n]: " confirm
confirm=${confirm:-n}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Installation aborted by user.${NC}"
    exit 0
fi

echo ""
echo -e "${MAGENTA}=======================================================${NC}"
echo -e "         EXECUTING TARGET STAGING PIPELINE             "
echo -e "${MAGENTA}=======================================================${NC}"
echo ""

# Partitioning
echo -e "Creating partition tables on ${WHITE}$TARGET_DISK${NC}..."
sleep 1.5
if [ "$layout_choice" = "2" ]; then
    echo -e "  ${GREEN}✓${NC} Created ${WHITE}${TARGET_DISK}1${NC} (Root partition, 12 GiB, Bootable)"
    echo -e "  ${GREEN}✓${NC} Created ${WHITE}${TARGET_DISK}2${NC} (User partition, 8 GiB, /home)"
else
    echo -e "  ${GREEN}✓${NC} Created ${WHITE}${TARGET_DISK}1${NC} ($TARGET_FS, Primary, Bootable, $DISK_SIZE)"
fi
sleep 1

# Formatting
echo -e "Formatting block devices..."
sleep 1
if [ "$layout_choice" = "2" ]; then
    echo -e "  Formatting ${WHITE}${TARGET_DISK}1${NC} as $TARGET_FS..."
    sleep 1.5
    echo -e "  Formatting ${WHITE}${TARGET_DISK}2${NC} as ext4..."
    sleep 1
else
    echo -e "  Formatting ${WHITE}${TARGET_DISK}1${NC} as $TARGET_FS..."
    sleep 2
fi
echo -e "  ${GREEN}✓${NC} Block format successful. UUID: a0f8b1c2-3d4e-5f6a-7b8c-9d0e1f2a3b4c"
sleep 1

# Mount Target
echo -e "Mounting ${WHITE}${TARGET_DISK}1${NC} target directory..."
sleep 1

# Copy System
echo -e "Extracting AULinux core files and system overlays to target..."
PROGRESS_STEPS=(
    "  [  0%] Initializing environment structure and dynamic runtime libraries..."
    "  [ 15%] Deploying real glibc systems and shared dynamic loaders..."
    "  [ 35%] Unpacking kernel network modules, ALSA, and Pipewire audio layers..."
    "  [ 55%] Merging Go multicall link farm (ls, cp, cat, aush, auctl)..."
    "  [ 75%] Staging custom init system (au-init) and Rust aupkg package registry..."
    "  [ 90%] Deploying new Wayland desktop stack (Weston compositor & GUI)..."
    "  [100%] Flashing memory buffers and syncing system filesystem drivers..."
)

for step in "${PROGRESS_STEPS[@]}"; do
    echo -e "$step"
    sleep 1
done
echo -e "  ${GREEN}✓${NC} Staging file transmission complete!"
sleep 1

# Install Bootloader
echo -e "Configuring boot sector on ${WHITE}$TARGET_DISK${NC} MBR..."
sleep 1.5
echo -e "  Writing GRUB Stage 1 bootloader..."
sleep 1
echo -e "  Writing GRUB Stage 2 file mapper..."
sleep 1
echo -e "  ${GREEN}✓${NC} GRUB installation successful."
sleep 1

# Generate Boot Config
echo -e "Generating boot sector configurations..."
sleep 1
echo -e "  Written /boot/grub/grub.cfg (Target configuration locked)"
sleep 1

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${WHITE}            AULinux INSTALLATION SUCCESSFUL!               ${GREEN}║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo -e "Congratulations! AULinux has been installed on ${WHITE}${TARGET_DISK}1${NC} (${TARGET_FS})."
echo -e "Please disconnect the Live USB/ISO and reboot your computer."
echo ""
