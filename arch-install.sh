#!/usr/bin/env bash
set -euo pipefail

source ./utils.sh

########################################
# Helpers
########################################

cleanup() {
  warn "Cleaning up mounted filesystems and crypto devices..."

  run "umount -R /mnt 2>/dev/null || true"

  if vgdisplay vg0 &>/dev/null; then
    run "lvchange -an vg0 2>/dev/null || true"
    run "vgchange -an vg0 2>/dev/null || true"
  fi

  if cryptsetup status cryptlvm &>/dev/null; then
    run "cryptsetup close cryptlvm || true"
  fi
}

########################################
# Auto-cleanup on failure
########################################
trap 'warn "Unexpected error, cleaning up..."; cleanup' ERR

########################################
# Internet
########################################
info "Checking internet connection"
ping -c 1 archlinux.org &>/dev/null || error "No internet connection"

########################################
# Time sync
########################################
run "timedatectl set-ntp true"

########################################
# Disk selection
########################################
lsblk
read -rp "Enter disk (default /dev/sda): " DISK
DISK_NAME=${DISK_NAME:-/dev/sda}
[[ -b "$DISK_NAME" ]] || error "Invalid disk: $DISK_NAME"

DISK_SIZE_BYTES=$(blockdev --getsize64 "$DISK_NAME")
DISK_SIZE_HUMAN=$(lsblk -dn -o SIZE "$DISK_NAME")

########################################
# Size prompts
########################################
echo
info "Selected disk: $DISK_NAME ($DISK_SIZE_HUMAN)"

read -rp "EFI size (default 2G): " EFI_SIZE
EFI_SIZE=${EFI_SIZE:-2G}

read -rp "Root size (e.g. 200G or fixed size, default 200G): " ROOT_SIZE
ROOT_SIZE=${ROOT_SIZE:-200G}

read -rp "Home size (e.g. 100%FREE or fixed size, default 100%FREE): " HOME_SIZE
HOME_SIZE=${HOME_SIZE:-100%FREE}

if [[ "$ROOT_SIZE" == "100%FREE" && "$HOME_SIZE" == "100%FREE" ]]; then
  error "Root and Home cannot both use 100%FREE"
fi

########################################
# Partitions
########################################
EFI_PART="${DISK_NAME}1"
LUKS_PART="${DISK_NAME}2"

########################################
# Preflight
########################################
clear
echo "========================================="
echo " ARCH LINUX INSTALLATION PREFLIGHT"
echo "========================================="
echo
echo " Disk            : $DISK_NAME ($DISK_SIZE_HUMAN)"
echo " EFI partition   : $EFI_SIZE (FAT32)"
echo " Root LV         : $ROOT_SIZE (ext4)"
echo " Home LV         : $HOME_SIZE (ext4)"
echo " Encryption      : LUKS + LVM"
echo " Boot mode       : UEFI"
echo " Dry-run         : $DRY_RUN"
echo
echo " ⚠️  ALL DATA ON THIS DISK WILL BE LOST"
echo
confirm "Proceed with installation?" || exit 0

########################################
# Disk wipe
########################################
info "Clearing existing mounts and crypto devices"
cleanup

info "Wiping disk signatures"
run "wipefs -a $DISK_NAME"

########################################
# Partitioning
########################################
info "Partitioning disk"
run "parted -s $DISK_NAME mklabel gpt"
run "parted -s $DISK_NAME mkpart ESP fat32 1MiB $EFI_SIZE"
run "parted -s $DISK_NAME set 1 esp on"
run "parted -s $DISK_NAME mkpart primary $EFI_SIZE 100%"

########################################
# Filesystems
########################################
run "mkfs.fat -F32 $EFI_PART"

########################################
# LUKS
########################################
info "Setting up LUKS"
run "cryptsetup luksFormat $LUKS_PART"
run "cryptsetup open $LUKS_PART cryptlvm"

########################################
# LVM
########################################
info "Creating LVM layout"
run "pvcreate /dev/mapper/cryptlvm"
run "vgcreate vg0 /dev/mapper/cryptlvm"

run "lvcreate -L $ROOT_SIZE vg0 -n root"

if [[ "$HOME_SIZE" == "100%FREE" ]]; then
  run "lvcreate -l 100%FREE vg0 -n home"
else
  run "lvcreate -L $HOME_SIZE vg0 -n home"
fi

########################################
# Filesystems
########################################
run "mkfs.ext4 /dev/vg0/root"
run "mkfs.ext4 /dev/vg0/home"

########################################
# Mounting
########################################
run "mount /dev/vg0/root /mnt"
run "mkdir -p /mnt/home /mnt/boot"
run "mount /dev/vg0/home /mnt/home"
run "mount $EFI_PART /mnt/boot"


# Modify pacman config

sed -i 's/^#Color/Color/' /etc/pacman.conf

########################################
# Base install
########################################
info "Installing base system with pacstrap"
run "script -q -c "pacstrap -K /mnt base linux linux-firmware sof-firmware intel-ucode base-devel grub efibootmgr networkmanager cryptsetup lvm2 vim zsh" /dev/null"
info "Base system installed with pacstrap"

########################################
# fstab
########################################
run "genfstab -U /mnt > /mnt/etc/fstab"

########################################
# Chroot setup
########################################
LUKS_PART_UUID=$(blkid -s UUID -o value "$LUKS_PART")

########################################
# Chroot
########################################
if ! $DRY_RUN; then
  rm -rf /mnt/chroot-setup.sh
  wget https://raw.githubusercontent.com/sayyedulawwab/linux-scripts/main/chroot-setup.sh -O /mnt/chroot-setup.sh
  run "chmod +x /mnt/chroot-setup.sh"
  arch-chroot /mnt /chroot-setup.sh $LUKS_PART_UUID $DISK_NAME
fi

########################################
# Cleanup
########################################
cleanup

########################################
# Finish
########################################
info "Installation completed successfully"
warn "Log saved at $LOG_FILE"
confirm "Reboot now?" && run "reboot"
