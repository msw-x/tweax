#!/bin/bash

BootKey=boot.key
RootKey=root.key
RootHeader=root.lks
RootOffsetMiB=512

LvmRootGiB=80

CryptBootFS='bootfs'
CryptRootFS='rootfs'
LvmVG='lvm'
LvmRoot='root'
LvmExt='ext'

DevListFile='dev.lst'
DevListCount=0

BootLabel='BOOT'
RootLabel='ROOT'

BootDev=''
RootDev=''

TmpDir='/tmp/install-'$(date +%s%N)
PwdDir=$(pwd)

DistrName=$(cat /etc/*-release | sed -n 's/^ID=//p')
DistrVersion=$(cat /etc/*-release | sed -n 's/^DISTRIB_RELEASE=//p')
DistrCodeName=$(cat /etc/*-release | sed -n 's/^DISTRIB_CODENAME=//p')
DistrArch=$(dpkg --print-architecture)

function GetDeviceList {
    lsblk -o NAME,TYPE | grep disk | awk '{print $1}' > $DevListFile
    DevListCount=$(wc -l $DevListFile | awk '{print $1}')
}

function PrintDeviceList {
    local n=0
    cat $DevListFile | \
    while read dev; do
        n=$((n+1))
        echo "[$n] $(DeviceInfo $dev)"
    done
}

function GetDevice {
    local index=$1
    local device=$(awk 'NR=='$index $DevListFile)
    echo $device
}

function GetEdgeDevice {
    local name=$1
    local edge=$2
    local device=$(cat $DevListFile | grep $name | $edge -n 1)
    echo $device
}

function AutoSelectDevices {
    BootDev=$(GetEdgeDevice sd tail)
    RootDev=$(GetEdgeDevice nvme head)
    if [[ RootDev == "" ]]; then
        RootDev=$(GetEdgeDevice sd head)
    fi
    if [[ BootDev == "" ]]; then
        BootDev=$(GetEdgeDevice nvme tail)
    fi
}

function DevicePatition {
    local device=$1
    local number=$2
    if [[ $device == *"nvme"* ]]; then
        echo ${device}p${number}
    else
        echo ${device}${number}
    fi
}

function DeviceMiB {
    local size=$(lsblk '/dev/'$1 -o NAME,SIZE,TYPE --byte | grep disk | awk '{print $2}')
    echo $(($size/1024/1024))
}

function DeviceGiB {
    local size=$(DeviceMiB $1)
    size=$(($size/1024))
    echo $size
}

function DeviceModel {
    local model=$(lsblk '/dev/'$1 -o NAME,MODEL,TYPE | grep disk | awk '{print $2}')
    echo $model
}

function DeviceInfo {
    local name=$1
    local size=$(DeviceGiB $name)
    local model=$(DeviceModel $name)
    echo "$name [$size GiB] $model"
}

function SelectDevice {
    local label=$1
    local device=$BootDev
    if [[ $label == $RootLabel ]]; then
        device=$RootDev
    fi
    read -n 1 -p "$label device [default=$device]: " key
    if [[ $key != "" ]]; then
        device=$(GetDevice $key)
        echo
    fi
    if [[ $label == $RootLabel ]]; then
        RootDev=$device
    else
        BootDev=$device
    fi
}

function CheckDeviceList {
    if (( $DevListCount < 2 )); then
        echo "Error: there must be at least 2 devices, but found only $DevListCount"
        exit 1
    fi
}

function SelectDevices {
    while : ; do
        AutoSelectDevices
        SelectDevice $BootLabel
        SelectDevice $RootLabel
        [[ $RootDev == $BootDev ]] || break
    done
    echo "$BootLabel device: $(DeviceInfo $BootDev)"
    echo "$RootLabel device: $(DeviceInfo $RootDev)"
}

function Launch {
    echo "Install ${DistrName} ${DistrVersion} (${DistrCodeName}) ${DistrArch}"
    if [[ $EUID == 0 ]]; then
        Fatal "the script should not be run from root"
    fi
}

function Startup {
    echo "Startup"
    mkdir ${TmpDir}
    cd ${TmpDir}

    if sudo grep timestamp_timeout /etc/sudoers >/dev/null; then
        echo "Warning: can't disable sudo timeout"
    else
        sudo sed -i "10i Defaults        timestamp_timeout=-1" /etc/sudoers
    fi
}

function СonfirmationDialog {
    read -n 1 -p "Attention! Are you sure you want to install system? y/n: " key && echo
    if [[ $key != 'y' ]]; then
        echo "cancel the installation"
        exit
    fi
}

function Сompletion {
    echo "Installation successfully completed!"
    read -n 1 -p "System reboot is required. Reboot now? y/n: " key && echo
    if [[ $key == 'y' ]]; then
        echo "rebooting..."
        reboot
    fi
}

PayPartition=''
EfiPartition=''
BootPartition=''
RootPartition=''

function PreInstall {
    local sizeMiB=$(DeviceMiB $BootDev)
    local efiMiB=100
    local bootMiB=500
    local payMib=$((sizeMiB-efiMiB-bootMiB-2))
    BootDev='/dev/'$BootDev
    RootDev='/dev/'$RootDev

    sudo umount ${BootDev}*
    sudo umount ${RootDev}*

    echo "make $BootLabel partition table: $BootDev"
    sudo parted $BootDev mklabel gpt
    sudo parted $BootDev mkpart primary 1MiB ${payMib}MiB
    sudo parted $BootDev mkpart primary ${payMib}MiB $((payMib+efiMiB))MiB
    sudo parted $BootDev mkpart primary $((payMib+efiMiB))MiB 100%
    sudo parted $BootDev set 2 boot on
    sudo parted $BootDev print

    echo "make $RootLabel partition table: $RootDev"
    sudo parted $RootDev mklabel gpt
    sudo parted $RootDev mkpart primary 1MiB 100%
    sudo parted $RootDev print

    PayPartition=$(DevicePatition $BootDev 1)
    EfiPartition=$(DevicePatition $BootDev 2)
    BootPartition=$(DevicePatition $BootDev 3)
    RootPartition=$(DevicePatition $RootDev 1)

    sudo mkfs.fat -F32 $PayPartition
    sudo mkfs.fat -F32 $EfiPartition
    sudo mkfs.btrfs -f $RootPartition

    local LuksOffset=$((RootOffsetMiB*1024*2))

    sudo dd if=/dev/urandom of=$BootKey bs=4096 count=1
    sudo chmod u=r,go-rwx $BootKey
    sudo cryptsetup luksFormat --type=luks1 --key-file=$BootKey $BootPartition
    sudo cryptsetup luksAddKey $BootPartition
    sudo cryptsetup luksOpen $BootPartition $CryptBootFS --key-file=$BootKey

    sudo dd if=/dev/urandom of=$RootKey bs=4096 count=1
    sudo chmod u=r,go-rwx $RootKey
    sudo cryptsetup luksFormat --hash=sha512 --key-size=512 --key-file=$RootKey $RootPartition --header $RootHeader --offset=$LuksOffset --luks2-keyslots-size=262144
    sudo cryptsetup luksOpen $RootPartition $CryptRootFS --key-file=$RootKey --header $RootHeader

    sudo pvcreate /dev/mapper/${CryptRootFS}
    sudo vgcreate $LvmVG /dev/mapper/${CryptRootFS}
    sudo lvcreate -n $LvmRoot -L ${LvmRootGiB}G $LvmVG
    sudo lvcreate -n $LvmExt -l 100%FREE $LvmVG

    sudo mkfs.ext4 /dev/mapper/${CryptBootFS}
    sudo mkfs.ext4 /dev/mapper/${LvmVG}-${LvmRoot}
    sudo mkfs.ext4 /dev/mapper/${LvmVG}-${LvmExt}

    lsblk
}

function Install {
    echo "Set /dev/mapper/${CryptBootFS} as /boot"
    echo "Set /dev/mapper/${LvmVG}-${LvmRoot} as /"
    echo "After installation set: Continue testing, without rebooting"
    read -p "Press enter to continue"

    ubiquity --no-bootloader
}

function PostInstall {
    local target='/target'
    local initramfsSecret='/etc/secret'

    sudo cp ${RootHeader} ${target}/tmp
    sudo cp ${PwdDir}/chroot.sh ${target}/tmp

    sudo mkdir -p ${target}/etc/secret
    sudo cp ${BootKey} ${target}/etc/secret
    sudo cp ${RootKey} ${target}/etc/secret
    echo "KEYFILE_PATTERN=/etc/secret/*.key" | sudo tee -a ${target}/etc/cryptsetup-initramfs/conf-hook
    echo "UMASK=0077" | sudo tee -a ${target}/etc/initramfs-tools/initramfs.conf

    local initramfsHookCopy=/target/etc/initramfs-tools/hooks/copy
    echo '#!/bin/sh' | sudo tee -a ${initramfsHookCopy}
    echo 'mkdir -p ${DESTDIR}'"${initramfsSecret}" | sudo tee -a ${initramfsHookCopy}
    echo "cp /tmp/${RootHeader}"' ${DESTDIR}'"${initramfsSecret}" | sudo tee -a ${initramfsHookCopy}
    echo 'exit 0' | sudo tee -a ${initramfsHookCopy}
    sudo chmod +x ${initramfsHookCopy}

    local UuidBoot=$(blkid -s UUID -o value $BootPartition)
    local UuidRoot=$(blkid -s UUID -o value $RootPartition)
    echo "$CryptBootFS UUID=${UuidBoot} ${initramfsSecret}/${BootKey} luks" | sudo tee -a ${target}/etc/crypttab
    echo "$CryptRootFS UUID=${UuidRoot} ${initramfsSecret}/${RootKey} luks,header=${initramfsSecret}/${RootHeader}" | sudo tee -a ${target}/etc/crypttab

    echo "GRUB_ENABLE_CRYPTODISK=y" | sudo tee -a ${target}/etc/default/grub
    echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a ${target}/etc/default/grub

    cat ${initramfsHookCopy}
    cat ${target}/etc/default/grub

    sudo mount /dev/mapper/${CryptBootFS} ${target}/boot
    for n in proc sys dev etc/resolv.conf; do sudo mount --rbind /$n /target/$n; done
    sudo chroot /target /tmp/chroot.sh $EfiPartition
}


Startup
Launch
GetDeviceList
PrintDeviceList
CheckDeviceList
SelectDevices
СonfirmationDialog
PreInstall
Install
PostInstall
Сompletion
