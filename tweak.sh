#!/bin/bash

set -eu

source ./conf.sh
source ./include/tools.sh

SrcDir=$PwdDir/tweak
VmDir=$MntExt/ext/vm

Hole='msw'

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
    mkdir -p $ext
    mkdir -p $tmp
    ln -sf $ext $Home/ext
    ln -sf $tmp $Home/tmp
}

configureHomeConfig() {
    SubTitle "Configure Home config"
    cp -r $SrcDir/home/.config $Home/
}

configureDocker() {
    SubTitle "Configure Docker"
    # configure for resolve conflict Docker with VPN networks
    cp $SrcDir/docker/daemon.json /etc/docker
    sudo usermod -aG docker $user
}

configureArduino() {
    SubTitle "Configure Arduino"
    sudo usermod -a -G dialout $user
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

setGnomeVal() {
    local path=$1
    local name=$2
    local val=$3
    gsettings set "org.gnome.$path" "$name" "$val"
}

installSysMon() {
    SubTitle "Install SysMon"
    git clone https://github.com/msw-x/sysmon
    cd sysmon
    ./install.sh
    cd ..
}

configureGnome() {
    SubTitle "Configure Gnome"

    echo "Hint: for debug gsettings use 'dconf-editor' or 'dconf dump /'"

    setGnomeVal desktop.privacy report-technical-problems false

    setGnomeVal desktop.interface clock-show-seconds true
    setGnomeVal desktop.interface clock-show-weekday true
    setGnomeVal desktop.interface clock-show-date true
    setGnomeVal desktop.interface clock-format '24h'

    setGnomeVal desktop.interface color-scheme 'prefer-dark'
    setGnomeVal desktop.interface gtk-theme 'Yaru-dark'
    setGnomeVal desktop.interface icon-theme 'Yaru-dark'

    setGnomeVal TextEditor show-line-numbers true
    setGnomeVal TextEditor spellcheck false
    setGnomeVal TextEditor highlight-current-line true

    #setGnomeVal shell enabled-extensions \"['user-theme@gnome-shell-extensions.gcampax.github.com']\"
    setGnomeVal shell.extensions.dash-to-dock autohide true
    setGnomeVal shell.extensions.dash-to-dock dock-fixed false
    setGnomeVal shell.extensions.dash-to-dock extend-height false

    setGnomeVal desktop.input-sources xkb-options "['grp:alt_shift_toggle']"

    setGnomeVal settings-daemon.plugins.media-keys terminal "['<Alt>t']"

    setGnomeVal settings-daemon.plugins.media-keys volume-up "['<Alt>Page_Up']"
    setGnomeVal settings-daemon.plugins.media-keys volume-mute "['<Alt>Pause']"
    setGnomeVal settings-daemon.plugins.media-keys volume-down "['<Alt>Page_Down']"

    local favoriteApps="['google-chrome.desktop', 'org.gnome.Terminal.desktop', 'virtualbox.desktop', 'qalculate-gtk.desktop', 'syntevo-smartgit.desktop']"
    setGnomeVal shell favorite-apps "$favoriteApps"

    local wallpaper='wallpaper.jpg'
    cp $SrcDir/$wallpaper $Home/.$wallpaper
    setGnomeVal desktop.background picture-uri-dark file://$Home/.$wallpaper
    setGnomeVal desktop.background show-desktop-icons false

    setGnomeVal shell.extensions.ding show-home false
    setGnomeVal shell.extensions.ding show-trash false
    setGnomeVal shell.extensions.ding show-volumes false
    setGnomeVal shell.extensions.dash-to-dock show-mounts false
    setGnomeVal shell.extensions.dash-to-dock show-trash false
}

configureLocale() {
    SubTitle "Configure Locale"
    setGnomeVal desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ru')]"
    local loc="en_US.UTF-8"
    sudo update-locale LANG=$loc LC_NUMERIC=$loc LC_TIME=$loc LC_MONETARY=$loc LC_PAPER=$loc LC_NAME=$loc
    sudo update-locale LC_ADDRESS=$loc LC_TELEPHONE=$loc LC_MEASUREMENT=$loc LC_IDENTIFICATION=$loc
}

configureTelegram() {
    SubTitle "Configure Telegram"
    Nohup $OptDir/Telegram/Telegram
}

configureVirtualBox() {
    SubTitle "Configure VirtualBox"
    # enable devices (including usb)
    sudo usermod -a -G vboxusers $user
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
    installSysMon
    configureGnome
    configureLocale
    configureTelegram
    configureVirtualBox
    configureSmartgit
    configureMC
    clean
}

Run() {
    GetUser
    Configure
    ConfigureDesktop
}

Run
