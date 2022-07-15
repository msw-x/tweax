#!/bin/bash

BootDevice=$(lsblk -o NAME,MOUNTPOINTS | awk '/efi$/{print $1}' | grep -o -P "[a-z]+")
if [[ $BootDevice == "" ]]; then
    echo "boot-device: not found"
    exit 1
fi
echo "boot-device: $BootDevice"
umount -l /boot
#dmsetup remove -f bootfs
cryptsetup luksClose bootfs
eject $BootDevice
