#!/bin/bash

EfiPartition=$1

echo "efi-partition: $EfiPartition"

mount -av

apt install -y --reinstall grub-efi-amd64-signed linux-generic linux-headers-generic
update-initramfs -c -k all
grub-install $EfiPartition --removable --no-nvram
