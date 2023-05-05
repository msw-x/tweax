#!/bin/bash
set -eu

BootKey=boot.key
RootKey=root.key
RootHeader=root.lks
RootOffsetMiB=512

EfiMiB=100
BootMiB=2000
IsoMiB=6000

LvmRootGiB=120

CryptBootFS='bootfs'
CryptRootFS='rootfs'
LvmVG='lvm'
LvmRoot='root'
LvmExt='ext'
InitramfsSecret='/etc/secret'

MntExt='/mnt/ext'

DevListFile='dev.lst'
DevListCount=0

RootPartFile='root.lst'
RootPartCount=0

BootLabel='BOOT'
RootLabel='ROOT'

EfiFsLabel='x-usb-efi'
IsoFsLabel='x-usb-iso'
PayFsLabel='x-usb-pay'
RootTrapFsLabel='x-data'

BootDev=''
RootDev=''

TmpDir='/tmp/install-'$(date +%s%N)
PwdDir=$(pwd)
SrcDir=${PwdDir}'/src/install'

DistrName=$(cat /etc/*-release | sed -n 's/^ID=//p')
DistrVersion=$(cat /etc/*-release | sed -n 's/^DISTRIB_RELEASE=//p')
DistrCodeName=$(cat /etc/*-release | sed -n 's/^DISTRIB_CODENAME=//p')
DistrArch=$(dpkg --print-architecture)

Reinstall=true
PayPartition=''
EfiPartition=''
BootPartition=''
IsoPartition=''
RootPartition=''

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
    if [[ $RootDev == "" ]]; then
        RootDev=$(GetEdgeDevice sd head)
    fi
    if [[ $BootDev == "" ]]; then
        BootDev=$(GetEdgeDevice nvme tail)
    fi
}

function GetRootPartList {
    local rootDev=$1
    lsblk '/dev/'$rootDev -o NAME,TYPE --list | grep part | awk '{print $1}' > $RootPartFile
    RootPartCount=$(wc -l $RootPartFile | awk '{print $1}')
}

function PrintRootPartList {
    local n=0
    cat $RootPartFile | \
    while read part; do
        n=$((n+1))
        echo "[$n] $(PartitionInfo $part)"
    done
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
    local model=$(lsblk '/dev/'$1 -o NAME,TYPE,MODEL | grep disk | awk '{$1=$2=""; print $0}' | awk '{$1=$1}1')
    echo $model
}

function DeviceInfo {
    local name=$1
    local size=$(DeviceGiB $name)
    local model=$(DeviceModel $name)
    echo "$name [$size GiB] $model"
}

function PartitionMiB {
    local size=$(lsblk '/dev/'$1 -o NAME,SIZE,TYPE --byte | grep part | awk '{print $2}')
    echo $(($size/1024/1024))
}

function PartitionGiB {
    local size=$(PartitionMiB $1)
    size=$(($size/1024))
    echo $size
}

function PartitionInfo {
    local name=$1
    local size=$(PartitionGiB $name)
    echo "$name [$size GiB]"
}

function ShowMounts {
    Purple='\e[1;35m'
    NC='\e[0m'
    lsblk -o NAME,FSTYPE,SIZE,FSAVAIL,TYPE,LABEL,MOUNTPOINTS | grep -v loop
    echo -e "${Purple}[/dev/mapper]${NC}"
    ls -la /dev/mapper | grep '\->' | awk '{print $9}'
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

function SelectRootPartition {
    echo "[0] $RootDev"
    PrintRootPartList
    read -n 1 -p "$RootLabel partition [default=0]: " key
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
    RootPartition=$(DevicePatition '/dev/'$RootDev $key)
}

function SelectDevices {
    while : ; do
        AutoSelectDevices
        SelectDevice $BootLabel
        SelectDevice $RootLabel
        [[ $RootDev == $BootDev ]] || break
    done
    GetRootPartList $RootDev
    if [[ $RootPartCount > 1 ]]; then
        SelectRootPartition
    fi
    local rootpart=''
    if [[ $RootPartition != "" ]]; then
        rootpart="[$RootPartition]"
    fi
    echo "$BootLabel device: $(DeviceInfo $BootDev)"
    echo "$RootLabel device: $(DeviceInfo $RootDev) $rootpart"
}

function SelectMode {
    read -n 1 -p "Re-Install mode? y/n: " key && echo
    if [[ $key == 'n' ]]; then
        Reinstall=false
    fi
    local mode="Full-Install (erase all data on $BootLabel and $RootLabel)"
    if $Reinstall; then
        mode="Re-Install (save $PayFsLabel, $IsoFsLabel and $RootTrapFsLabel)"
    fi
    echo "Mode: $mode"
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

function ExtractKeys {
    sudo cryptsetup luksOpen $BootPartition $CryptBootFS
    sudo mkdir $CryptBootFS
    sudo mount "/dev/mapper/${CryptBootFS}" $CryptBootFS
    sudo mkdir 'initramfs'
    sudo unmkinitramfs "${CryptBootFS}/initrd.img" 'initramfs'
    sudo umount $CryptBootFS || true
    sudo cryptsetup luksClose $CryptBootFS
    sudo cp "initramfs/main/cryptroot/keyfiles/${CryptRootFS}.key" ${RootKey}
    sudo cp "initramfs/main${InitramfsSecret}/${RootHeader}" .
}

function PreInstall {
    local sizeMiB=$(DeviceMiB $BootDev)
    local minMiB=$((EfiMiB+BootMiB+IsoMiB+100))
    if (( sizeMiB < minMiB )); then
        echo "Error: size of $BootDev ($sizeMiB MiB) very small, it is necessary to at least $minMiB MiB"
        exit 1
    fi
    local payMiB=$((sizeMiB-EfiMiB-BootMiB-IsoMiB-2))
    local bootOffsetMiB=$((payMiB+EfiMiB))
    local isoOffsetMiB=$((bootOffsetMiB+BootMiB))

    BootDev='/dev/'$BootDev
    RootDev='/dev/'$RootDev

    sudo umount ${BootDev}* || true
    sudo umount ${RootDev}* || true

    if ! $Reinstall; then
        echo "make $BootLabel partition table: $BootDev"
        sudo parted --script $BootDev mklabel gpt
        sudo parted --script $BootDev mkpart primary 1MiB ${payMiB}MiB
        sudo parted --script $BootDev mkpart primary ${payMiB}MiB ${bootOffsetMiB}MiB
        sudo parted --script $BootDev mkpart primary ${bootOffsetMiB}MiB ${isoOffsetMiB}MiB
        sudo parted --script $BootDev mkpart primary ${isoOffsetMiB}MiB 100%
        sudo parted --script $BootDev set 2 boot on

        if [[ $RootPartition == "" ]]; then
            echo "make $RootLabel partition table: $RootDev"
            sudo parted --script $RootDev mklabel gpt
            sudo parted --script $RootDev mkpart primary 1MiB 100%
        fi
    fi
    sudo parted $BootDev print
    sudo parted $RootDev print

    PayPartition=$(DevicePatition $BootDev 1)
    EfiPartition=$(DevicePatition $BootDev 2)
    BootPartition=$(DevicePatition $BootDev 3)
    IsoPartition=$(DevicePatition $BootDev 4)
    if [[ $RootPartition == "" ]]; then
        RootPartition=$(DevicePatition $RootDev 1)
    fi

    if $Reinstall; then
        ExtractKeys
    fi

    sudo mkfs.fat -F32 $EfiPartition -n $EfiFsLabel
    if ! $Reinstall; then
        sudo mkfs.fat -F32 $PayPartition -n $PayFsLabel
        sudo mkfs.ext4 -F $IsoPartition -L $IsoFsLabel
        sudo mkfs.btrfs -f $RootPartition --label $RootTrapFsLabel
    fi

    sudo dd if=/dev/urandom of=$BootKey bs=4096 count=1
    sudo chmod u=r,go-rwx $BootKey
    sudo cryptsetup -q luksFormat --type=luks1 --key-file=$BootKey $BootPartition
    sudo cryptsetup luksAddKey $BootPartition --key-file=$BootKey
    sudo cryptsetup luksOpen $BootPartition $CryptBootFS --key-file=$BootKey

    if ! $Reinstall; then
        local luksOffset=$((RootOffsetMiB*1024*2))
        sudo dd if=/dev/urandom of=$RootKey bs=4096 count=1
        sudo chmod u=r,go-rwx $RootKey
        sudo cryptsetup -q luksFormat --hash=sha512 --key-size=512 --key-file=$RootKey $RootPartition --header $RootHeader --offset=$luksOffset --luks2-keyslots-size=262144
    fi
    sudo cryptsetup luksOpen $RootPartition $CryptRootFS --key-file=$RootKey --header $RootHeader

    sudo mkfs.ext4 -F /dev/mapper/${CryptBootFS}

    if ! $Reinstall; then
        sudo pvcreate /dev/mapper/${CryptRootFS}
        sudo vgcreate $LvmVG /dev/mapper/${CryptRootFS}
        sudo lvcreate -n $LvmRoot -L ${LvmRootGiB}G $LvmVG
        sudo lvcreate -n $LvmExt -l 100%FREE $LvmVG
        sudo mkfs.ext4 /dev/mapper/${LvmVG}-${LvmExt}
    fi
    sudo mkfs.ext4 -F /dev/mapper/${LvmVG}-${LvmRoot}

    ShowMounts
}

function Install {
    echo "Set /dev/mapper/${CryptBootFS} as /boot"
    echo "Set /dev/mapper/${LvmVG}-${LvmRoot} as /"
    echo "After installation set: Continue testing, without rebooting"
    read -p "Press enter to continue"

    #sudo apt install -y ubiquity ubiquity-frontend-gtk
    ubiquity --no-bootloader
    #ubuntu-desktop-installer
}

function UnmountTarget {
    for ((;;))
    do
        echo "wait unmount of target..."
        sleep 1s
        if ! lsblk | grep "target"; then
            break
        fi
    done
    sleep 1s
}

function MountTarget {
    local target='/target'
    local targetRoot="${target}"
    local targetBoot="${target}/boot"
    sudo mkdir -p ${targetRoot}
    sudo mkdir -p ${targetBoot}
    sudo mount "/dev/mapper/${LvmVG}-${LvmRoot}" ${targetRoot}
    sudo mount "/dev/mapper/${CryptBootFS}" ${targetBoot}

    ShowMounts
}

function PostInstall {
    local target='/target'
    local lksdir='/tmp'
    # to be able to update the kernel and rebuild initrd
    lksdir=$InitramfsSecret

    sudo mkdir -p ${target}${lksdir}
    sudo cp ${RootHeader} ${target}${lksdir}
    sudo cp ${SrcDir}/chroot.sh ${target}/tmp
    sudo chmod +x ${target}/tmp/chroot.sh

    sudo mkdir -p ${target}${InitramfsSecret}
    sudo cp ${BootKey} ${target}${InitramfsSecret}
    sudo cp ${RootKey} ${target}${InitramfsSecret}
    echo "KEYFILE_PATTERN=${InitramfsSecret}/*.key" | sudo tee -a ${target}/etc/cryptsetup-initramfs/conf-hook
    echo "UMASK=0077" | sudo tee -a ${target}/etc/initramfs-tools/initramfs.conf

    local initramfsHookCopy=/target/etc/initramfs-tools/hooks/copy
    echo '#!/bin/sh' | sudo tee -a ${initramfsHookCopy}
    echo 'mkdir -p ${DESTDIR}'"${InitramfsSecret}" | sudo tee -a ${initramfsHookCopy}
    echo "cp ${lksdir}/${RootHeader}"' ${DESTDIR}'"${InitramfsSecret}" | sudo tee -a ${initramfsHookCopy}
    echo 'exit 0' | sudo tee -a ${initramfsHookCopy}
    sudo chmod +x ${initramfsHookCopy}

    local uuidBoot=$(blkid -s UUID -o value $BootPartition)
    local uuidRoot=$(blkid -s UUID -o value $RootPartition)
    echo "$CryptBootFS UUID=${uuidBoot} ${InitramfsSecret}/${BootKey} luks" | sudo tee -a ${target}/etc/crypttab
    echo "$CryptRootFS UUID=${uuidRoot} ${InitramfsSecret}/${RootKey} luks,header=${InitramfsSecret}/${RootHeader}" | sudo tee -a ${target}/etc/crypttab

    echo "GRUB_DEFAULT=\"ISO\"" | sudo tee -a ${target}/etc/default/grub
    echo "GRUB_ENABLE_CRYPTODISK=y" | sudo tee -a ${target}/etc/default/grub
    echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a ${target}/etc/default/grub

    local menuIsoFile=${target}/etc/grub.d/40_custom
    local uuidIso=$(blkid -s UUID -o value $IsoPartition)
    sudo bash -c 'cat >> '"$menuIsoFile"' << "EOL"
menuentry "ISO" {
   set isofile="/x.iso"
   insmod part_gpt
   insmod ext2
   search --no-floppy --fs-uuid --set $uuidIso
   loopback loop $isofile
   linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=$isofile noprompt noeject
   initrd (loop)/casper/initrd
}
EOL'
    sudo sed -i 's/$uuidIso/'"$uuidIso/g" $menuIsoFile

    sudo chmod -x ${target}/etc/grub.d/10_linux_zfs
    sudo chmod -x ${target}/etc/grub.d/20_linux_xen
    sudo chmod -x ${target}/etc/grub.d/20_memtest86+
    sudo chmod -x ${target}/etc/grub.d/30_os-prober
    sudo chmod -x ${target}/etc/grub.d/30_uefi-firmware
    sudo chmod -x ${target}/etc/grub.d/35_fwupd

    sudo sed -i '\|boot/efi|d' ${target}/etc/fstab
    local UuidEfi=$(blkid -s UUID -o value $EfiPartition)
    echo "UUID=$UuidEfi /boot/efi vfat umask=0077 0 1" | sudo tee -a ${target}/etc/fstab
    echo "/dev/mapper/${LvmVG}-${LvmExt} $MntExt ext4 defaults 0 2" | sudo tee -a ${target}/etc/fstab

    ls -1 /etc/grub.d
    cat ${menuIsoFile}
    cat ${target}/etc/default/grub
    cat ${target}/etc/fstab
    cat ${initramfsHookCopy}

    if ! $Reinstall; then
        local user=$(ls -1 ${target}/home | awk '(NR == 1)')
        local mnt=${target}/${MntExt}
        echo "user: $user"
        sudo useradd $user
        sudo mkdir $mnt
        sudo mount /dev/mapper/${LvmVG}-${LvmExt} $mnt
        sudo chown -R ${user}:${user} $mnt
    fi

    for n in proc sys dev etc/resolv.conf; do sudo mount --rbind /$n ${target}/$n; done
    sudo chroot ${target} /tmp/chroot.sh
}


Startup
Launch
GetDeviceList
PrintDeviceList
CheckDeviceList
SelectDevices
SelectMode
СonfirmationDialog
PreInstall
Install
UnmountTarget
MountTarget
PostInstall
Сompletion
