#!/bin/bash

set -eu

username=$1

locale-gen

hwclock --systohc --utc

mkinitcpio -P

echo "Enter root password"
passwd
useradd -m -g users -G wheel -s /bin/bash $username
echo "Enter $username password"
passwd $username

grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable

######
grub-mkconfig -o /boot/grub/grub.cfg

grub-probe -t device /boot/grub
grub-probe -t fs_uuid /boot/grub

free -h

#pacman -S networkmanager bspwm ...
