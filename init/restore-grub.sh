#!/bin/sh
set -e

f="/boot/grub/grub.cfg"
up="${f}.up"
bk="${f}.bk"

if [ -f "$up" ]; then
    if [ -f "$f" ]; then
        echo "backup grub.cfg"
        cp "$f" "$bk"
    fi
    echo "restore grub.cfg"
    cp "$up" "$f"
fi

exit 0
