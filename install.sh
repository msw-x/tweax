#!/bin/bash

# -e option instructs bash to immediately exit if any command has a non-zero exit status
# -u affects to unused variables
set -eu

BootKey=boot.key
RootKey=root.key
RootHeader=root.lks
RootOffsetMiB=512

EfiMiB=100
BootMiB=4000
IsoMiB=8000

LvmRootGiB=160

EfiFsLabel='x-usb-efi'
IsoFsLabel='x-usb-iso'
PayFsLabel='x-usb-pay'
RootTrapFsLabel='x-data'

BootLabel='BOOT'
RootLabel='ROOT'

BootFS='bootfs'
RootFS='rootfs'
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

Time() {
    local time="$(date -d @$(($(date +%s)-$start)) +"%Mm %Ss")"
    echo
    echo -e "${Bold}${Blue}time: $time${NC}"
}

Fatal() {
    msg=$*
    Time
    echo
    echo -e "${Red}$msg${NC}"
    exit 1
}

Ls() {
    local dir=$1
    echo
    echo -e "${Bold}${Blue}$dir${NC}"
    ls -1 $dir
    echo
}

Cat() {
    local file=$1
    echo
    echo -e "${Bold}${Blue}$file:${NC}"
    cat $file
    echo
    echo -e "${Blue}==============================${NC}"
}

New() {
    local file="$1"
    local value="$2"
    echo $value | tee $file > /dev/null
}

Add() {
    local file="$1"
    local value="$2"
    echo $value | tee -a $file > /dev/null
}

Set() {
    local file="$1"
    local name="$2"
    local value="$3"
    local separator="${4:-|}"
    # update
    sed -i "s${separator}.*${name}=.*${separator}${name}=${value}${separator}" "$file"
    # insert
    grep -q "$name" $file || echo -e "\n$name=$value" | tee -a $file > /dev/null
}

Put() {
    local file="$1"
    local placeholder="$2"
    local value="$3"
    local separator="${4:-|}"
    sed -i "s${separator}@${placeholder}${separator}${value}${separator}g" $file
}

Chroot() {
    arch-chroot $Target /bin/bash -c "$*"
}

EnableLocale() {
    local name=$1
    sed -i "/#$name/s/^.//" $Target/etc/locale.gen
}

Title() {
    local value="$1"
    echo
    echo -e "${Bold}${Green}${value}${NC}"
}

SubTitle() {
    local value="$1"
    echo
    echo -e "${Green}${value}${NC}"
}

username=''
hostname=''

# Devices

devicePrefix="/dev/"
deviceMapper=$devicePrefix'mapper'

DeviceName() {
    local name=$1
    name=${name#"$devicePrefix"}
    echo "${name}"
}

DevicePath() {
    local path=$1
    if [[ $path == $devicePrefix* ]]; then
        echo $path
    else
        echo $devicePrefix$path
    fi
}

DeviceMiB() {
    local path=$(DevicePath $1)
    local size=$(lsblk $path -o path,SIZE,TYPE --byte | grep disk | awk '{print $2}')
    echo $(($size/1024/1024))
}

DeviceGiB() {
    local path=$(DevicePath $1)
    local size=$(DeviceMiB $path)
    size=$(($size/1024))
    echo $size
}

DeviceModel() {
    local path=$(DevicePath $1)
    local model=$(lsblk $path -o path,TYPE,MODEL | grep disk | awk '{$1=$2=""; print $0}' | awk '{$1=$1}1')
    echo $model
}

DeviceInfo() {
    local name=$(DeviceName $1)
    local path=$(DevicePath $1)
    local size=$(DeviceGiB $path)
    local model=$(DeviceModel $path)
    echo "$name [$size GiB] $model"
}

DevicePartition() {
    local device=$1
    local number=$2
    if [[ $device == *"nvme"* ]]; then
        echo ${device}p${number}
    else
        echo ${device}${number}
    fi
}

DevicePartitionsCount() {
    local path=$(DevicePath $1)
    local partitions=$(lsblk $path -o NAME,TYPE --list | grep part | awk '{print $1}')
    local n=$(echo $partitions | wc -w)
    echo "$n"
}

# Partitions

PartitionMiB() {
    local path=$(DevicePath $1)
    local size=$(lsblk $path -o NAME,SIZE,TYPE --byte | grep part | awk '{print $2}')
    echo $(($size/1024/1024))
}

PartitionGiB() {
    local size=$(PartitionMiB $1)
    size=$(($size/1024))
    echo $size
}

PartitionInfo() {
    local name=$(DeviceName $1)
    local path=$(DevicePath $1)
    local size=$(PartitionGiB $path)
    echo "$name [$size GiB]"
}

PartitionUUID() {
    local path=$(DevicePath $1)
    local uuid=$(blkid -s UUID -o value $path)
    echo $uuid
}

# Mounts

ShowMounts() {
    echo -e "${Purple}mounts:${NC}"
    lsblk -o NAME,PTTYPE,FSTYPE,SIZE,FSUSE%,RO,RM,TYPE,LABEL,MOUNTPOINTS,UUID,STATE
    echo -e "${Purple}[$deviceMapper]${NC}"
    ls -la $deviceMapper | grep '\->' | awk '{print $9}'
}

# Select devices

devices=''

LoadDevices() {
    devices=$(lsblk -o NAME,TYPE | grep disk | awk '{print $1}')
}

ShowDevices() {
    Title "Devices"
    local n=0
    for name in $devices
    do
        n=$((n+1))
        echo "[$n] $(DeviceInfo $name)"
    done
}

DevicesCount() {
    local n=$(echo $devices | wc -w)
    echo "$n"
}

CheckDevices() {
    local n=$(DevicesCount)
    local m=2
    if (( $n < $m )); then
        Fatal "There must be at least $m devices, but found only $n"
    fi
}

CheckBootDeviceSize() {
    local sizeMiB=$(DeviceMiB $bootDev)
    local minMiB=$((EfiMiB+BootMiB+IsoMiB+100))
    if (( sizeMiB < minMiB )); then
        Fatal "Error: size of $bootDev ($sizeMiB MiB) very small, it is necessary to at least $minMiB MiB"
    fi
}

CheckRootDeviceSize() {
    local sizeGiB=$(DeviceGiB $rootDev)
    local minGiB=$((LvmRootGiB+4))
    if (( sizeGiB < minGiB )); then
        Fatal "Error: size of $rootDev ($sizeGiB GiB) very small, it is necessary to at least $minGiB GiB"
    fi
}

GetDevice() {
    local index=$1
    local device=$(echo $devices | awk '{print $'$index'}')
    echo $device
}

GetEdgeDevice() {
    local name=$1
    local edge=$2
    local device=$(echo $devices | tr ' ' '\n' | grep $name | $edge -n 1)
    echo $device
}

bootDev=''
rootDev=''

AutoSelectDevices() {
    bootDev=$(GetEdgeDevice sd tail)
    rootDev=$(GetEdgeDevice nvme head)
    if [[ $rootDev == "" ]]; then
        rootDev=$(GetEdgeDevice sd head)
    fi
    if [[ $bootDev == "" ]]; then
        bootDev=$(GetEdgeDevice nvme tail)
    fi
}

SelectDevice() {
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

SelectDevices() {
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

LoadRootPartitions() {
    local path=$(DevicePath $1)
    rootPartitions=$(lsblk $path -o NAME,TYPE --list | grep part | awk '{print $1}')
}

ShowRootPartitions() {
    local n=0
    for name in $rootPartitions
    do
        n=$((n+1))
        echo "[$n] $(PartitionInfo $name)"
    done
}

RootPartitionsCount() {
    local n=$(echo $rootPartitions | wc -w)
    echo "$n"
}

SelectRootPartition() {
    echo "[0] $rootDev"
    ShowRootPartitions
    local key=''
    read -n 1 -p "$(echo -e "$Cyan$RootLabel$NC partition [default=0]: ")" key
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

CloseDevices() {
    umount "$Target/boot/efi" &> /dev/null || :
    umount "$Target/boot" &> /dev/null || :
    umount "$Target" &> /dev/null || :

    umount '/dev/'${bootDev}* &> /dev/null || :
    umount '/dev/'${rootDev}* &> /dev/null || :

    vgchange -an &> /dev/null || :

    cryptsetup luksClose $BootFS &> /dev/null || :
    cryptsetup luksClose $RootFS &> /dev/null || :
}

WipeRoot() {
    local dev=$rootDev
    local name='device'
    if [[ $rootPartition != "" ]]; then
        dev=$rootPartition
        name='partition'
    fi
    echo
    read -n 1 -p "Wipe $name $dev? y/n: " key && echo
    if [[ $key == 'y' ]]; then
        cryptsetup -q open --type plain --cipher aes-xts-plain64 --key-size 256 --key-file /dev/urandom /dev/$dev wipe
        dd bs=1M if=/dev/zero of=$deviceMapper/wipe status=progress || true
        cryptsetup close wipe
    fi
}

# Distro

OsReleaseKey() {
    local key=$1
    grep "^$key=" /etc/os-release | cut -d'=' -f2 | tr -d '"'
}

DistroID=$(OsReleaseKey 'ID')
DistroCodeName=$(OsReleaseKey 'VERSION_CODENAME')

# Install

reinstall=true

Startup() {
    if [[ $EUID != 0 ]]; then
        Fatal "The script should be run from root user"
    fi

    mkdir $TmpDir
    cd $TmpDir

    hostnamectl
    echo
    cat /etc/os-release
    echo
    echo -e "${Purple}$(uname -rmo)${NC}"
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

SelectMode() {
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

SetPersonal() {
    read -p "Username: " username
    read -p "Hostname: " hostname
}

Сonfirmation() {
    local key=''
    read -n 1 -p "$(echo -e "${Red}Attention! Are you sure you want to install system?${NC} y/n: ")" key && echo
    if [[ $key != 'y' ]]; then
        echo "cancel the installation"
        exit
    fi
}

Finish() {
    Time
    echo
    echo -e "${Green}Installation successfully completed!${NC}"
    read -n 1 -p "System reboot is required. Reboot now? y/n: " key && echo
    if [[ $key == 'y' ]]; then
        echo "rebooting..."
        reboot
    fi
}

ExtractKeys() {
    local initramfs='initramfs'
    cryptsetup luksOpen $bootPartition $BootFS
    mount --mkdir "$deviceMapper/$BootFS" $BootFS
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

payPartition=''
efiPartition=''
bootPartition=''
isoPartition=''

MakePartitions() {
    Title "Make partitions"

    local sizeMiB=$(DeviceMiB $bootDev)
    local payMiB=$((sizeMiB-EfiMiB-BootMiB-IsoMiB-2))
    local bootOffsetMiB=$((payMiB+EfiMiB))
    local isoOffsetMiB=$((bootOffsetMiB+BootMiB))

    bootDev=$(DevicePath $bootDev)
    rootDev=$(DevicePath $rootDev)

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
    partprobe $bootDev
    echo -e "${Purple}$RootLabel${NC} device info: ${Bold}${Purple}$rootDev${NC}"
    parted $rootDev print
    partprobe $rootDev

    payPartition=$(DevicePartition $bootDev 1)
    efiPartition=$(DevicePartition $bootDev 2)
    bootPartition=$(DevicePartition $bootDev 3)
    isoPartition=$(DevicePartition $bootDev 4)
    if [[ $rootPartition == "" ]]; then
        rootPartition=$(DevicePartition $rootDev 1)
    else
        rootPartition=$(DevicePath $rootPartition)
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
    cryptsetup luksOpen $bootPartition $BootFS --key-file=$BootKey

    if ! $reinstall; then
        local luksOffset=$((RootOffsetMiB*1024*2))
        dd if=/dev/urandom of=$RootKey bs=4096 count=1
        chmod u=r,go-rwx $RootKey
        cryptsetup -q luksFormat --cipher=aes-xts-plain64 --hash=sha512  --iter-time=5000 --key-size=512 --key-file=$RootKey $rootPartition --header=$RootHeader --offset=$luksOffset --luks2-keyslots-size=262144
    fi
    cryptsetup luksOpen $rootPartition $RootFS --key-file=$RootKey --header $RootHeader

    mkfs.ext4 -F $deviceMapper/$BootFS

    if ! $reinstall; then
        pvcreate $deviceMapper/$RootFS
        vgcreate $LvmVG $deviceMapper/$RootFS
        lvcreate -n $LvmRoot -L ${LvmRootGiB}G $LvmVG
        lvcreate -n $LvmExt -l 100%FREE $LvmVG
        mkfs.ext4 $deviceMapper/${LvmVG}-${LvmExt}
    fi
    mkfs.ext4 -F $deviceMapper/${LvmVG}-${LvmRoot}

    local targetRoot="$Target"
    local targetBoot="$Target/boot"
    local targetEfi="$Target/boot/efi"
    local targetMntExt="$Target/$MntExt"

    mount --mkdir "$deviceMapper/$LvmVG-$LvmRoot" $targetRoot
    mount --mkdir "$deviceMapper/$LvmVG-$LvmExt" $targetMntExt
    mount --mkdir "$deviceMapper/$BootFS" $targetBoot
    mount --mkdir $efiPartition $targetEfi

    ShowMounts
}

InstallArch() {
    # Syncronise the Package Database
    pacman -Syy

    # Install the Arch Base System
    #linux-firmware
    #x86-video-intel — Это для интел
    #xf86-vide-amdgpu xf86-video-ati — Это для AMD
    #xf86-video-nouveau — Это для нвидиа
    pacstrap $Target base base-devel linux intel-ucode grub lvm2 nano dhcpcd iproute2 networkmanager cryptsetup openssh git
}

InstallUbuntu() {
    apt update
    apt install -y debootstrap arch-install-scripts # arch-install-scripts for genfstab
    debootstrap --arch=amd64 $DistroCodeName $Target http://archive.ubuntu.com/ubuntu/
}

Install() {
    Title "Install"
    case $DistroID in
        arch)
            InstallArch
            ;;
        ubuntu)
            InstallUbuntu
            ;;
    esac
}

InstallInit() {
    Chroot "apt install -y linux-generic lvm2 cryptsetup grub-efi-amd64-signed"
}

bootUUID=''
bootUuid=''
bootfsUUID=''
rootUUID=''
isoUUID=''

GetUUIDs() {
    bootUUID=$(PartitionUUID $bootPartition)
    bootUuid=$(echo "$bootUUID" | tr -d "-")
    bootfsUUID=$(PartitionUUID $deviceMapper/$BootFS)
    rootUUID=$(PartitionUUID $rootPartition)
    isoUUID=$(PartitionUUID $isoPartition)
}

CopySecrets() {
    mkdir -p $Target/$Secrets
    cp $RootHeader $Target/$Secrets
    cp $BootKey $Target/$Secrets
    cp $RootKey $Target/$Secrets
}

SetInitHookArch() {
    local encryptHook='encrypt2'
    local encryptHookFile=$Target/etc/initcpio/hooks/$encryptHook
    cp $PwdDir/crypthook $encryptHookFile
    cp $Target/usr/lib/initcpio/install/encrypt $Target/etc/initcpio/install/$encryptHook

    Put $encryptHookFile "BootUUID" $bootUUID
    Put $encryptHookFile "BootKey" $Secrets/$BootKey
    Put $encryptHookFile "BootFS" $BootFS
    Put $encryptHookFile "RootUUID" $rootUUID
    Put $encryptHookFile "RootFS" $RootFS
    Put $encryptHookFile "RootKey" $Secrets/$RootKey
    Put $encryptHookFile "RootHeader" $Secrets/$RootHeaders
    Cat $encryptHookFile

    local mkinitcpio=$Target/etc/mkinitcpio.conf
    local secretFiles="$Secrets/$BootKey $Secrets/$RootKey $Secrets/$RootHeader"
    cp $mkinitcpio $mkinitcpio.bk
    cp $PwdDir/'mkinitcpio-arch.conf' $mkinitcpio
    Put $mkinitcpio "FILES" $secretFiles
    Put $mkinitcpio "ENCRYPT" $encryptHook
    Cat $mkinitcpio
}

SetInitHookUbuntu() {
    local lksdir='/tmp'
    # to be able to update the kernel and rebuild initrd
    lksdir=$Secrets

    local hook=$Target/etc/cryptsetup-initramfs/conf-hook
    Set $hook "KEYFILE_PATTERN" "${Secrets}/*.key"
    Cat $hook
    local initramfs=$Target/etc/initramfs-tools/initramfs.conf
    Set $initramfs "UMASK" "0077"
    Cat $initramfs

    local copy=$Target/etc/initramfs-tools/hooks/copy
    Add $copy '#!/bin/sh'
    Add $copy 'mkdir -p ${DESTDIR}'"$Secrets"
    Add $copy "cp $lksdir/$RootHeader"' ${DESTDIR}'"$Secrets"
    Add $copy 'exit 0'
    chmod +x $copy
    Cat $copy
}

SetInitHook() {
    case $DistroID in
        arch)
            SetInitHookArch
            ;;
        ubuntu)
            SetInitHookUbuntu
            ;;
    esac
}

SetFstab() {
    local fstab=$Target/etc/fstab
    genfstab -U $Target >> $fstab
    Cat $fstab

    case $DistroID in
        ubuntu)
            #sudo sed -i '\|boot/efi|d' $fstab
            #local efiUUID=$(PartitionUUID $efiPartition)
            #echo "UUID=$efiUUID /boot/efi vfat umask=0077 0 1" | tee -a $fstab
            #Cat $fstab

            local crypttab=$Target/etc/crypttab
            Add $crypttab "$BootFS UUID=$bootUUID $Secrets/$BootKey luks"
            Add $crypttab "$RootFS UUID=$rootUUID $Secrets/$RootKey luks,header=$Secrets/$RootHeader"
            Cat $crypttab
            ;;
    esac
}

SetGrub() {
    local grub=$Target/etc/default/grub
    # Allow booting from /boot on a LUKS encrypted partition
    Set $grub "GRUB_ENABLE_CRYPTODISK" "y"
    # Disable discover other OS installed
    Set $grub "GRUB_DISABLE_OS_PROBER" "true"
    Cat $grub

    local grubconf=$Target/boot/grub/grub.cfg
    mkdir -p $Target/boot/grub
    cp $PwdDir/grub.cfg $grubconf
    Put $grubconf "BootUUID" $bootUUID
    Put $grubconf "bootUuid" $bootUuid
    Put $grubconf "BootfsUUID" $bootfsUUID
    Put $grubconf "RootUUID" $rootUUID
    Put $grubconf "IsoUUID" $isoUUID
    Cat $grubconf
}

CreateInitramfs() {
    SubTitle "Create initramfs"
    # -c (create)
    # -k all (for all kernels)
    Chroot "update-initramfs -c -k all"
}

InstallLoader() {
    SubTitle "Install loader"
    Chroot "grub-install --no-nvram"
    Chroot 'echo "boot device: $(grub-probe -t device /boot/grub)"'
    Chroot 'echo "boot fs-uuid: $(grub-probe -t fs_uuid /boot/grub)"'
}

SetupLoader() {
    SubTitle "Setup loader"
    Chroot "update-grub"
    Chroot 'echo "boot device: $(grub-probe -t device /boot/grub)"'
    Chroot 'echo "boot fs-uuid: $(grub-probe -t fs_uuid /boot/grub)"'
    ###
    Cat $Target/boot/grub/grub.cfg
}

BasicSetup() {
    SubTitle "Basic setup"
    # -m - create home dir
    # -G - sudo group
    # -s - shell
    local g=''
    case $DistroID in
        arch)
            g='wheel'
            ;;
        ubuntu)
            g='sudo'
            ;;
    esac
    Chroot "useradd -m -G $g -s /bin/bash $username"
    echo -e "Enter ${Bold}${Green}$username${NC} ${Bold}password${NC}"
    Chroot "passwd $username"

    ln -s /usr/share/zoneinfo/$TimeZone $Target/etc/localtime

    for locale in $Locales; do
        EnableLocale "$locale.UTF-8 UTF-8"
    done

    New $Target/etc/hostname $hostname

    New $Target/etc/hosts "127.0.0.1 localhost"
    Add $Target/etc/hosts "127.0.0.1 $hostname"

    if ! $reinstall; then
        Chroot "chown -R $username:$username $targetMntExt"
    fi
}

Setup() {
    Title "Setup"
    InstallInit
    ShowMounts
    GetUUIDs
    CopySecrets
    SetInitHook
    SetFstab
    SetGrub
    CreateInitramfs
    InstallLoader
    SetupLoader
    BasicSetup
}


Startup
CheckEfi
CheckDistro
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
WipeRoot
MakePartitions
Install
Setup
Finish
