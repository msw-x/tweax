# Devices

devicePrefix='/dev/'
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

WaitPartition() {
    local part="$1"
    local timeout="${2:-10}"
    echo "Waiting for partition $part to be created..."
    for i in $(seq 1 "$TIMEOUT"); do
        if [ -b "$part" ]; then
            echo "✓ Partition $part created successfully (attempt $i)"
            return 0
        fi
        echo "⏳ Waiting for $part... attempt $i/$timeout"
        sleep 1
    done
    echo "✗ Error: partition $part not created within $timeout seconds" >&2
    return 1
}

# Mounts

ShowMounts() {
    Title "Mounts"
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
    umount "$Target/$MntExt" &> /dev/null || :
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
    if $reinstall; then
        return
    fi
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
