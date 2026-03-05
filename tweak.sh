#!/bin/bash

set -eu

source ./conf.sh
source ./include/tools.sh
source ./include/devices.sh
source ./include/base.sh

SrcDir=$PwdDir/tweax

Arch=$(dpkg --print-architecture)

AptList='
    htop
    btop
    iftop
    nvtop
    gpustat
    lnav
    gparted
    smartmontools

    mc
    tree
    filezilla

    git
    git-lfs

    build-essential
    pkg-config
    cmake
    gcc
    g++
    python3-dev
    python3-pip
    python3-venv
    arduino

    libfmt-dev
    libpcap-dev
    libsqlite3-dev
    libboost-all-dev
    nlohmann-json3-dev
    catch2

    virtualbox
    virtualbox-ext-pack
    virtualbox-guest-additions-iso
    wine
    winetricks
    docker.io
    docker-compose-V2

    p7zip-full
    unrar

    wget
    curl
    nmap
    socat
    ethtool
    wireshark
    traceroute

    picocom
    minicom

    vlc
    gimp
    ffmpeg
    audacity
    kazam
    vokoscreen-ng
    recordmydesktop
    simplescreenrecorder
    pulseaudio
    pulseeffects
    ubuntu-restricted-extras

    ubuntu-desktop
    imwheel
    dconf-editor
    gnome-tweaks
    gnome-shell-extensions
    gir1.2-appindicator3-0.1
    qalculate-gtk
'
SnapList='
    postman
    dbeaver-ce
    opera
    winbox
    sublime-text
'
SnapClassicList='
    code
'

user=''

GetUser() {
    local users
    mapfile -t users < <(GetUsers)
    if [ ${#users[@]} -eq 0 ]; then
        Fatal "user not found"
    else
        user="${users[0]}"
        echo
        echo -e "user: ${Bold}${Green}$user${NC}"
    fi
}

PreIntall() {
    Title "PreInstall"
    DEBIAN_FRONTEND=noninteractive
    apt update
    apt install -y ubuntu-drivers-common
}

InstallDrivers() {
    Title "Install drivers"
    ubuntu-drivers autoinstall
}

packages() {
    local list="$1"
    local packages=$(echo "$list" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
    echo "$packages"
}

AptIntall() {
    Title "Install apt"
    apt install -y $(packages "$AptList")
}

SnapIntall() {
    Title "Install snap"
    snap install $(packages "$SnapList")
}

SnapClassicIntall() {
    Title "Install snap classic"
    snap install --classic $(packages "$SnapClassicList")
}

dpkgInstall() {
    local name=$1
    local ref=$2
    SubTitle "Install $name"
    name=$(ToLower $name).deb
    echo "ref: $ref"
    wget $ref -O $name
    dpkg -i $name
}

installChrome() {
    dpkgInstall "Chrome" "https://dl.google.com/linux/direct/google-chrome-stable_current_$Arch.deb"
}

installSmartgit() {
    dpkgInstall "Smartgit" $(wget -qO - https://www.syntevo.com/smartgit/download/ | grep -Eo 'href=[^ ]+ ' | grep -Eo "https.*.deb")
}

DpkgInstall() {
    Title "Install dpkg"
    installChrome
    installSmartgit
}

installGolang() {
    SubTitle "Install Golang"
    local url=https://golang.org
    local ref=$url$(wget -qO- $url/dl/ | grep -Eo 'href="[^\"]+"' | grep -Eo "/dl/go.*linux-$DistrArch.tar.gz" -m 1)
    local name=golang.tar.gz
    echo "ref: $ref"
    wget $ref -O $name
    tar -C $OptDir -xzf $name
}

installTelegram() {
    SubTitle "Install Telegram"
    local ref=https://telegram.org/dl/desktop/linux
    local name=tsetup.tar.xz
    echo "ref: $ref"
    wget $ref -O $name
    tar -C $OptDir -xvf $name
}

installEtcher() {
    SubTitle "Install Etcher"
    local url=https://github.com/balena-io/etcher
    local ver=$(wget -qO - $url | grep -Eo 'href="[^\"]+"' | grep -Eo 'v[0-9][0-9.]+' | grep -Eo '[0-9][0-9.]+')
    local ref="$url/releases/download/v$ver/balenaEtcher-$ver-x64.AppImage"
    local name=etcher
    local dir=$OptDir/$name
    echo "ver: $ver"
    echo "ref: $ref"
    wget $ref -O $name
    mkdir $dir
    mv $name $dir/$name
}

installWinBox() {
    SubTitle "Install Winbox"
    local dir=$OptDir'/winbox'
    local ref='https://mt.lv/winbox'
    local name='winbox.exe'
    echo "ref: $ref"
    wget $ref -O $name
    mkdir $dir
    mv $name $dir
    WinBoxExe=$dir/$name
}

installStamina() {
    SubTitle "Install Stamina"
    local dir=$OptDir'/stamina'
    local ref=https://stamina.ru/files/Stamina.zip
    winetricks mfc42
    wine reg add "HKCU\Keyboard Layout\Preload" /f /v "2" /t REG_SZ /d "00000419"
    wget $ref -O stamina.zip
    unzip stamina.zip
    mkdir $dir
    mv Stamina/* $dir
    StaminaExe="$dir/stamina.exe"
    mv $dir/Stamina.exe $StaminaExe
    chown -R $user:$user $dir
}

installSysMon() {
    SubTitle "Install SysMon"
    git clone https://github.com/msw-x/sysmon
    cd sysmon
    ./install.sh
    cd ..
}

installSly() {
    SubTitle "Install Sly"
    cp -rv $SrcDir/sly $OptDir/
}

OptInstall() {
    installGolang
    installTelegram
    installEtcher
    installWinBox
    installStamina
    installSysMon
    installSly
}


Startup
CheckDistro
GetUser
Сonfirmation
PreIntall
InstallDrivers
AptIntall
SnapIntall
SnapClassicIntall
DpkgInstall
OptInstall
Finish
