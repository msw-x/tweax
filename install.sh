#!/bin/bash

set -eu

source ./conf.sh
source ./include/tools.sh
source ./include/devices.sh
source ./include/base.sh

SrcDir=$PwdDir/tweak

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
    alacritty
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

opencvDependencies='
    git
    cmake
    pkg-config
    build-essential

    python3-dev
    python3-numpy

    openexr
    gfortran

    libavcodec-dev
    libavformat-dev
    libswscale-dev
    libavdevice-dev
    libv4l-dev
    libxvidcore-dev
    libx264-dev
    libva-dev
    libdrm-dev

    libjpeg-dev
    libpng-dev
    libtiff-dev

    libgtk-3-dev
    libtbb-dev
    liblapack-dev
    libeigen3-dev
    libdc1394-dev
    libopenexr-dev
    libopenblas-dev
    libgstreamer1.0-dev
    libgstreamer-plugins-base1.0-dev
'

installOpencv() {
    SubTitle "Install Opencv"
    
    apt install -y $(packages "$opencvDependencies")
    
    wget -O opencv.zip https://github.com/opencv/opencv/archive/master.zip
    wget -O opencv_contrib.zip https://github.com/opencv/opencv_contrib/archive/master.zip
    unzip opencv.zip
    unzip opencv_contrib.zip
    mkdir -p build && cd build

    local options='
        -D CMAKE_BUILD_TYPE=RELEASE
        -D CMAKE_INSTALL_PREFIX=/usr/local
        -D OPENCV_GENERATE_PKGCONFIG=ON
        -D OPENCV_ENABLE_NONFREE=ON
        -D OPENCV_EXTRA_MODULES_PATH=../opencv_contrib-master/modules
        ../opencv-master
    '

    local gpu=$(lspci | grep -i "3d controller" | grep -o "\[.*\]" | tr -d '[]')
    echo "GPU: $gpu"

    local CudaArch=""
    if [[ "$gpu" =~ "GeForce RTX" ]]; then
        CudaArch="8.6"
    fi

    if [ ! -z "$CudaArch" ]; then
        apt install -y nvidia-cuda-toolkit nvidia-cudnn
        local cuda="
            -D WITH_TBB=ON
            -D WITH_CUDA=ON
            -D WITH_CUDNN=ON
            -D OPENCV_DNN_CUDA=ON
            -D ENABLE_FAST_MATH=1
            -D CUDA_FAST_MATH=1
            -D CUDA_ARCH_BIN=$CudaArch
            -D WITH_CUBLAS=1
            -D WITH_OPENGL=ON
        "
        options="$cuda $options"
    fi

    cmake $options
    make -j$CpuN
    make install
    ldconfig

    cd ..
}

SrcInstall() {
    installOpencv
}

Tweak() {
    Сonfirmation
    PreInstall
    InstallDrivers
    AptInstall
    SnapInstall
    SnapClassicInstall
    DpkgInstall
    OptInstall
    SrcInstall
}

Run() {
    Startup
    CheckDistro
    GetUser
    Tweak
    Finish
}

Run
