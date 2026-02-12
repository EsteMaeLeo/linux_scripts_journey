#!/usr/bin/env bash
# wipe.sh - Safely wipe a disk completely before Arch Linux install
# WARNING: This destroys ALL data on the target disk!

set -euo pipefail
# Load configuration from .env if it exists
if [ -f .env ]; then
    set -a          # automatically export all variables
    source .env     # or: . .env
    set +a          # turn off auto-export
else
    echo "Warning: .env file not found — using fallback defaults"
fi

# ==================== CONFIG ====================
DISK=$INST_DISK         # CHANGE THIS if needed (e.g. /dev/nvme0n1)
WIPE_FIRST_MB=100        # How many MB to zero at the beginning (enough for signatures)
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== DANGEROUS OPERATION ===${NC}"
echo -e "This script will **COMPLETELY WIPE** the disk: ${YELLOW}$DISK${NC}"
echo -e "All partitions, filesystems, data, signatures — GONE FOREVER."
echo ""
lsblk -f | grep -A5 "$DISK" || lsblk | grep -A5 "$DISK"
echo ""
read -r -p "Type the disk name to confirm (e.g. sda): " confirm
if [[ "$confirm" != "${DISK#/dev/}" ]]; then
    echo -e "${RED}Confirmation failed. Aborting.${NC}"
    exit 1
fi

echo -e "${YELLOW}Unmounting anything related to $DISK ...${NC}"
umount -R /mnt 2>/dev/null || true
umount "${DISK}1" 2>/dev/null || true
umount "${DISK}2" 2>/dev/null || true
umount "${DISK}3" 2>/dev/null || true
umount "${DISK}p1" 2>/dev/null || true  # for nvme
umount "${DISK}p2" 2>/dev/null || true
mount | grep "$DISK" | awk '{print $3}' | xargs -r umount -l 2>/dev/null || true

echo -e "${YELLOW}Disabling swap ...${NC}"
swapoff -a 2>/dev/null || true

echo -e "${YELLOW}Wiping filesystem signatures ...${NC}"
wipefs --all --force "$DISK"* 2>/dev/null || true

echo -e "${YELLOW}Zapping partition tables (GPT + MBR) ...${NC}"
sgdisk --zap-all "$DISK" || {
    echo -e "${RED}sgdisk failed — trying fallback${NC}"
    dd if=/dev/zero of="$DISK" bs=512 count=34 status=none
    dd if=/dev/zero of="$DISK" bs=512 count=34 seek=$(($(blockdev --getsz "$DISK") - 34)) status=none
}

echo -e "${YELLOW}Wiping first ${WIPE_FIRST_MB} MB to clear old superblocks ...${NC}"
dd if=/dev/zero of="$DISK" bs=1M count="$WIPE_FIRST_MB" status=progress conv=fsync
sync

echo -e "${GREEN}Wipe complete!${NC}"
echo "Verifying disk is clean:"
echo ""
lsblk -f
echo ""
fdisk -l "$DISK" | head -n 10
echo ""
echo -e "You can now safely repartition $DISK (e.g. with sgdisk or cfdisk)."
echo -e "Run your install script from the beginning."

exit 0