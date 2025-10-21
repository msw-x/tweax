#!/bin/bash

set -eu

Bold='\033[1m'
Red='\e[31m'
Green='\e[32m'
Yellow='\e[33m'
Blue='\e[34m'
Purple='\e[35m'
Cyan='\e[36m'
NC='\e[0m'

username=$1

locale-gen
locale -a

hwclock --systohc --utc

mkinitcpio -P

echo -e "Enter ${Bold}${Red}root${NC} ${Bold}password${NC}"
passwd
useradd -m -g users -G wheel -s /bin/bash $username
echo -e "Enter ${Bold}${Green}$username${NC} ${Bold}password${NC}"
passwd $username

grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable

grub-probe -t device /boot/grub
grub-probe -t fs_uuid /boot/grub

free -h

systemctl enable dhcpcd
