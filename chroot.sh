#!/bin/bash

BootDev=$1

echo "boot device: $BootDev"

mount -av

apt install -y --reinstall grub-efi-amd64-signed linux-generic linux-headers-generic
update-initramfs -c -k all
grub-install $BootDev --no-nvram
update-grub
grub-probe -t device /boot/grub
grub-probe -t fs_uuid /boot/grub
