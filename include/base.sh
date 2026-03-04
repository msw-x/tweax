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

Сonfirmation() {
    local key=''
    read -n 1 -p "$(echo -e "🚀 ${Red}Attention! Are you sure you want to install system?${NC} y/n: ")" key && echo
    if [[ $key != 'y' ]]; then
        echo "cancel the installation"
        exit
    fi
}

Finish() {
    Time
    echo
    echo -e "✅ ${Green}Installation successfully completed!${NC}"
    read -n 1 -p "System reboot is required. Reboot now? y/n: " key && echo
    if [[ $key == 'y' ]]; then
        echo "rebooting..."
        reboot
    fi
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
}

ShowRoot() {
    echo -e "${Purple}$RootLabel${NC} device info: ${Bold}${Purple}$rootDev${NC}"
    parted $rootDev print
}

OpenBoot() {
    cryptsetup luksOpen $bootPartition $BootFS
}

OpenRoot() {
    cryptsetup luksOpen $rootPartition $RootFS --key-file=$RootKey --header=$RootHeader
}

ProbeBoot() {
    partprobe $bootDev
}

ProbeRoot() {
    partprobe $rootDev
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
    MountBoot
    local initramfs='initramfs'
    mkdir $initramfs
    case $DistroID in
        arch)
            cd $initramfs
            lsinitcpio -x "$targetBoot/initramfs-linux.img"
            cd ..
            cp "$initramfs/$Secrets/$RootKey" .
            cp "$initramfs/$Secrets/$RootHeader" .
            ;;
        ubuntu)
            unmkinitramfs "$targetBoot/initrd.img" $initramfs
            cp "$initramfs/main/cryptroot/keyfiles/$RootFS.key" $RootKey
            cp "$initramfs/main$Secrets/$RootHeader" .
            ;;
    esac
    umount $targetBoot || true
    cryptsetup luksClose $BootFS
}

inetDev=''
inetIp=''
inetGw=''
inetDns=''

GetInet() {
    inetDev=$(ip route get 8.8.8.8 2>/dev/null | grep -o 'dev [^ ]*' | cut -d' ' -f2)
    if [[ $inetDev == "" ]]; then
        return
    fi
    inetIp=$(ip -4 addr show $inetDev | grep -o "inet [0-9./]*" | cut -d' ' -f2 | head -1)
    inetGw=$(ip route show default | grep $inetDev | grep -o "via [0-9.]*" | cut -d' ' -f2 | head -1)
    if command -v resolvectl &> /dev/null; then
        inetDns=$(resolvectl dns $inetDev 2>/dev/null | awk -F': ' '{print $2}' | xargs)
    fi
}
