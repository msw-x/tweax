#!/bin/bash

set -eu

source ./conf.sh
source ./include/tools.sh
source ./include/devices.sh
source ./include/base.sh

SrcDir=$PwdDir/tweak
OptDir=/opt
VmDir=$MntExt/ext/vm

Hole='msw'

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
    Home=/home/$user
    Media=/media/$user
}

AddAlias() {
    local alias=$*
    local file=$Home/.bashrc
    if ! grep "$alias" $file; then
        Add $file "alias $alias"
    fi
}

AddPath() {
    local path=$1
    local file=$Home/.profile
    if ! grep $path $file; then
        Add $file 'export PATH=$PATH:'$path
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

configurePath() {
    SubTitle "Configure Path"
    AddPath "$OptDir/sly"
    AddPath "$OptDir/go/bin"
    AddPath "$Home/go/bin"
    AddPath "$Home/$Hole/bin/bin/vit"
}

configureAliase() {
    SubTitle "Configure Aliase"
    AddAlias "pw='poweroff'"
    AddAlias "hs='history | grep'"
}

configureDirs() {
    SubTitle "Configure Dirs"

    ln -sf $Media $Home/usb

    mkdir $Home/$Hole
    mkln() {
        local disk=$1
        local name=$2
        ln -sf /mnt/local/$disk/$name $Home/$Hole/$name
    }
    mkln "d" "dnn"
    mkln "u" "src"
    mkln "n" "bin"
    mkln "s" "signal"
    mkln "r" "archive"
    mkln "j" "job"
    mkln "o" "msw"
    mkln "m" "music"
    mkln "p" "projects"
    mkln "w" "media"
    mkln "x" "x"

    local ext=$MntExt/ext
    local tmp=$ext/tmp
    ln -sf $ext $Home/ext
    ln -sf $tmp $Home/tmp

    mkdir -p $ext
    mkdir -p $tmp

    chown $user:$user $ext
    chown $user:$user $tmp
}

configureHomeConfig() {
    SubTitle "Configure Home config"
    cp -r $SrcDir/home/.config $Home/
    chown -R $user:$user $Home/.config
}

configureDocker() {
    SubTitle "Configure Docker"
    # configure for resolve conflict Docker with VPN networks
    cp $SrcDir/docker/daemon.json /etc/docker
    usermod -aG docker $user
}

configureArduino() {
    SubTitle "Configure Arduino"
    usermod -a -G dialout $user
}

configureGit() {
    SubTitle "Configure Git"

    local email=''
    echo "git user: $user"
    echo -n "git email: "
    read email

    git config --global user.name $user
    git config --global user.email $email

    git config --global gc.autoDetach false
    git config --global pull.rebase false

    git lfs install
}

Configure() {
    configurePath
    configureAliase

    configureDirs
    configureHomeConfig

    configureDocker
    configureArduino
    configureGit
}

configureGnome() {
    SubTitle "Configure Gnome"

    echo "Hint: for debug gsettings use 'dconf-editor' or 'dconf dump /'"

    setGnome() {
        local path=$1
        local name=$2
        local val=$3
        echo "path: $path"
        echo "name: $name"
        echo "val: $val"
        # -E (preserve-env)
        sudo -E -u $user gsettings set "org.gnome.$path" "$name" "$val"
        echo
    }

    setGnome desktop.privacy report-technical-problems false

    setGnome desktop.interface clock-show-seconds true
    setGnome desktop.interface clock-show-weekday true
    setGnome desktop.interface clock-show-date true
    setGnome desktop.interface clock-format '24h'

    setGnome desktop.interface color-scheme 'prefer-dark'
    setGnome desktop.interface gtk-theme 'Yaru-dark'
    setGnome desktop.interface icon-theme 'Yaru-dark'

    setGnome TextEditor show-line-numbers true
    setGnome TextEditor spellcheck false
    setGnome TextEditor highlight-current-line true

    #setGnome shell enabled-extensions \"['user-theme@gnome-shell-extensions.gcampax.github.com']\"
    setGnome shell.extensions.dash-to-dock autohide true
    setGnome shell.extensions.dash-to-dock dock-fixed false
    setGnome shell.extensions.dash-to-dock extend-height false

    setGnome desktop.input-sources xkb-options "['grp:alt_shift_toggle']"

    setGnome settings-daemon.plugins.media-keys terminal "['<Alt>t']"

    setGnome settings-daemon.plugins.media-keys volume-up "['<Alt>Page_Up']"
    setGnome settings-daemon.plugins.media-keys volume-mute "['<Alt>Pause']"
    setGnome settings-daemon.plugins.media-keys volume-down "['<Alt>Page_Down']"

    local favoriteApps="['google-chrome.desktop', 'org.gnome.Terminal.desktop', 'virtualbox.desktop', 'qalculate-gtk.desktop', 'syntevo-smartgit.desktop']"
    setGnome shell favorite-apps "$favoriteApps"

    local wallpaper='wallpaper.jpg'
    cp $SrcDir/$wallpaper $Home/.$wallpaper
    setGnome desktop.background picture-uri-dark file://$Home/.$wallpaper
    setGnome desktop.background show-desktop-icons false

    setGnome shell.extensions.ding show-home false
    setGnome shell.extensions.ding show-trash false
    setGnome shell.extensions.ding show-volumes false
    setGnome shell.extensions.dash-to-dock show-mounts false
    setGnome shell.extensions.dash-to-dock show-trash false
}

configureLocale() {
    SubTitle "Configure Locale"
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ru')]"
    local loc="en_US.UTF-8"
    update-locale LANG=$loc LC_NUMERIC=$loc LC_TIME=$loc LC_MONETARY=$loc LC_PAPER=$loc LC_NAME=$loc
    update-locale LC_ADDRESS=$loc LC_TELEPHONE=$loc LC_MEASUREMENT=$loc LC_IDENTIFICATION=$loc
}

configureTelegram() {
    SubTitle "Configure Telegram"
    Nohup $OptDir/Telegram/Telegram
}

configureVirtualBox() {
    SubTitle "Configure VirtualBox"
    # enable devices (including usb)
    usermod -a -G vboxusers $user
    Nohup virtualbox
    local key='n'
    until [ $key == 'y' ]; do
        read -n 1 -p "Please close VirtualBox. Continue configure? y/n: " key && echo
    done
    local conf="$Home/.config/VirtualBox/VirtualBox.xml"
    local exp='(defaultMachineFolder=)"[^\"]+"'
    local path="\"$VmDir\""
    sed -i -E "s|$exp|\1$path|" $conf
}

configureSmartgit() {
    SubTitle "Configure Smartgit"
    Nohup /usr/share/smartgit/bin/smartgit.sh
    echo "select 'Non-commercial use only'"
    local key='n'
    until [ $key == 'y' ]; do
        read -n 1 -p "Smartgit ready for configure? y/n: " key && echo
    done
    local conf="preferences.yml"
    local dir="$Home/.config/smartgit"
    local ver=$(ls -1 $dir | awk '/[0-9]/{print $1; exit}')
    conf="$dir/$ver/$conf"
    echo "ver: $ver"
    echo "conf: $conf"
    local dateFormat="dateFormat: {datePattern: dd.MM.yyyy, timePattern: 'HH:mm', showTimeForLastDays: false}"
    sed -i 's/^dateFormat:.*/$dateFormat/' $conf
}

configureMC() {
    SubTitle "Configure mc"
    local conf="$Home/.config/mc/ini"
    Set $conf "old_esc_mode" "true"
    Set $conf "old_esc_mode_timeout" "1000"
    Set $conf "skin" "yadt256-defbg"
}

clean() {
    rm -rf ~/Documents ~/Music ~/Pictures ~/Public ~/Templates ~/Videos
}

ConfigureDesktop() {
    configureGnome
    configureLocale
    configureTelegram
    configureVirtualBox
    configureSmartgit
    configureMC
    clean
}

Tweak() {
    local desktopIsRunning=0
    if pgrep -u "$user" -f "X|Xorg|gnome-shell|xfce4-session" >/dev/null 2>&1; then
        desktopIsRunning=1
    fi
    if (( $desktopIsRunning )); then
        local key=''
        echo
        read -n 1 -p "Configure only desktop environment? y/n: " key && echo
        if [[ $key == 'y' ]]; then
            ConfigureDesktop
            return
        fi
    fi
    Сonfirmation
    PreInstall
    InstallDrivers
    AptInstall
    SnapInstall
    SnapClassicInstall
    DpkgInstall
    OptInstall
    SrcInstall
    Configure
    if (( $desktopIsRunning )); then
        ConfigureDesktop
    fi
}


Startup
CheckDistro
GetUser
Tweak
Finish
