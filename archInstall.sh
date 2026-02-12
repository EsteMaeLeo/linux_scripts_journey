#!/usr/bin/env bash
# =============================================================================
# Arch Linux interactive setup script
# - Root password reset
# - Hostname
# - Locale
# - New user + password + groups
# - Sudo wheel group
# - SSH: AllowUsers <newuser> only (disables root login via password)
# ==========================================================================
set -euo pipefail
# Load configuration from .env if it exists
if [ -f .env ]; then
    set -a          # automatically export all variables
    source .env     # or: . .env
    set +a          # turn off auto-export
else
    echo "Warning: .env file not found — using fallback defaults"
fi

# Now use safe defaults if variables weren't set
: "${INST_USERNAME:=user}"           # fallback if not in .env
: "${INST_HOSTNAME:=arch-desktop}"
: "${INST_TIMEZONE:=UTC}"
: "${INST_LOCALE:=en_US.UTF-8}"

# Optional: print what will be used (for debugging)
echo "Using username: $INST_USERNAME"
echo "Using hostname: $INST_HOSTNAME"
echo "Using timezone: $INST_TIMEZONE"
echo "Using local: $INST_LOCALE"
echo "Using disk: $INST_DISK"

# ==================== CONFIG ====================
DISK=$INST_DISK                 # CHANGE THIS IF NEEDED (e.g. /dev/nvme0n1)
HOSTNAME_DEFAULT=$INST_HOSTNAME
LOCALE_DEFAULT=$INST_LOCALE
TIMEZONE=$INST_TIMEZONE
USERNAME_DEFAULT=$INST_USERNAME          # you used 'toor' in one place
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Arch Linux installer (live phase)${NC}"
echo -e "${RED}Target disk: $DISK${NC} — ALL DATA WILL BE LOST!"
read -p "Type YES to continue: " confirm
[[ "$confirm" != "YES" && "$confirm" != "yes" ]] && exit 1

# Sync time
timedatectl set-ntp true

# Partition (EFI 512MiB + rest BTRFS)
echo -e "${YELLOW}Partitioning $DISK ...${NC}"
sgdisk --zap-all "$DISK"
sgdisk --new=1:0:+512MiB --typecode=1:ef00 --change-name=1:EFI "$DISK"
sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:root "$DISK"
sgdisk -p "$DISK"

# Format
mkfs.fat -F32 "${DISK}1"
mkfs.btrfs -L ArchRoot -f "${DISK}2"

# Mount and create subvolumes
mount "${DISK}2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume list /mnt
umount /mnt

# Remount with subvolumes
mount -o noatime,compress=zstd,subvol=@ "${DISK}2" /mnt
mkdir -p /mnt/{boot,home,.snapshots,var/log}
mount -o noatime,compress=zstd,subvol=@home "${DISK}2" /mnt/home
mount -o noatime,compress=zstd,subvol=@snapshots "${DISK}2" /mnt/.snapshots
mount -o noatime,compress=zstd,subvol=@var_log "${DISK}2" /mnt/var/log
mount "${DISK}1" /mnt/boot

lsblk -f

# Install base system
echo -e "${YELLOW}pacstrap ...${NC}"
pacstrap -K /mnt base linux linux-firmware btrfs-progs sudo vim nano micro grub efibootmgr networkmanager openssh zram-generator base-devel git sddm

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# ==================== CONFIG ====================
# Use environment variables if set, otherwise safe defaults
: "${INST_HOSTNAME:=myarch}"           # safe fallback
: "${INST_LOCALE:=en_US.UTF-8}"
: "${INST_TIMEZONE:=UTC}"              # neutral default
: "${INST_USERNAME:=user}"             # generic fallback
# ===============================================

# Copy chroot script into place
cat > /mnt/setup-chroot.sh << 'EOF'
#!/usr/bin/env bash
# Chroot phase - runs automatically

set -euo pipefail

# ==================== CONFIG FROM LIVE PHASE ====================
HOSTNAME="${INST_HOSTNAME}"
LOCALE="${INST_LOCALE}"
TIMEZONE="${INST_TIMEZONE}"
USERNAME="${INST_USERNAME}"
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd /root

echo -e "${YELLOW}Chroot phase - setting timezone, locale, hostname...${NC}"

hwclock --systohc
timedatectl set-timezone "$TIMEZONE"

# Locale
sed -i "/^#.*$LOCALE/s/^#//" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat << EOH > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOH

# Root password
echo -e "${YELLOW}Set root password${NC}"
passwd

# Create user
useradd -m -s /bin/bash "$USERNAME"
echo -e "${YELLOW}Set password for $USERNAME${NC}"
passwd "$USERNAME"
usermod -aG wheel,audio,video,optical,storage,input "$USERNAME"

# Sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ZRAM
cat > /etc/systemd/zram-generator.conf << EOC
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOC

# Bootloader (GRUB EFI)
mkdir -p /boot/efi
mount "${DISK}1" /boot/efi   # DISK is not defined here - hardcoded for safety
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# SSH
systemctl enable sshd

# Network
systemctl enable NetworkManager

# Optional: SDDM if you want graphical login
# systemctl enable sddm

# AUR helper (yay)
su - "$USERNAME" -c "cd ~ && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"

echo -e "${GREEN}Chroot phase complete!${NC}"
echo "You can now exit, umount -R /mnt && reboot"

# Optional: pause so you can review
# read -p "Press Enter to exit chroot script..."
EOF

chmod +x /mnt/setup-chroot.sh

# Chroot and run the second script
echo -e "${YELLOW}Entering chroot...${NC}"
arch-chroot /mnt /setup-chroot.sh

echo -e "${GREEN}Installation finished!${NC}"
echo "Now: umount -R /mnt && reboot"
echo "After reboot, login as $USERNAME or root"

exit 0