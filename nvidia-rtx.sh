source ./utils.sh

run "pacman -Syu linux-headers nvidia-open-dkms nvidia nvidia-utils nvidia-settings egl-wayland"

run "sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet nvidia_drm.modeset=1\"|' /etc/default/grub"

grub-mkconfig -o /boot/grub/grub.cfg

mkinitcpio -P