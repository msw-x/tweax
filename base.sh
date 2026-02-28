# Basic

PwdDir=$(pwd)

Chroot() {
    arch-chroot $Target /bin/bash -c "$*"
}

OsReleaseKey() {
    local key=$1
    grep "^$key=" /etc/os-release | cut -d'=' -f2 | tr -d '"'
}

DistroID=$(OsReleaseKey 'ID')
DistroCodeName=$(OsReleaseKey 'VERSION_CODENAME')

Startup() {
    if [[ $EUID != 0 ]]; then
        Fatal "The script should be run from root user"
    fi

    hostnamectl
    echo
    cat /etc/os-release
    echo
    echo -e "🏷️  ${Purple}$(uname -rmo)${NC}"

    if [ -d $TmpDir ]; then
        local key=''
        echo
        read -n 1 -p "Clean $TmpDir? y/n: " key && echo
        if [[ $key == 'y' ]]; then
            rm -rf $TmpDir
        fi
    fi
    if [ ! -d $TmpDir ]; then
        mkdir $TmpDir
    fi
    cd $TmpDir
}

CheckEfi() {
    if [ ! -f /sys/firmware/efi/fw_platform_size ]; then
        Fatal "UEFI not found"
    fi
}

CheckDistro() {
    case $DistroID in
        arch)
            ;;
        ubuntu)
            ;;
        *)
            Fatal "Unknown distro id: $DistroID"
            ;;
    esac
}

mapBootFS=$deviceMapper/$BootFS
mapRootFS=$deviceMapper/$RootFS
mapLvmRoot=$deviceMapper/$LvmVG-$LvmRoot
mapLvmExt=$deviceMapper/$LvmVG-$LvmExt

targetRoot="$Target"
targetBoot="$Target/boot"
targetEfi="$Target/boot/efi"
targetMntExt=$Target$MntExt

payPartition=''
efiPartition=''
bootPartition=''
isoPartition=''

DefineBoot() {
    bootDev=$(DevicePath $bootDev)
    payPartition=$(DevicePartition $bootDev 1)
    efiPartition=$(DevicePartition $bootDev 2)
    bootPartition=$(DevicePartition $bootDev 3)
    isoPartition=$(DevicePartition $bootDev 4)
}

DefineRoot() {
    rootDev=$(DevicePath $rootDev)
    if [[ $rootPartition == "" ]]; then
        rootPartition=$(DevicePartition $rootDev 1)
    else
        rootPartition=$(DevicePath $rootPartition)
    fi
}

ShowBoot() {
    echo -e "${Yellow}$BootLabel${NC} device info: ${Bold}${Yellow}$bootDev${NC}"
    parted $bootDev print
    partprobe $bootDev
}

ShowRoot() {
    echo -e "${Purple}$RootLabel${NC} device info: ${Bold}${Purple}$rootDev${NC}"
    parted $rootDev print
    partprobe $rootDev
}

OpenBoot() {
    cryptsetup luksOpen $bootPartition $BootFS
}

OpenRoot() {
    cryptsetup luksOpen $rootPartition $RootFS --key-file=$RootKey --header $RootHeader
}

MountBoot() {
    mount --mkdir $mapBootFS $targetBoot
}

MountEfi() {
    mount --mkdir $efiPartition $targetEfi
}

MountLvmRoot() {
    mount --mkdir $mapLvmRoot $targetRoot
}

MountLvmExt() {
    mount --mkdir $mapLvmExt $targetMntExt
}

ExtractKeys() {
    OpenBoot
    local initramfs='initramfs'
    mkdir $initramfs
    case $DistroID in
        arch)
            cd $initramfs
            lsinitcpio -x "../$BootFS/initramfs-linux.img"
            cd ..
            cp "$initramfs/$Secrets/$RootKey" .
            cp "$initramfs/$Secrets/$RootHeader" .
            ;;
        ubuntu)
            unmkinitramfs "$BootFS/initrd.img" $initramfs
            cp "$initramfs/main/cryptroot/keyfiles/$RootFS.key" $RootKey
            cp "$initramfs/main$Secrets/$RootHeader" .
            ;;
    esac
    umount $BootFS || true
    cryptsetup luksClose $BootFS
}
