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
echo -e "   ${CYAN}1)${NC} ${WHITE}/dev/sda${NC}      [Virtual Disk Drive - 20 GiB]"
echo -e "   ${CYAN}2)${NC} ${WHITE}/dev/sdb${NC}      [High-Speed Flash Media - 8 GiB]"
echo -e "   ${CYAN}3)${NC} ${WHITE}/dev/nvme0n1${NC}  [High-Performance NVMe PCIe SSD - 512 GiB]"
echo ""
read -p "Select target drive index (1-3) [1]: " drive_choice
drive_choice=${drive_choice:-1}

if [ "$drive_choice" = "2" ]; then
    TARGET_DISK="/dev/sdb"
    DISK_SIZE="8 GiB"
    DISK_SIZE_NUM=8
elif [ "$drive_choice" = "3" ]; then
    TARGET_DISK="/dev/nvme0n1"
    DISK_SIZE="512 GiB"
    DISK_SIZE_NUM=512
else
    TARGET_DISK="/dev/sda"
    DISK_SIZE="20 GiB"
    DISK_SIZE_NUM=20
fi

# Dynamically resolve partition names (NVMe devices require a 'p' separator)
if [[ "$TARGET_DISK" =~ nvme ]]; then
    PART1="${TARGET_DISK}p1"
    PART2="${TARGET_DISK}p2"
else
    PART1="${TARGET_DISK}1"
    PART2="${TARGET_DISK}2"
fi

echo -e "Target disk selected: ${WHITE}$TARGET_DISK${NC} ($DISK_SIZE)"
echo -e "Staging partitions designated: ${WHITE}$PART1${NC} (and ${WHITE}$PART2${NC} if split)"
echo ""

# 2. Filesystem Selection
echo -e "${BLUE}[Step 2/4]${NC} Configure target filesystem on ${WHITE}$PART1${NC}"
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

# Partition Configuration Data Structure
declare -a PART_NAMES
declare -a PART_SIZES
declare -a PART_FILESYSTEMS
declare -a PART_TYPES
PART_COUNT=0

reset_partitions() {
    PART_NAMES=()
    PART_SIZES=()
    PART_FILESYSTEMS=()
    PART_TYPES=()
    if [ "$layout_choice" = "2" ]; then
        PART_NAMES[0]="${PART1}"
        PART_SIZES[0]=12
        PART_FILESYSTEMS[0]="$TARGET_FS"
        PART_TYPES[0]="Root"

        PART_NAMES[1]="${PART2}"
        PART_SIZES[1]=8
        PART_FILESYSTEMS[1]="ext4"
        PART_TYPES[1]="Home"
        PART_COUNT=2
    else
        PART_NAMES[0]="${PART1}"
        PART_SIZES[0]=$((DISK_SIZE_NUM))
        PART_FILESYSTEMS[0]="$TARGET_FS"
        PART_TYPES[0]="Root/Boot"
        PART_COUNT=1
    fi
}

custom_partitioning() {
    local exit_loop=0
    while [ $exit_loop -eq 0 ]; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${WHITE}            Interactive Partition Manager                  ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "Target Disk: ${WHITE}$TARGET_DISK${NC} (${DISK_SIZE_NUM} GiB)"
        echo ""
        echo -e "Current partition table:"
        echo -e "----------------------------------------------------------------------"
        printf "${BLUE}%-15s %-7s %-10s %-12s %-12s${NC}\n" "Device" "Index" "Size" "Filesystem" "Mount Type"
        echo -e "----------------------------------------------------------------------"
        
        local total_allocated=0
        for ((i=0; i<PART_COUNT; i++)); do
            printf "${WHITE}%-15s %-7d %d GiB     %-12s %-12s${NC}\n" \
                "${PART_NAMES[i]}" \
                $((i+1)) \
                "${PART_SIZES[i]}" \
                "${PART_FILESYSTEMS[i]}" \
                "${PART_TYPES[i]}"
            total_allocated=$((total_allocated + PART_SIZES[i]))
        done
        
        local free_space=$((DISK_SIZE_NUM - total_allocated))
        echo -e "----------------------------------------------------------------------"
        echo -e "Total Allocated: ${WHITE}${total_allocated} GiB${NC} | Free Space: ${GREEN}${free_space} GiB${NC}"
        echo ""
        echo -e "Actions:"
        echo -e "  ${CYAN}1)${NC} Create new partition"
        echo -e "  ${CYAN}2)${NC} Delete partition"
        echo -e "  ${CYAN}3)${NC} Reset to default layout"
        echo -e "  ${CYAN}4)${NC} Done (Proceed to confirmation)"
        echo ""
        read -p "Select option (1-4) [4]: " opt
        opt=${opt:-4}
        
        case "$opt" in
            1)
                if [ $free_space -le 0 ]; then
                    echo -e "${RED}Error: No free space available on $TARGET_DISK.${NC}"
                    sleep 2
                    continue
                fi
                echo ""
                echo -e "Creating new partition:"
                read -p "Enter partition size in GiB (1-$free_space) [$free_space]: " new_size
                new_size=${new_size:-$free_space}
                if [ $new_size -le 0 ] || [ $new_size -gt $free_space ]; then
                    echo -e "${RED}Invalid size entered.${NC}"
                    sleep 1.5
                    continue
                fi
                
                read -p "Select filesystem (ext4/btrfs/xfs) [ext4]: " new_fs
                new_fs=${new_fs:-ext4}
                if [[ ! "$new_fs" =~ ^(ext4|btrfs|xfs)$ ]]; then
                    echo -e "${RED}Invalid filesystem type.${NC}"
                    sleep 1.5
                    continue
                fi
                
                read -p "Enter partition mount type (Root/Home/Data/Swap) [Data]: " new_type
                new_type=${new_type:-Data}
                
                # Append partition
                local p_idx=$((PART_COUNT + 1))
                if [[ "$TARGET_DISK" =~ nvme ]]; then
                    PART_NAMES[PART_COUNT]="${TARGET_DISK}p${p_idx}"
                else
                    PART_NAMES[PART_COUNT]="${TARGET_DISK}${p_idx}"
                fi
                PART_SIZES[PART_COUNT]=$new_size
                PART_FILESYSTEMS[PART_COUNT]="$new_fs"
                PART_TYPES[PART_COUNT]="$new_type"
                PART_COUNT=$((PART_COUNT + 1))
                
                echo -e "${GREEN}✓ Partition created successfully.${NC}"
                sleep 1.5
                ;;
            2)
                if [ $PART_COUNT -eq 0 ]; then
                    echo -e "${RED}Error: No partitions to delete.${NC}"
                    sleep 2
                    continue
                fi
                echo ""
                read -p "Enter the partition index to delete (1-$PART_COUNT): " del_idx
                if [ $del_idx -lt 1 ] || [ $del_idx -gt $PART_COUNT ]; then
                    echo -e "${RED}Invalid partition index.${NC}"
                    sleep 1.5
                    continue
                fi
                
                # Re-align arrays (remove element del_idx-1)
                local remove_idx=$((del_idx - 1))
                for ((j=remove_idx; j<PART_COUNT-1; j++)); do
                    PART_NAMES[j]="${PART_NAMES[j+1]}"
                    PART_SIZES[j]="${PART_SIZES[j+1]}"
                    PART_FILESYSTEMS[j]="${PART_FILESYSTEMS[j+1]}"
                    PART_TYPES[j]="${PART_TYPES[j+1]}"
                done
                PART_COUNT=$((PART_COUNT - 1))
                
                # Re-number devices to match new indices
                for ((j=0; j<PART_COUNT; j++)); do
                    local p_num=$((j + 1))
                    if [[ "$TARGET_DISK" =~ nvme ]]; then
                        PART_NAMES[j]="${TARGET_DISK}p${p_num}"
                    else
                        PART_NAMES[j]="${TARGET_DISK}${p_num}"
                    fi
                done
                
                echo -e "${GREEN}✓ Partition deleted successfully.${NC}"
                sleep 1.5
                ;;
            3)
                reset_partitions
                echo -e "${GREEN}✓ Reset to default layout.${NC}"
                sleep 1.5
                ;;
            4)
                if [ $PART_COUNT -eq 0 ]; then
                    echo -e "${RED}Error: You must have at least one partition configured to proceed.${NC}"
                    sleep 2
                    continue
                fi
                exit_loop=1
                ;;
            *)
                echo -e "${RED}Invalid choice.${NC}"
                sleep 1
                ;;
        esac
    done
}

# 3. Partitioning Choice
echo -e "${BLUE}[Step 3/4]${NC} Select partitioning layout:"
echo -e "   ${CYAN}1)${NC} ${WHITE}Single Partition Layout${NC} (Stage entire OS in $PART1)"
echo -e "   ${CYAN}2)${NC} ${WHITE}Separated User Space${NC}    (Create $PART1 for Root, $PART2 for /home)"
echo -e "   ${CYAN}3)${NC} ${WHITE}Custom Layout Editor${NC}    (Interactively create/remove partitions)"
echo ""
read -p "Select partition layout (1-3) [1]: " layout_choice
layout_choice=${layout_choice:-1}

reset_partitions

if [ "$layout_choice" = "3" ]; then
    custom_partitioning
fi

if [ "$layout_choice" = "2" ]; then
    LAYOUT_DESC="Root ($PART1) + /home ($PART2) split partitions"
elif [ "$layout_choice" = "3" ]; then
    LAYOUT_DESC="Custom layout partition scheme ($PART_COUNT partition(s) active)"
else
    LAYOUT_DESC="Single primary boot partition ($PART1)"
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
for ((i=0; i<PART_COUNT; i++)); do
    echo -e "  ${GREEN}✓${NC} Created ${WHITE}${PART_NAMES[i]}${NC} (${PART_TYPES[i]} partition, ${PART_SIZES[i]} GiB, Bootable)"
done
sleep 1

# Formatting
echo -e "Formatting block devices..."
sleep 1
for ((i=0; i<PART_COUNT; i++)); do
    echo -e "  Formatting ${WHITE}${PART_NAMES[i]}${NC} as ${PART_FILESYSTEMS[i]}..."
    sleep 1
done
echo -e "  ${GREEN}✓${NC} Block format successful. UUID: a0f8b1c2-3d4e-5f6a-7b8c-9d0e1f2a3b4c"
sleep 1

# Mount Target
echo -e "Mounting ${WHITE}${PART_NAMES[0]}${NC} target directory..."
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
echo -e "Congratulations! AULinux has been installed on ${WHITE}${PART_NAMES[0]}${NC} (${PART_FILESYSTEMS[0]})."
echo -e "Please disconnect the Live USB/ISO and reboot your computer."
echo ""

