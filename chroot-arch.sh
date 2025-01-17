#!/bin/bash

# -a: этот параметр указывает системе монтировать все файловые системы, перечисленные в файле /etc/fstab, которые еще не смонтированы. Это полезно для автоматического монтирования всех необходимых файловых систем.
# -v: этот параметр активирует "подробный" режим, что означает, что команда будет выводить дополнительную информацию о процессе монтирования.
#mount -av

#update-initramfs -c -k all
#grub-install --no-nvram
#update-grub


#nano /etc/mkinitcpio.conf
#HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)
#FILES=(/etc/secret/boot.key /etc/secret/root.key /etc/secret/root.lks)

mkinitcpio -P

# Install GRUB to the mounted ESP for UEFI booting
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
#grub-install --no-nvram --recheck
#grub-install --root-directory=/mnt /dev/sdb

# Generate GRUB's configuration file
grub-mkconfig -o /boot/grub/grub.cfg

grub-probe -t device /boot/grub
grub-probe -t fs_uuid /boot/grub
