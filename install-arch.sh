#!/bin/bash

# -e option instructs bash to immediately exit if any command has a non-zero exit status
# -u affects to unused variables
set -eu

BootKey=boot.key
RootKey=root.key
RootHeader=root.lks
RootOffsetMiB=512

EfiMiB=100
BootMiB=500
IsoMiB=2000

LvmRootGiB=120

EfiFsLabel='x-usb-efi'
IsoFsLabel='x-usb-iso'
PayFsLabel='x-usb-pay'
RootTrapFsLabel='x-data'

BootLabel='BOOT'
RootLabel='ROOT'

CryptBootFS='bootfs'
CryptRootFS='rootfs'
LvmVG='lvm'
LvmRoot='root'
LvmExt='ext'

Secrets='/etc/secret'

MntExt='/mnt/ext'

TimeZone='Europe/Moscow'

Locales='en_US ru_RU'

# Tools

TmpDir='/tmp/install-'$(date +%s%N)
PwdDir=$(pwd)
SrcDir=${PwdDir}'/src/install'

Target='/mnt'

Bold='\033[1m'
Red='\e[31m'
Green='\e[32m'
Yellow='\e[33m'
Blue='\e[34m'
Purple='\e[35m'
Cyan='\e[36m'
NC='\e[0m'

function Fatal {
    msg=$*
    echo -e "${Red}$msg${NC}"
    exit 1
}

username=''
hostname=''

# Devices

devicePrefix="/dev/"
deviceMapper=$devicePrefix'mapper'

function DeviceName {
    local name=$1
    name=${name#"$devicePrefix"}
    echo "${name}"
}

function DevicePath {
    local path=$1
    if [[ $path == $devicePrefix* ]]; then
        echo $path
    else
        echo $devicePrefix$path
    fi
}

function DeviceMiB {
    local path=$(DevicePath $1)
    local size=$(lsblk $path -o path,SIZE,TYPE --byte | grep disk | awk '{print $2}')
    echo $(($size/1024/1024))
}

function DeviceGiB {
    local path=$(DevicePath $1)
    local size=$(DeviceMiB $path)
    size=$(($size/1024))
    echo $size
}

function DeviceModel {
    local path=$(DevicePath $1)
    local model=$(lsblk $path -o path,TYPE,MODEL | grep disk | awk '{$1=$2=""; print $0}' | awk '{$1=$1}1')
    echo $model
}

function DeviceInfo {
    local name=$(DeviceName $1)
    local path=$(DevicePath $1)
    local size=$(DeviceGiB $path)
    local model=$(DeviceModel $path)
    echo "$name [$size GiB] $model"
}

function DevicePartition {
    local device=$1
    local number=$2
    if [[ $device == *"nvme"* ]]; then
        echo ${device}p${number}
    else
        echo ${device}${number}
    fi
}

function DevicePartitionsCount {
    local path=$(DevicePath $1)
    local partitions=$(lsblk $path -o NAME,TYPE --list | grep part | awk '{print $1}')
    local n=$(echo $partitions | wc -w)
    echo "$n"
}

# Partitions

function PartitionMiB {
    local path=$(DevicePath $1)
    local size=$(lsblk $path -o NAME,SIZE,TYPE --byte | grep part | awk '{print $2}')
    echo $(($size/1024/1024))
}

function PartitionGiB {
    local size=$(PartitionMiB $1)
    size=$(($size/1024))
    echo $size
}

function PartitionInfo {
    local name=$(DeviceName $1)
    local path=$(DevicePath $1)
    local size=$(PartitionGiB $path)
    echo "$name [$size GiB]"
}

function PartitionUUID {
    local path=$(DevicePath $1)
    local uuid=$(blkid -s UUID -o value $path)
    echo $uuid
}

# Mounts

function ShowMounts {
    lsblk -o NAME,PTTYPE,FSTYPE,SIZE,FSUSE%,RO,RM,TYPE,LABEL,MOUNTPOINTS,UUID,STATE
    echo -e "${Purple}[$deviceMapper]${NC}"
    ls -la $deviceMapper | grep '\->' | awk '{print $9}'
}

# Select devices

devices=''

function LoadDevices {
    devices=$(lsblk -o NAME,TYPE | grep disk | awk '{print $1}')
}

function ShowDevices {
    echo "Devices:"
    local n=0
    for name in $devices
    do
        n=$((n+1))
        echo "[$n] $(DeviceInfo $name)"
    done
}

function DevicesCount {
    local n=$(echo $devices | wc -w)
    echo "$n"
}

function CheckDevices {
    local n=$(DevicesCount)
    local m=2
    if (( $n < $m )); then
        Fatal "There must be at least $m devices, but found only $n"
    fi
}

function CheckBootDeviceSize {
    local sizeMiB=$(DeviceMiB $bootDev)
    local minMiB=$((EfiMiB+BootMiB+IsoMiB+100))
    if (( sizeMiB < minMiB )); then
        Fatal "Error: size of $bootDev ($sizeMiB MiB) very small, it is necessary to at least $minMiB MiB"
    fi
}

function CheckRootDeviceSize {
    local sizeGiB=$(DeviceGiB $rootDev)
    local minGiB=$((LvmRootGiB+4))
    if (( sizeGiB < minGiB )); then
        Fatal "Error: size of $rootDev ($sizeGiB GiB) very small, it is necessary to at least $minGiB GiB"
    fi
}

function GetDevice {
    local index=$1
    local device=$(echo $devices | awk '{print $'$index'}')
    echo $device
}

function GetEdgeDevice {
    local name=$1
    local edge=$2
    local device=$(echo $devices | tr ' ' '\n' | grep $name | $edge -n 1)
    echo $device
}

bootDev=''
rootDev=''

function AutoSelectDevices {
    bootDev=$(GetEdgeDevice sd tail)
    rootDev=$(GetEdgeDevice nvme head)
    if [[ $rootDev == "" ]]; then
        rootDev=$(GetEdgeDevice sd head)
    fi
    if [[ $bootDev == "" ]]; then
        bootDev=$(GetEdgeDevice nvme tail)
    fi
}

function SelectDevice {
    local label=$1
    local device=$bootDev
    if [[ $label == $RootLabel ]]; then
        device=$rootDev
    fi
    local key=''
    read -n 1 -p "$(echo -e "$Cyan$label$NC device [default=$Bold$Cyan$device$NC]: ")" key
    if [[ $key != "" ]]; then
        device=$(GetDevice $key)
        echo
    fi
    if [[ $label == $RootLabel ]]; then
        rootDev=$device
    else
        bootDev=$device
    fi
}

function SelectDevices {
    while : ; do
        AutoSelectDevices
        SelectDevice $BootLabel
        SelectDevice $RootLabel
        [[ $rootDev == $bootDev ]] || break
    done
    LoadRootPartitions $rootDev
    local n=$(RootPartitionsCount)
    if [[ $n > 1 ]]; then
        SelectRootPartition
    fi
    local rootpart=''
    if [[ $rootPartition != "" ]]; then
        rootpart="[$rootPartition]"
    fi
    echo -e "${Yellow}$BootLabel${NC} device: ${Bold}${Yellow}$(DeviceInfo $bootDev)${NC}"
    echo -e "${Purple}$RootLabel${NC} device: ${Bold}${Purple}$(DeviceInfo $rootDev) $rootpart${NC}"
}

rootPartitions=''
rootPartition=''

function LoadRootPartitions {
    local path=$(DevicePath $1)
    rootPartitions=$(lsblk $path -o NAME,TYPE --list | grep part | awk '{print $1}')
}

function ShowRootPartitions {
    local n=0
    for name in $rootPartitions
    do
        n=$((n+1))
        echo "[$n] $(PartitionInfo $name)"
    done
}

function RootPartitionsCount {
    local n=$(echo $rootPartitions | wc -w)
    echo "$n"
}

function SelectRootPartition {
    echo "[0] $rootDev"
    ShowRootPartitions
    local key=''
    read -n 1 -p "$(echo -e "$Cyan$RootLabel$NC device [default=0]: ")" key
    local re='^[0-9]+$'
    if [[ $key == "" ]]; then
        return
    fi
    if ! [[ $key =~ $re ]]; then
       return
    fi
    echo
    if [[ $key == 0 ]]; then
        return
    fi
    rootPartition=$(DevicePartition $rootDev $key)
}

# Install

reinstall=true

function Startup {
    mkdir ${TmpDir}
    cd ${TmpDir}

    echo $(uname -rmo)
}

function CheckArch {
    if ! uname -r | grep -q arch; then
        Fatal "Arch not found"
    fi
}

function CheckEfi {
    if [ ! -f /sys/firmware/efi/fw_platform_size ]; then
        Fatal "UEFI not found"
    fi
}

function SelectMode {
    local bootPartitionsCount=$(DevicePartitionsCount $bootDev)
    if [[ $bootPartitionsCount == 4 ]]; then
        local key=''
        read -n 1 -p "Re-Install mode? y/n: " key && echo
        if [[ $key == 'n' ]]; then
            reinstall=false
        elif [[ $key != 'y' ]]; then
            exit 1
        fi
    else
        reinstall=false
    fi
    local mode="Full-Install (${Red}erase all data${NC} on ${Yellow}$BootLabel${NC} and ${Purple}$RootLabel${NC})"
    if $reinstall; then
        mode="Re-Install (save ${Cyan}$PayFsLabel${NC}, ${Cyan}$IsoFsLabel${NC} and ${Cyan}$RootTrapFsLabel${NC})"
    fi
    echo -e "Mode: $mode"
}

function SetPersonal {
    read -p "Username: " username
    read -p "Hostname: " hostname
}

function Сonfirmation {
    local key=''
    read -n 1 -p "$(echo -e "${Red}Attention! Are you sure you want to install system?${NC} y/n: ")" key && echo
    if [[ $key != 'y' ]]; then
        echo "cancel the installation"
        exit
    else
        echo
    fi
}

function Finish {
    echo -e "${Green}Installation successfully completed!${NC}"
    read -n 1 -p "System reboot is required. Reboot now? y/n: " key && echo
    if [[ $key == 'y' ]]; then
        echo "rebooting..."
        reboot
    fi
}

payPartition=''
efiPartition=''
bootPartition=''
isoPartition=''

function CloseDevices {
    umount -R /mnt || true

    umount "$Target/boot/efi" || true
    umount "$Target/boot" || true
    umount "$Target" || true

    umount '/dev/'${bootDev}* || true
    umount '/dev/'${rootDev}* || true

    vgchange -an

    cryptsetup luksClose $CryptBootFS || true
    cryptsetup luksClose $CryptRootFS || true
}

function WipeDevice {
    echo
    read -n 1 -p "Wipe device $rootDev? y/n: " key && echo
    if [[ $key == 'y' ]]; then
        cryptsetup -q open --type plain --cipher aes-xts-plain64 --key-size 256 --key-file /dev/urandom /dev/$rootDev wipe
        dd bs=1M if=/dev/zero of=$deviceMapper/wipe status=progress || true
        cryptsetup close wipe
    fi
}

function MakePartitions {
    local sizeMiB=$(DeviceMiB $bootDev)
    local payMiB=$((sizeMiB-EfiMiB-BootMiB-IsoMiB-2))
    local bootOffsetMiB=$((payMiB+EfiMiB))
    local isoOffsetMiB=$((bootOffsetMiB+BootMiB))

    bootDev=$(DevicePath $bootDev)
    rootDev=$(DevicePath $rootDev)

    echo
    if ! $reinstall; then
        echo -e "make ${Yellow}$BootLabel${NC} partition table: ${Bold}${Yellow}$bootDev${NC}"
        parted --script $bootDev mklabel gpt
        parted --script $bootDev mkpart primary 1MiB ${payMiB}MiB
        parted --script $bootDev mkpart primary ${payMiB}MiB ${bootOffsetMiB}MiB
        parted --script $bootDev mkpart primary ${bootOffsetMiB}MiB ${isoOffsetMiB}MiB
        parted --script $bootDev mkpart primary ${isoOffsetMiB}MiB 100%
        parted --script $bootDev set 2 boot on
        if [[ $rootPartition == "" ]]; then
            echo -e "make ${Purple}$RootLabel${NC} partition table: ${Bold}${Purple}$rootDev${NC}"
            parted --script $rootDev mklabel gpt
            parted --script $rootDev mkpart primary 1MiB 100%
        fi
        echo
    fi

    echo -e "${Yellow}$BootLabel${NC} device info: ${Bold}${Yellow}$bootDev${NC}"
    parted $bootDev print
    echo -e "${Purple}$RootLabel${NC} device info: ${Bold}${Purple}$rootDev${NC}"
    parted $rootDev print

    payPartition=$(DevicePartition $bootDev 1)
    efiPartition=$(DevicePartition $bootDev 2)
    bootPartition=$(DevicePartition $bootDev 3)
    isoPartition=$(DevicePartition $bootDev 4)
    if [[ $rootPartition == "" ]]; then
        rootPartition=$(DevicePartition $rootDev 1)
    fi

    if $reinstall; then
        ExtractKeys
    fi

    mkfs.fat -F32 $efiPartition -n $EfiFsLabel
    if ! $reinstall; then
        mkfs.fat -F32 $payPartition -n $PayFsLabel
        mkfs.ext4 -F $isoPartition -L $IsoFsLabel
        mkfs.btrfs -f $rootPartition --label $RootTrapFsLabel
    fi

    # You must use luks1 here - Currently, the latest grub does support opening a luks2 partition,
    # but it does not support the argon2id encryption algorithm yet. So to have an encrypted boot requires luks1 for the moment.
    # I have upped the iteration parameter to 5000 from the default 3000. 
    # This will result in the unlocking of encrypted partition taking a little longer at boot (nothing excessive, but it depends on hardware).
    # If this is a problem (i.e. you have a slow processor), please change the 5000 in the command below back to 3000.
    # I would not recommend going any lower than the default of 3000.

    dd if=/dev/urandom of=$BootKey bs=4096 count=1
    chmod u=r,go-rwx $BootKey
    cryptsetup -q luksFormat --type=luks1 --cipher=aes-xts-plain64 --hash=sha512 --iter-time=5000 --key-size=512 --key-file=$BootKey $bootPartition
    cryptsetup luksAddKey $bootPartition --key-file=$BootKey
    cryptsetup luksOpen $bootPartition $CryptBootFS --key-file=$BootKey

    if ! $reinstall; then
        local luksOffset=$((RootOffsetMiB*1024*2))
        dd if=/dev/urandom of=$RootKey bs=4096 count=1
        chmod u=r,go-rwx $RootKey
        cryptsetup -q luksFormat --cipher=aes-xts-plain64 --hash=sha512  --iter-time=5000 --key-size=512 --key-file=$RootKey $rootPartition --header=$RootHeader --offset=$luksOffset --luks2-keyslots-size=262144
    fi
    cryptsetup luksOpen $rootPartition $CryptRootFS --key-file=$RootKey --header $RootHeader

    mkfs.ext4 -F $deviceMapper/$CryptBootFS

    if ! $reinstall; then
        pvcreate $deviceMapper/$CryptRootFS
        vgcreate $LvmVG $deviceMapper/$CryptRootFS
        lvcreate -n $LvmRoot -L ${LvmRootGiB}G $LvmVG
        lvcreate -n $LvmExt -l 100%FREE $LvmVG
        mkfs.ext4 $deviceMapper/${LvmVG}-${LvmExt}
    fi
    mkfs.ext4 -F $deviceMapper/${LvmVG}-${LvmRoot}

    local targetRoot="$Target"
    local targetBoot="$Target/boot"
    local targetEfi="$Target/boot/efi"
    local targetMntExt="$Target/$MntExt"

    mount --mkdir "$deviceMapper/${LvmVG}-${LvmRoot}" $targetRoot
    mount --mkdir "$deviceMapper/${LvmVG}-${LvmExt}" $targetMntExt
    mount --mkdir "$deviceMapper/${CryptBootFS}" $targetBoot
    mount --mkdir $efiPartition $targetEfi

    if ! $reinstall; then
        useradd $username
        chown -R $username:$username $targetMntExt
    fi

    ShowMounts
}

function Install {
    echo
    echo -e "${Bold}${Green}Install${NC}"

    # Syncronise the Package Database
    pacman -Syy

    # Install the Arch Base System
    #linux-firmware
    #x86-video-intel — Это для интел
    #xf86-vide-amdgpu xf86-video-ati — Это для AMD
    #xf86-video-nouveau — Это для нвидиа
    pacstrap $Target base base-devel linux intel-ucode grub lvm2 nano dhcpcd iproute2 networkmanager cryptsetup
}

function Ls {
    local dir=$1
    echo -e "${Bold}${Blue}$dir${NC}"
    ls -1 $dir
    echo
}

function Cat {
    local file=$1
    echo -e "${Bold}${Blue}$file${NC}"
    cat $file
    echo
}

function EnableLocale {
    local name=$1
    sed -i "/#$name/s/^.//" $Target/etc/locale.gen
}

function PostInstall {
    echo 
    echo -e "${Bold}${Green}Postinstall${NC}"

    mkdir -p $Target/$Secrets
    cp $RootHeader $Target/$Secrets
    cp $BootKey $Target/$Secrets
    cp $RootKey $Target/$Secrets

    ShowMounts

    local bootUUID=$(PartitionUUID $bootPartition)
    local rootUUID=$(PartitionUUID $rootPartition)
    local cryptBootUUID=$(PartitionUUID $deviceMapper/$CryptBootFS)
    local bootUuid=$(echo "$bootUUID" | tr -d "-")

    local fstab=$Target/etc/fstab
    genfstab -U $Target >> $fstab
    Cat $fstab

    local grub=$Target/etc/default/grub
    # Allow booting from /boot on a LUKS encrypted partition
    sed -i "/#GRUB_ENABLE_CRYPTODISK=y/s/^.//" $grub
    # Disable discover other OS installed
    sed -i "s|#GRUB_DISABLE_OS_PROBER=false|GRUB_DISABLE_OS_PROBER=true|" $grub
    Cat $grub

    local grubconf=$Target/boot/grub/grub.cfg
    mkdir -p $Target/boot/grub
    cp $PwdDir/grub-arch.cfg $grubconf
    sed -i "s|@BootUUID|$bootUUID|" $grubconf
    sed -i "s|@bootUuid|$bootUuid|" $grubconf
    sed -i "s|@CryptBootUUID|$cryptBootUUID|" $grubconf
    Cat $grubconf

    local encryptHook='encrypt2'
    local encryptHookFile=$Target/etc/initcpio/hooks/$encryptHook
    cp $PwdDir/crypthook-arch $encryptHookFile
    cp $Target/usr/lib/initcpio/install/encrypt $Target/etc/initcpio/install/$encryptHook
    sed -i "s|@BootUUID|$bootUUID|" $encryptHookFile
    sed -i "s|@BootKey|$Secrets/$BootKey|" $encryptHookFile
    sed -i "s|@CryptBootFS|$CryptBootFS|" $encryptHookFile
    sed -i "s|@RootUUID|$rootUUID|" $encryptHookFile
    sed -i "s|@CryptRootFS|$CryptRootFS|" $encryptHookFile
    sed -i "s|@RootKey|$Secrets/$RootKey|" $encryptHookFile
    sed -i "s|@RootHeader|$Secrets/$RootHeader|" $encryptHookFile
    Cat $encryptHookFile

    local mkinitcpio=$Target/etc/mkinitcpio.conf
    local secretFiles="$Secrets/$BootKey $Secrets/$RootKey $Secrets/$RootHeader"
    cp $mkinitcpio $mkinitcpio.bk
    cp $PwdDir/'mkinitcpio-arch.conf' $mkinitcpio
    sed -i "s|@FILES|$secretFiles|" $mkinitcpio
    sed -i "s|@ENCRYPT|$encryptHook|" $mkinitcpio
    Cat $mkinitcpio

    ln -s /usr/share/zoneinfo/$TimeZone $Target/etc/localtime

    for locale in $Locales
    do
        EnableLocale "$locale.UTF-8 UTF-8"
    done

    echo $hostname > $Target/etc/hostname

    #vim $Target/etc/hosts
    #127.0.0.1 localhost
    #::1 localhost
    #127.0.0.1 ARCH.localdomain ARCH
    #Вместо ARCH можете написать ваше имя компьтера , у меня это ARCH

    local sudoers=$Target/etc/sudoers
    sed -i "/# %wheel ALL=(ALL:ALL) ALL/s/^..//" $sudoers
    Cat $sudoers

    #nano $Target/etc/vconsole.conf
    #KEYMAP=ru
    #FONT=cyr-sun16

    cp $PwdDir/chroot-arch.sh $Target/root/chroot.sh
    chmod +x $Target/root/chroot.sh

    arch-chroot $Target /root/chroot.sh $username
    rm $Target/root/chroot.sh

    umount -R /mnt
}

# Run

Startup
CheckEfi
CheckArch
LoadDevices
ShowDevices
CheckDevices
SelectDevices
CheckBootDeviceSize
CheckRootDeviceSize
SelectMode
SetPersonal
Сonfirmation
CloseDevices
WipeDevice
MakePartitions
Install
PostInstall
Finish
