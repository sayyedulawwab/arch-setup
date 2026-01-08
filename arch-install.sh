#!/usr/bin/env bash
set -e

########################################
# Helpers
########################################
error() {
  echo -e "\e[31mERROR:\e[0m $1"
  exit 1
}

info() {
  echo -e "\e[32m==>\e[0m $1"
}

confirm() {
  read -rp "$1 [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

########################################
# Internet check
########################################
info "Checking internet connection..."
if ! ping -c 1 ping.archlinux.com &>/dev/null; then
  error "No internet connection. Please connect to the internet and rerun."
fi
info "Internet OK"

########################################
# Time sync
########################################
timedatectl set-ntp true

########################################
# Disk selection
########################################
lsblk
read -rp "Enter disk (e.g. /dev/sda): " DISK
[[ -b "$DISK" ]] || error "Invalid disk"

echo
echo "⚠️  ALL DATA ON $DISK WILL BE ERASED!"
confirm "Continue?" || exit 0

########################################
# Partitioning (GPT + UEFI)
########################################
info "Partitioning disk"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 2049MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 2049MiB 100%

EFI_PART="${DISK}1"
LUKS_PART="${DISK}2"

########################################
# EFI format
########################################
mkfs.fat -F32 "$EFI_PART"

########################################
# LUKS encryption
########################################
info "Setting up LUKS"
cryptsetup luksFormat "$LUKS_PART"
cryptsetup open "$LUKS_PART" cryptlvm

########################################
# LVM setup
########################################
info "Creating LVM"
pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm

lvcreate -L 200G vg0 -n root
lvcreate -l 100%FREE vg0 -n home

########################################
# Filesystems
########################################
mkfs.ext4 /dev/vg0/root
mkfs.ext4 /dev/vg0/home

########################################
# Mounting
########################################
mount /dev/vg0/root /mnt
mkdir -p /mnt/home
mount /dev/vg0/home /mnt/home

mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

########################################
# Mirrors
########################################
pacman -Sy --noconfirm reflector

cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

reflector \
  --country Bangladesh,India,Singapore \
  --latest 10 \
  --protocol https \
  --sort rate \
  --save /etc/pacman.d/mirrorlist

########################################
# Base install
########################################
pacstrap -K /mnt \
  base linux linux-firmware sof-firmware base-devel \
  grub efibootmgr networkmanager vim \
  lvm2 cryptsetup

########################################
# fstab
########################################
genfstab -U /mnt
confirm "Append fstab to /mnt/etc/fstab?" || error "Aborted"
genfstab -U /mnt >> /mnt/etc/fstab

########################################
# Chroot
########################################
arch-chroot /mnt /bin/bash <<EOF
set -e

########################################
# Timezone
########################################
read -rp "Timezone (default Asia/Dhaka): " TZ
TZ=\${TZ:-Asia/Dhaka}
ln -sf /usr/share/zoneinfo/\$TZ /etc/localtime
hwclock --systohc

########################################
# Localization
########################################
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

########################################
# Hostname
########################################
read -rp "Hostname: " HOSTNAME
echo "\$HOSTNAME" > /etc/hostname

########################################
# mkinitcpio (encrypt + lvm)
########################################
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

########################################
# Root password
########################################
passwd

########################################
# User
########################################
read -rp "New username: " USERNAME
useradd -m -G wheel -s /bin/bash "\$USERNAME"
passwd "\$USERNAME"

########################################
# Sudo
########################################
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

########################################
# NetworkManager
########################################
systemctl enable NetworkManager

########################################
# GRUB
########################################
UUID=\$(blkid -s UUID -o value "$LUKS_PART")

sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:cryptlvm root=/dev/vg0/root\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

########################################
# MSI fallback fix
########################################
mkdir -p /boot/EFI/BOOT
cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI

efibootmgr -c -d "$DISK" -p 1 \
  -L "Arch Linux" \
  -l '\\EFI\\GRUB\\grubx64.efi'

EOF

########################################
# Done
########################################
info "Installation finished. Rebooting..."
reboot
