#!/usr/bin/env bash
set -euo pipefail

source ./utils.sh

LUKS_PART_UUID=$1
DISK_NAME=$2

run "read -rp 'Timezone (default Asia/Dhaka): ' TZ"
TZ=\${TZ:-Asia/Dhaka}
run "ln -sf /usr/share/zoneinfo/\$TZ /etc/localtime"
run "hwclock --systohc"

run "sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen"
run "locale-gen"
run "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"

run "read -rp 'Hostname: ' HOSTNAME"
run "echo '\$HOSTNAME' > /etc/hostname"

run "sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf"
run "mkinitcpio -P"

echo "Set root password"
run "passwd"

run "read -rp 'New username: ' USERNAME"
run "useradd -m -G wheel -s /bin/bash '\$USERNAME'"
run "passwd '\$USERNAME'"
run "pacman -S --noconfirm sudo"

run "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/00-wheel"
run "chmod 440 /etc/sudoers.d/00-wheel"

run "systemctl enable NetworkManager"

run "sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="cryptdevice=UUID=$LUKS_PART_UUID:cryptlvm root=/dev/vg0/root"|' /etc/default/grub"

run "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
run "grub-mkconfig -o /boot/grub/grub.cfg"

run "mkdir -p /boot/EFI/BOOT"
run "cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI"

run "efibootmgr -c -d "$DISK_NAME" -p 1 -L "Arch Linux" -l '\\EFI\\GRUB\\grubx64.efi'"

run "chsh -s /usr/bin/zsh"
run "chsh -s /usr/bin/zsh \$USERNAME"