#!/bin/bash

set -eu

source ./conf.sh
source ./include/tools.sh
source ./include/devices.sh
source ./include/base.sh

SrcDir=$PwdDir/init

reinstall=true

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

username=''
hostname=''

SetPersonal() {
    read -p "Username: " username
    read -p "Hostname: " hostname
}

MakePartitions() {
    Title "Make partitions"

    local sizeMiB=$(DeviceMiB $bootDev)
    local payMiB=$((sizeMiB-EfiMiB-BootMiB-IsoMiB-2))
    local bootOffsetMiB=$((payMiB+EfiMiB))
    local isoOffsetMiB=$((bootOffsetMiB+BootMiB))

    DefineBoot
    DefineRoot

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

    ProbeBoot
    ProbeRoot

    ShowBoot
    ShowRoot

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
    OpenRoot

    mkfs.ext4 -F $mapBootFS

    if ! $reinstall; then
        pvcreate $mapRootFS
        vgcreate $LvmVG $mapRootFS
        lvcreate -n $LvmRoot -L ${LvmRootGiB}G $LvmVG
        lvcreate -n $LvmExt -l 100%FREE $LvmVG
        mkfs.ext4 $mapLvmExt
    fi
    mkfs.ext4 -F $mapLvmRoot

    MountLvmRoot
    MountLvmExt
    MountBoot
    MountEfi

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
    case $DistroID in
        arch)
            ;;
        ubuntu)
            Chroot "apt install -y linux-generic lvm2 cryptsetup grub-efi-amd64-signed"
            ;;
    esac
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
    cp $SrcDir/crypthook $encryptHookFile
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
    cp $SrcDir/mkinitcpio.conf $mkinitcpio
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
    cp $SrcDir/grub.cfg $grubconf
    Put $grubconf "BootUUID" $bootUUID
    Put $grubconf "bootUuid" $bootUuid
    Put $grubconf "BootfsUUID" $bootfsUUID
    Put $grubconf "RootUUID" $rootUUID
    Put $grubconf "IsoUUID" $isoUUID
    Put $grubconf "DistroID" $DistroID
    Put $grubconf "MapLvmRoot" $mapLvmRoot
    Cat $grubconf
}

CreateInitramfs() {
    SubTitle "Create initramfs"
    # -c (create)
    # -k all (for all kernels)
    Chroot "update-initramfs -c -k all"

    ### Chroot "mkinitcpio -P"
}

InstallLoader() {
    SubTitle "Install loader"
    Chroot "grub-install --no-nvram"
    Chroot 'echo "boot device: $(grub-probe -t device /boot/grub)"'
    Chroot 'echo "boot fs-uuid: $(grub-probe -t fs_uuid /boot/grub)"'
}

SetupLoader() {
    SubTitle "Setup loader"
    Chroot 'echo "boot device: $(grub-probe -t device /boot/grub)"'
    Chroot 'echo "boot fs-uuid: $(grub-probe -t fs_uuid /boot/grub)"'
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

    ln -sf /usr/share/zoneinfo/$TimeZone $Target/etc/localtime

    local localegen=$Target/etc/locale.gen
    for locale in $Locales; do
        local name="$locale.UTF-8"
        sed -i "/#.*$name/s/^.//" $localegen
    done
    sed -i 's/^[[:space:]]*//' $localegen
    Chroot "locale-gen"
    Chroot "locale -a"

    ### Chroot "hwclock --systohc --utc"

    New $Target/etc/hostname $hostname

    New $Target/etc/hosts "127.0.0.1 localhost"
    Add $Target/etc/hosts "127.0.0.1 $hostname"

    if ! $reinstall; then
        Chroot "chown -R $username:$username $MntExt"
    fi
}

MakeInet() {
    SubTitle "Internet"
    echo "dev: $inetDev"
    echo "ip: $inetIp"
    echo "gw: $inetGw"
    echo "dns: $inetDns"
    local inet="$Target/home/$username/inet.sh"
    cp $SrcDir/init/inet.sh $inet
    Put $inet "Dev" $inetDev
    Put $inet "Ip" $inetIp
    Put $inet "Gw" $inetGw
    Put $inet "Dns" $inetDns
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
    GetInet
    MakeInet
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
