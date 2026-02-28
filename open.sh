#!/bin/bash

set -eu

source ./conf.sh
source ./tools.sh
source ./devices.sh
source ./base.sh

Open() {
    Title "Actions"
    echo "[0] exit"
    echo "[1] extract keys"
    echo "[2] open boot"
    echo "[3] open root"
    echo "[4] close all"
    local key=''
    read -n 1 -p "$(echo -e "${Cyan}action:${NC}") " key
    echo
    echo
    case $key in
        1)
            DefineBoot
            ShowBoot
            ExtractKeys
            ;;
        2)
            DefineBoot
            ShowBoot
            OpenBoot
            MountBoot
            MountEfi
            ;;
        3)
            DefineRoot
            ShowRoot
            OpenRoot
            MountLvmRoot
            MountLvmExt
            ;;
        4)
            CloseDevices
            ;;
    esac
}

Startup
ShowMounts
LoadDevices
ShowDevices
SelectDevices
Open
