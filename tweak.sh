#!/bin/bash

set -eu

source ./conf.sh
source ./include/tools.sh
source ./include/devices.sh
source ./include/base.sh

SrcDir=$PwdDir/tweax
OptDir=/opt

Arch=$(dpkg --print-architecture)

AptList='
    nano
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
    docker-compose-v2

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
    opera
    winbox
'
SnapClassicList='
    code
    dbeaver-ce
    sublime-text
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

PreInstall() {
    Title "PreInstall"
    export DEBIAN_FRONTEND=noninteractive
    # pre-accept the license via debconf for virtualbox-ext-pack
    echo "virtualbox-ext-pack virtualbox-ext-pack/license select true" | debconf-set-selections
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

AptInstall() {
    Title "Install apt"
    apt install -y $(packages "$AptList")
}

SnapInstall() {
    Title "Install snap"
    snap install $(packages "$SnapList")
}

SnapClassicInstall() {
    Title "Install snap classic"
    for pkg in $(packages "$SnapClassicList"); do
        snap install --classic $pkg
    done
}

dpkgInstall() {
    local name=$1
    local ref=$2
    SubTitle "Install $name"
    name=$(ToLower $name).deb
    echo "ref: $ref"
    wget $ref -O $name
    # dpkk -i $name
    # for auto install dependencies:
    apt install -y ./$name
}

installChrome() {
    dpkgInstall "Chrome" "https://dl.google.com/linux/direct/google-chrome-stable_current_$Arch.deb"
}

installSmartgit() {
    dpkgInstall "Smartgit" $(wget -qO - https://www.syntevo.com/smartgit/download/ | grep -Eo 'href=[^ ]+ ' | grep -Eo "https.*.deb")
}

installEtcher() {
    local url=https://github.com/balena-io/etcher
    local ver=$(wget -qO - $url | grep -Eo 'href="[^\"]+"' | grep -Eo 'v[0-9][0-9.]+' | grep -Eo '[0-9][0-9.]+')
    local ref="$url/releases/download/v$ver/balena-etcher_${ver}_$Arch.deb"
    dpkgInstall "Etcher" $ref
}

DpkgInstall() {
    Title "Install dpkg"
    installChrome
    installSmartgit
    installEtcher
}

installGolang() {
    SubTitle "Install Golang"
    local url=https://go.dev
    local ref=$url$(wget -qO- $url/dl/ | grep -Eo 'href="[^\"]+"' | grep -Eo "/dl/go.*linux-$Arch.tar.gz" -m 1)
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
    installSysMon
    installSly
}

Clean() {
    rm -rf ~/Documents ~/Music ~/Pictures ~/Public ~/Templates ~/Videos
}


Startup
CheckDistro
GetUser
Сonfirmation
PreInstall
InstallDrivers
AptInstall
SnapInstall
SnapClassicInstall
DpkgInstall
OptInstall
Clean
Finish
