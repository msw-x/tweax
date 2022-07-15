#!/bin/bash

mount -av

apt install -y --reinstall grub-efi-amd64-signed linux-generic linux-headers-generic
update-initramfs -c -k all
grub-install --no-nvram
update-grub
grub-probe -t device /boot/grub
grub-probe -t fs_uuid /boot/grub
