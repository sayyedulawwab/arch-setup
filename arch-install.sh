#!/usr/bin/env bash
set -euo pipefail

########################################
# Globals
########################################
LOG_FILE="/var/log/arch-install.log"
DRY_RUN=false

########################################
# Argument parsing
########################################
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "⚠️  DRY-RUN MODE ENABLED — no changes will be made"
fi

########################################
# Logging
########################################
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

########################################
# Helpers
########################################
info() { echo -e "\e[32m==>\e[0m $1"; }
warn() { echo -e "\e[33mWARNING:\e[0m $1"; }

error() {
  echo -e "\e[31mERROR:\e[0m $1"
  umount -R /mnt || true
  cryptsetup close cryptlvm || true
  exit 1
}

confirm() {
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

########################################
# Auto-cleanup on failure
########################################
trap 'warn "Unexpected error, cleaning up..."; umount -R /mnt || true; cryptsetup close cryptlvm || true' ERR

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
DISK=${DISK:-/dev/sda}
[[ -b "$DISK" ]] || error "Invalid disk: $DISK"

DISK_SIZE_BYTES=$(blockdev --getsize64 "$DISK")
DISK_SIZE_HUMAN=$(lsblk -dn -o SIZE "$DISK")

########################################
# Size prompts
########################################
echo
info "Selected disk: $DISK ($DISK_SIZE_HUMAN)"

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
EFI_PART="${DISK}1"
LUKS_PART="${DISK}2"

########################################
# Preflight
########################################
clear
echo "========================================="
echo " ARCH LINUX INSTALLATION PREFLIGHT"
echo "========================================="
echo
echo " Disk            : $DISK ($DISK_SIZE_HUMAN)"
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
info "Wiping disk signatures"
run "wipefs -a $DISK"

########################################
# Partitioning
########################################
info "Partitioning disk"
run "parted -s $DISK mklabel gpt"
run "parted -s $DISK mkpart ESP fat32 1MiB $EFI_SIZE"
run "parted -s $DISK set 1 esp on"
run "parted -s $DISK mkpart primary $EFI_SIZE 100%"

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

########################################
# Mirrors (fast + global)
########################################
info "Configuring mirrors"

run "pacman -Sy --noconfirm reflector"
run "cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup"

COUNTRY=$(curl -s https://ipinfo.io/country || echo "*")

run "reflector \
  --protocol https \
  --completion-percent 100 \
  --country \"$COUNTRY,*\" \
  --sort country \
  --sort score \
  --connection-timeout 15 \
  --download-timeout 15 \
  --save /etc/pacman.d/mirrorlist"

head -n 15 /etc/pacman.d/mirrorlist

########################################
# Base install
########################################
info "Installing base system"
run "pacstrap -K /mnt \
  base linux linux-firmware sof-firmware intel-ucode base-devel \
  grub efibootmgr networkmanager vim \
  lvm2 cryptsetup"

########################################
# fstab
########################################
run "genfstab -U /mnt > /mnt/etc/fstab"

########################################
# Chroot setup
########################################
UUID=$(blkid -s UUID -o value "$LUKS_PART")

cat <<EOF > /mnt/chroot-setup.sh
#!/usr/bin/env bash
set -euo pipefail

exec >> /var/log/arch-install.log 2>&1

read -rp "Timezone (default Asia/Dhaka): " TZ
TZ=\${TZ:-Asia/Dhaka}
ln -sf /usr/share/zoneinfo/\$TZ /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

read -rp "Hostname: " HOSTNAME
echo "\$HOSTNAME" > /etc/hostname

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

echo "Set root password"
passwd

read -rp "New username: " USERNAME
useradd -m -G wheel -s /bin/bash "\$USERNAME"
passwd "\$USERNAME"

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager

sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="cryptdevice=UUID=$UUID:cryptlvm root=/dev/vg0/root"|' /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

mkdir -p /boot/EFI/BOOT
cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI

efibootmgr -c -d "$DISK" -p 1 -L "Arch Linux" -l '\\EFI\\GRUB\\grubx64.efi'
EOF

run "chmod +x /mnt/chroot-setup.sh"

########################################
# Chroot
########################################
if ! $DRY_RUN; then
  arch-chroot /mnt /chroot-setup.sh
fi

########################################
# Cleanup
########################################
run "umount -R /mnt || true"
run "cryptsetup close cryptlvm || true"

########################################
# Finish
########################################
info "Installation completed successfully"
warn "Log saved at $LOG_FILE"
confirm "Reboot now?" && run "reboot"
