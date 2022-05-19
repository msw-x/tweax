#!/bin/bash

start=$(date +%s)

TmpDir='/tmp/install-'$(date +%s%N)
PwdDir=$(pwd)

DistrName=$(cat /etc/*-release | sed -n 's/^ID=//p')
DistrVersion=$(cat /etc/*-release | sed -n 's/^DISTRIB_RELEASE=//p')
DistrCodeName=$(cat /etc/*-release | sed -n 's/^DISTRIB_CODENAME=//p')
DistrArch=$(dpkg --print-architecture)

CpuCoreCount=$(grep ^siblings /proc/cpuinfo | uniq | awk '{print $3}')

User=$(who | awk '(NR == 1)' | awk '{print $1}')
Home='/home/'$User
Media='/media/'$User
OptDir='/opt'
MntExt='/mnt/ext'
VmPath=$MntExt'/vm'

SrcDir=$PwdDir'/src'
SrcHomeDir=$SrcDir'/home'
SrcDconfDir=$SrcDir'/dconf'
SrcDebDir=$SrcDir'/deb'

SourcesListFile="/etc/apt/sources.list"

StepFile=$PwdDir'/step'

Wallpaper="wallpaper.jpg"

GitUser=$User
GitEmail=$(cat email)

PrintCommands=1
PerformCommands=1

Step=-1
OneStep=-1
InitStep=0


function PrintTime {
    echo "execution time $(date -d @$(($(date +%s)-$start)) +"%Mm %Ss")"
}

function Fatal {
    msg=$*
    step=""
    if [[ $Step != -1 ]]; then
        step="[$Step]"
    fi
    PrintTime
    if [[ $msg == "" ]]; then
        echo "[ERROR]${step}"
    else
        echo "[ERROR]${step}: ${msg}"
    fi
    exit 1
}

function Echo {
    if [[ $PrintCommands == 1 ]]; then
        echo $@
    fi
}

function PrintTitle {
    title=$*
    nl=""
    if [[ $PrintCommands == 1 ]]; then
        nl="\n"
    fi
    if [[ $title != "" ]]; then
        if [[ $Step == -1 ]]; then
            printf "${nl}${title}\n"
        else
            printf "${nl}[$Step]: ${title}\n"
        fi
    fi
}

function PrintSubTitle {
    title=$*
    nl=""
    if [[ $PrintCommands == 1 ]]; then
        nl="\n"
    fi
    if [[ $title != "" ]]; then
        printf "${nl}{$Step}: ${title}\n"
    fi
}

function Exec {
    PrintSubTitle $2
    Echo $1
    if [[ $PerformCommands == 1 ]]; then
        if ! eval $1; then
            Fatal
        fi
    fi
}

function Exec2 {
    PrintSubTitle $2
    Echo $1
    if [[ $PerformCommands == 1 ]]; then
        if ! eval $1; then
            Echo "Error. Attempt to repeat"
            if ! eval $1; then
                Fatal
            fi
        fi
    fi
}

function AptInstall {
    cmd=$1
    title=$2
    if [[ $title == "" ]]; then
        title=$cmd
    fi
    Exec2 'sudo apt install -y '$cmd "install ${title}"
}

function AptInstallFix {
    cmd=$1
    title=$2
    if [[ $title == "" ]]; then
        title=$cmd
    fi
    Exec 'sudo apt install -y '$cmd' --fix-missing' "install ${title}"
}

function NextStep {
    Step=$(($Step+1))
}

function AddToFstab {
    s=$*
    Exec "echo \"${s}\" | sudo tee -a /etc/fstab"
}

function AddToBashRC {
    s=$*
    Exec "echo \"${s}\" | tee -a ${Home}/.bashrc"
}

function AddToProfile {
    s=$*
    Exec "echo '${s}' | tee -a ${Home}/.profile"
}

function AddAliase {
    alias=$*
    if grep "$alias" ${Home}/.bashrc >/dev/null; then
        Echo "[Warning] alias ${alias} already exist"
    else
        AddToBashRC "alias "$alias
    fi
}

function AddPath {
    path=$*
    if grep $path ${Home}/.profile >/dev/null; then
        Echo "[Warning] path ${path} already exist"
    else
        AddToProfile 'export PATH=$PATH:'$path
    fi
}

function AddAptPortSource {
    suffix=$1
    if [[ $suffix != "" ]]; then
        suffix="-${suffix}"
    fi
    s="deb [arch=armhf,arm64] http://ports.ubuntu.com/ ${DistrCodeName}${suffix} main restricted universe multiverse"
    Exec "echo '${s}' | sudo tee -a ${SourcesListFile}"
}

function CheckStepIfDisabled {
    for i in $DisabledStepsList; do
        if (( $i == $1 )); then
            return 1
        fi
    done
    return 0
}

function CheckStep {
    if (( OneStep != -1 )); then
        if (( Step == OneStep )); then
            return 0
        fi
        return 1
    fi
    if (( Step >= InitStep )) && CheckStepIfDisabled Step; then
        if [[ $PerformCommands == 1 ]]; then
            echo "$Step" > "$StepFile"
        fi
        return 0
    fi
    return 1
}

for i in "$@"; do
    case $i in
        help)
            echo "help         - print this help"
            echo "list         - print list of operations"
            echo "list-slim    - print short list of operations"
            echo "step         - initial step"
            echo "step-one     - perform only one step"
            echo "step-disable - list of disabled steps, for example: 4,8,26"
            exit 0
        ;;
        list)
            PerformCommands=0
        ;;
        list-slim)
            PerformCommands=0
            PrintCommands=0
        ;;
        step=*)
            # init step
            s=$i
            s=${s#*step=}
            InitStep=$s
        ;;
        step-one=*)
            # only one step
            s=$i
            s=${s#*step-one=}
            OneStep=$s
        ;;
        step-disable=*)
            s=$i
            s=${s#*step-disable=}
            DisabledStepsList=$s
            DisabledStepsList=$(echo "$DisabledStepsList" | sed 's/,/ /g')
        ;;
        *)
            Fatal "unknown command: "$i
        ;;
    esac
done

AptList='
    apt-transport-https

    htop
    iftop
    lnav
    gparted

    imwheel
    dconf-editor
    gnome-tweaks
    gnome-shell-extensions

    psensor
    indicator-multiload

    mc
    tree
    filezilla

    git
    gitk
    git-lfs

    build-essential
    cmake
    curl
    pkg-config
    libpcap-dev
    libfmt-dev
    libdlib-dev
    libboost-all-dev
    libsqlite3-dev
    nlohmann-json3-dev
    catch2
    crossbuild-essential-arm64
    crossbuild-essential-armel
    crossbuild-essential-armhf
    protobuf-compiler
    clang
    gcc
    g++

    python3-dev
    python3-pip
    python3-venv
    python-is-python3

    wine
    virtualbox
    virtualbox-guest-additions-iso
    docker.io

    p7zip-full
    unrar

    nmap
    socat
    traceroute

    picocom
    minicom

    hyphen-ru
    okular
    sublime-text
    sublime-merge

    qalculate-gtk

    vlc
    gimp
    ffmpeg
    audacity
    graphviz
    kazam
    vokoscreen-ng
    recordmydesktop
    simplescreenrecorder

    torbrowser-launcher

    gir1.2-appindicator3-0.1
'
AptListDialog='
    smartmontools
    wireshark
    ubuntu-restricted-extras
    virtualbox-ext-pack
'


function Startup {
    PrintTitle "Startup"
    Exec 'mkdir '${TmpDir}
    Exec 'cd '${TmpDir}

    if sudo grep timestamp_timeout /etc/sudoers >/dev/null; then
        Echo "[Warning] can't disable sudo timeout"
    else
        Exec 'sudo sed -i "10i Defaults        timestamp_timeout=-1" /etc/sudoers'
    fi
    NextStep
}

function Clean {
    if CheckStep; then
        PrintTitle "Clean"

        Exec 'rm -rf ~/Documents ~/Music ~/Pictures ~/Public ~/Templates ~/Videos examples.desktop'

        Exec 'sudo apt purge -y gnome-mines' "remove game mines"
        Exec 'sudo apt purge -y gnome-sudoku' "remove game sudoku"
        Exec 'sudo apt purge -y gnome-mahjongg' "remove game mahjongg"
        Exec 'sudo apt purge -y aisleriot' "remove game solitaire"
        Exec 'sudo apt purge -y update-notifier' "remove Update Notifier"
        Exec 'sudo apt autoremove -y'
        Exec 'sudo snap remove gnome-calculator' "remove gnome-calculator"
    fi
    NextStep
}

function AddAptRepositories {
    if CheckStep; then
        PrintTitle "Add repositories"

        Exec 'wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -' "add Sublime-text repository"
        Exec 'echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list'
    fi
    NextStep
}

function AddPortRepositories {
    if CheckStep; then
        PrintTitle "Add Port repositories"

        Exec "sudo sed -i \"s/deb http/deb [arch=${DistrArch}] http/\" ${SourcesListFile}"

        Exec "echo '' | sudo tee -a ${SourcesListFile}"
        AddAptPortSource
        AddAptPortSource "security"
        AddAptPortSource "updates"
        AddAptPortSource "backports"

        Exec "sudo dpkg --add-architecture armhf"
        Exec "sudo dpkg --add-architecture arm64"
    fi
    NextStep
}

function Upgrading {
    if CheckStep; then
        PrintTitle "Upgrading"

        Exec 'sudo apt update' "updating"
        Exec 'sudo apt upgrade -y' "upgrading"
    fi
    NextStep
}

function InstallOverApt {
    if CheckStep; then
        PrintTitle "Install from Apt"

        for i in $AptList; do
            AptInstall $i
        done
    fi
    NextStep
}

function InstallOverAptDialog {
    if CheckStep; then
        PrintTitle "Install from Apt with Dialogs"

        for i in $AptListDialog; do
            AptInstall $i
        done
    fi
    NextStep
}

function InstallChrome {
    if CheckStep; then
        PrintTitle "Install Chrome"

        Exec "wget https://dl.google.com/linux/direct/google-chrome-stable_current_${DistrArch}.deb" "download Chrome"
        Exec "sudo dpkg -i google-chrome-stable_current_${DistrArch}.deb" "install Chrome"
    fi
    NextStep
}


function InstallSmartgit {
    if CheckStep; then
        PrintTitle "Install Smartgit"

        version=$(wget -qO - https://www.syntevo.com/smartgit/download/ | awk '/Version [0-9]/{print $2}')
        pointcount=$(echo "${version}" | tr -cd . | wc -c)
        if [[ $pointcount == 1 ]]; then
            version="${version}.0"
        fi
        Echo "version: "$version
        version=$(echo "${version}" | sed 's/\./_/g')
        Exec "wget https://www.syntevo.com/downloads/smartgit/smartgit-${version}.deb" "download Smartgit"
        Exec "sudo dpkg -i smartgit-${version}.deb" "install Smartgit"
    fi
    NextStep
}

function InstallSmartsynchronize {
    if CheckStep; then
        PrintTitle "Install Smartsynchronize"

        ref=$(wget -qO- https://www.syntevo.com/smartsynchronize/download/ | grep -Eo 'href="[^\"]+"' | grep -Eo '/downloads.*.deb')
        ref=https://www.syntevo.com$ref
        Echo $ref

        Exec "wget $ref -O smartsynchronize.deb" "download Smartsynchronize"
        Exec "sudo dpkg -i smartsynchronize.deb" "install Smartsynchronize"
    fi
    NextStep
}

function InstallArduino {
    if CheckStep; then
        PrintTitle "Install Arduino"

        Exec 'wget https://downloads.arduino.cc/arduino-nightly-linux64.tar.xz' "download Arduino"
        Exec 'tar xf arduino-nightly-linux64.tar.xz' "unpack Arduino"
        Exec 'mv arduino-nightly arduino'
        Exec 'sudo mv arduino /opt'
        Exec 'sudo /opt/arduino/install.sh' "install Arduino"
        Exec 'rm -rf ~/Desktop/*'
    fi
    NextStep
}

function InstallWinBox {
    if CheckStep; then
        PrintTitle "Install Winbox"

        WinBoxDir=$OptDir'/winbox'
        exename='winbox.exe'
        ref='https://mt.lv/winbox'
        Exec "wget $ref -O $exename" "download Winbox"
        Exec 'sudo mkdir '${WinBoxDir}
        Exec "sudo mv $exename ${WinBoxDir}"
    fi
    NextStep
}

function InstallTeamviewer {
    if CheckStep; then
        PrintTitle "Install Teamviewer"

        Exec "wget https://download.teamviewer.com/download/linux/teamviewer_${DistrArch}.deb" "download Teamviewer"
        Exec "sudo dpkg -i teamviewer_${DistrArch}.deb ; sudo apt install -y -f" "install Teamviewer"
    fi
    NextStep
}

function InstallPostman {
    if CheckStep; then
        PrintTitle "Install Postman"

        Exec 'sudo snap install postman'
    fi
    NextStep
}

function InstallGolang {
    if CheckStep; then
        PrintTitle "Install Golang"

        ref=$(wget -qO- https://golang.org/dl/ | grep -Eo 'href="[^\"]+"' | grep -Eo "/dl/go.*linux-${DistrArch}.tar.gz" -m 1)
        ref=https://golang.org$ref
        Exec "wget ${ref} -O golang.tar.gz" "download Golang"
        Exec "sudo tar -C $OptDir -xzf golang.tar.gz" "install Golang"
    fi
    NextStep
}

function InstallTelegram {
    if CheckStep; then
        PrintTitle "Install Telegram"

        Exec "wget https://telegram.org/dl/desktop/linux -O tsetup.tar.xz" "download Telegram"
        Exec "sudo tar -C $OptDir -xvf tsetup.tar.xz" "install Telegram"
    fi
    NextStep
}

function InstallEtcher {
    if CheckStep; then
        PrintTitle "Install Balena Etcher"

        ref=$(wget -qO- https://www.balena.io/etcher/ | grep -Eo 'href="[^\"]+"' | grep -Eo 'http.*balena-etcher-electron.*-linux-x64.zip')

        Exec "sudo apt install -y libfuse2"
        Exec "wget $ref -O etcher.zip" "download Balena Etcher"
        Exec "unzip etcher.zip" "install Balena Etcher"
        Exec "sudo mkdir $OptDir/etcher"
        Exec "sudo mv *.AppImage $OptDir/etcher/etcher"
    fi
    NextStep
}

function InstallSkype {
    if CheckStep; then
        PrintTitle "Install Skype"

        ref="https://go.skype.com/skypeforlinux-64.deb"

        Exec "sudo apt install -y libgdk-pixbuf-xlib-2.0-0 libgdk-pixbuf2.0-0"
        Exec "wget $ref -O skype.deb" "download Skype"
        Exec "sudo dpkg -i skype.deb" "install Skype"
    fi
    NextStep
}

function InstallStorageIndicator {
    if CheckStep; then
        PrintTitle "Install Storage indicator"

        Exec "git clone git://mswo.ru/msw/storage-indicator" "download Storage indicator"
        Exec 'cd storage-indicator'
        Exec './install.sh' "install Storage indicator"
        Exec 'cd ..'
    fi
    NextStep
}

function InstallTruecrypt {
    if CheckStep; then
        PrintTitle "Install Truecrypt"

        Exec "tar xvf $SrcDebDir/truecrypt-7.1a-linux-console-x64.tar.gz" "unpack Truecrypt"
        Exec 'sudo ./truecrypt-7.1a-setup-console-x64' "install Truecrypt"

        Exec "sudo cp -rv ${SrcDir}/tco ${OptDir}/" "install tc"
    fi
    NextStep
}

function InstallOpencv {
    if CheckStep; then
        PrintTitle "Install Opencv"

        Exec "sudo apt install -y build-essential cmake git pkg-config
            libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev
            libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev
            gfortran openexr libatlas-base-dev python3-dev python3-numpy
            libtbb2 libtbb-dev libdc1394-dev libopenexr-dev
            libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev
        "

        Exec 'wget -O opencv.zip https://github.com/opencv/opencv/archive/master.zip'
        Exec 'wget -O opencv_contrib.zip https://github.com/opencv/opencv_contrib/archive/master.zip'
        Exec 'unzip opencv.zip'
        Exec 'unzip opencv_contrib.zip'
        Exec 'mkdir -p build && cd build'

        options="
            -D CMAKE_BUILD_TYPE=RELEASE
            -D CMAKE_INSTALL_PREFIX=/usr/local
            -D OPENCV_GENERATE_PKGCONFIG=ON
            -D OPENCV_ENABLE_NONFREE=ON
            -D OPENCV_EXTRA_MODULES_PATH=../opencv_contrib-master/modules
            ../opencv-master
        "

        Exec "cmake ${options}"
        Exec "make -j${CpuCoreCount}"
        Exec 'sudo make install'
        Exec 'sudo ldconfig'

        Exec 'cd ..'
    fi
    NextStep
}


function ConfigurePath {
    if CheckStep; then
        PrintTitle "Configure Path"

        AddPath $OptDir'/tco/bin'
        AddPath $OptDir'/go/bin'
        AddPath $Home'/go/bin'
        AddPath $Home'/msw/bin/bin/vit'
    fi
    NextStep
}

function ConfigureAliase {
    if CheckStep; then
        PrintTitle "Configure Aliase"

        AddAliase "pw='poweroff'"
        AddAliase "hs='history | grep'"
        AddAliase "winbox='nohup wine ${WinBoxDir}/$exename </dev/null >/dev/null 2>&1 &'"
    fi
    NextStep
}


function ConfigureDirs {
    if CheckStep; then
        PrintTitle "Configure Dirs"

        Exec "ln -s $Media $Home/usb" "usb"

        Exec "mkdir $Home/msw" "containers"
        function maketcln {
            disk=$1
            name=$2
            Exec "ln -s /mnt/tc/$disk/$name $Home/msw/$name"
        }
        maketcln "a" "ext"
        maketcln "u" "src"
        maketcln "n" "bin"
        maketcln "s" "signal"
        maketcln "r" "archive"
        maketcln "j" "job"
        maketcln "o" "msw"
        maketcln "m" "music"
        maketcln "p" "projects"
        maketcln "w" "media"
        maketcln "x" "x"

        Exec "ln -s $MntExt $Home/ext" "ext"
        Exec "ln -s $MntExt/tmp $Home/tmp" "tmp"
    fi
    NextStep
}

function ConfigureHomeConfig {
    if CheckStep; then
        PrintTitle "Configure Home config"

        Exec "cp -rv ${SrcHomeDir}/.config ${Home}/"
    fi
    NextStep
}

function ConfigureTerminal {
    if CheckStep; then
        PrintTitle "Configure Terminal"

        Exec "dconf load /org/gnome/terminal/ < ${SrcDconfDir}/terminal"
    fi
    NextStep
}

function ConfigureEnvironment {
    if CheckStep; then
        PrintTitle "Configure Environment"

        Echo "Hint: for debug gsettings use 'dconf-editor' or 'dconf dump /'"

        Exec "gsettings set org.gnome.desktop.privacy report-technical-problems false"

        Exec "gsettings set org.gnome.desktop.interface clock-show-seconds true"
        Exec "gsettings set org.gnome.desktop.interface clock-show-weekday true"
        Exec "gsettings set org.gnome.desktop.interface clock-show-date true"
        Exec "gsettings set org.gnome.desktop.interface clock-format '24h'"

        Exec "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'"
        Exec "gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-purple-dark'"
        Exec "gsettings set org.gnome.desktop.interface icon-theme 'Yaru-purple'"
        Exec "gsettings set org.gnome.shell enabled-extensions \"['user-theme@gnome-shell-extensions.gcampax.github.com']\""

        Exec "gsettings set org.gnome.gedit.preferences.editor scheme 'Yaru-dark'"

        Exec "gsettings set org.gnome.shell.extensions.dash-to-dock autohide true"
        Exec "gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false"
        Exec "gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false"

        LangToggle="['grp:alt_shift_toggle']"
        Exec 'gsettings set org.gnome.desktop.input-sources xkb-options "'$LangToggle'"'

        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys terminal \"['<Alt>t']\""

        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-up \"['<Alt>Page_Up']\""
        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute \"['<Alt>Pause']\""
        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-down \"['<Alt>Page_Down']\""

        Exec "gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-up \"['<Super>Page_Up']\""
        Exec "gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-down \"['<Super>Page_Down']\""

        FavoriteApps="['google-chrome.desktop', 'org.gnome.Terminal.desktop', 'virtualbox.desktop', 'qalculate-gtk.desktop', 'syntevo-smartgit.desktop']"
        Exec "gsettings set org.gnome.shell favorite-apps \"${FavoriteApps}\""

        WallpaperPath=$Home/.$Wallpaper
        Exec "cp ${SrcDir}/${Wallpaper} ${WallpaperPath}"
        Exec "gsettings set org.gnome.desktop.background picture-uri file://$WallpaperPath"

        Exec "gsettings set org.gnome.desktop.background show-desktop-icons false"
        Exec "gsettings set org.gnome.shell.extensions.ding show-home false"
        Exec "gsettings set org.gnome.shell.extensions.ding show-trash false"
        Exec "gsettings set org.gnome.shell.extensions.ding show-volumes false"
        Exec "gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false"
        Exec "gsettings set org.gnome.shell.extensions.dash-to-dock show-trash false"

        key="org.gnome.settings-daemon.plugins.media-keys"
        custom0="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        custom1="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        custom2="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
        Exec "gsettings set $key custom-keybindings \"['$custom0', '$custom1', '$custom2']\""
        Exec "gsettings set $key.custom-keybinding:$custom0 name 'Rhythmbox play-pause'"
        Exec "gsettings set $key.custom-keybinding:$custom0 command 'rhythmbox-client --play-pause'"
        Exec "gsettings set $key.custom-keybinding:$custom0 binding '<Alt>Insert'"
        Exec "gsettings set $key.custom-keybinding:$custom1 name 'Rhythmbox previous'"
        Exec "gsettings set $key.custom-keybinding:$custom1 command 'rhythmbox-client --previous'"
        Exec "gsettings set $key.custom-keybinding:$custom1 binding '<Alt>Delete'"
        Exec "gsettings set $key.custom-keybinding:$custom2 name 'Rhythmbox next'"
        Exec "gsettings set $key.custom-keybinding:$custom2 command 'rhythmbox-client --next'"
        Exec "gsettings set $key.custom-keybinding:$custom2 binding '<Alt>End'"

        Exec "sudo sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf"
    fi
    NextStep
}

function ConfigureNetwork {
    if CheckStep; then
        PrintTitle "Configure Network"

        eth=$(nmcli device | awk '/ethernet/{print $1; exit}')
        Exec "nmcli connection add con-name inet type ethernet ifname $eth conn.autoconnect-p 10"
        Exec "nmcli connection add con-name print type ethernet ifname $eth ipv4.method manual ipv4.addr 195.200.200.57/24 ipv4.gateway 195.200.200.1"
    fi
    NextStep
}

function ConfigureLocale {
    if CheckStep; then
        PrintTitle "Configure Locale"

        Exec "sudo locale-gen ru_RU.UTF-8"
        layouts="[('xkb', 'us'), ('xkb', 'ru')]"
        Exec "gsettings set org.gnome.desktop.input-sources sources \"$layouts\""
        Exec "sudo sed -i 's/ru_RU/en_US/' /etc/default/locale"
    fi
    NextStep
}

function ConfigureDocker {
    if CheckStep; then
        PrintTitle "Configure Docker"

        Echo "configure for resolve conflict Docker with VPN networks"
        Echo "for use VPN: sudo systemctl stop docker"
        Exec "sudo cp ${SrcDir}/docker/daemon.json /etc/docker" "docker daemon.json"
    fi
    NextStep
}

function ConfigureGit {
    if CheckStep; then
        PrintTitle "Configure Git"

        Exec 'git config --global user.name '$GitUser
        Exec 'git config --global user.email '$GitEmail

        Exec 'git config --global gc.autoDetach false'
        Exec 'git config --global pull.rebase false'

        Exec 'git lfs install'
    fi
    NextStep
}

function ConfigureImwheel {
    if CheckStep; then
        PrintTitle "Configure Imwheel"

        imwheelrc=".imwheelrc"
        Exec "cp ${SrcHomeDir}/${imwheelrc} ${Home}/${imwheelrc}"
    fi
    NextStep
}

function ConfigureIndicatorMultiload {
    if CheckStep; then
        PrintTitle "Configure Indicator-Multiload"

        Exec "dconf load /de/mh21/indicator-multiload/ < ${SrcDconfDir}/indicator-multiload"
    fi
    NextStep
}

function ConfigurePsensor {
    if CheckStep; then
        PrintTitle "Configure Psensor"

        Exec "dconf write /apps/psensor/interface-hide-on-startup true"
    fi
    NextStep
}

function ConfigureVirtualBox {
    if CheckStep; then
        PrintTitle "Configure VirtualBox"

        Exec "sudo usermod -a -G vboxusers $USER" "enable devices (including usb)"

        Exec "nohup virtualbox </dev/null >/dev/null 2>&1 &"
        if [[ $PerformCommands == 1 ]]; then
            key='n'
            until [ $key == 'y' ]; do
                read -n 1 -p "Please close VirtualBox. Continue configure? y/n: " key && echo
            done
        fi
        ConfFile="$Home/.config/VirtualBox/VirtualBox.xml"
        exp='(defaultMachineFolder=)"[^\"]+"'
        path="\"$VmPath\""
        Exec "sed -i -E 's|$exp|\1$path|' $ConfFile"
    fi
    NextStep
}

function ConfigureTelegram {
    if CheckStep; then
        PrintTitle "Configure Telegram"

        Exec "nohup $OptDir/Telegram/Telegram </dev/null >/dev/null 2>&1 &"
    fi
    NextStep
}

function ConfigureEtcher {
    if CheckStep; then
        PrintTitle "Configure Telegram"

        Exec "sudo cp ${SrcDir}/etcher.png ${OptDir}/etcher" "copy menu icon"
        Exec "sudo cp ${SrcDir}/etcher.desktop /usr/share/applications" "make menu icon"
    fi
    NextStep
}

function ConfigureSmartgit {
    if CheckStep; then
        PrintTitle "Configure Smartgit"

        Exec "nohup /usr/share/smartgit/bin/smartgit.sh </dev/null >/dev/null 2>&1 &" "run Smartgit"
        Echo "select 'Non-commercial use only'"
        if [[ $PerformCommands == 1 ]]; then
            key='n'
            until [ $key == 'y' ]; do
                read -n 1 -p "Smartgit ready for configure? y/n: " key && echo
            done
        fi
        ConfFile="preferences.yml"
        ConfDir="$Home/.config/smartgit"
        Version=$(ls -1 $ConfDir | awk '/[0-9]/{print $1; exit}')
        ConfPath="$ConfDir/$Version/$ConfFile"
        Echo "version: $Version"
        Echo "config: $ConfPath"
        DateFormat="dateFormat: {datePattern: dd.MM.yyyy, timePattern: 'HH:mm', showTimeForLastDays: false}"
        Exec "sed -i 's/^dateFormat:.*/$DateFormat/' $ConfPath"
    fi
    NextStep
}

function ConfigureArduino {
    if CheckStep; then
        PrintTitle "Configure Arduino"

        Exec "sudo usermod -a -G dialout $User"
    fi
    NextStep
}

function ConfigureMC {
    if CheckStep; then
        PrintTitle "Configure mc"

        Exec "mc"
        Config="$Home/.config/mc/ini"
        Exec "sed -i 's/^old_esc_mode=.*/old_esc_mode=true/' $Config"
        Exec "sed -i 's/^old_esc_mode_timeout=.*/old_esc_mode_timeout=1000/' $Config"
    fi
    NextStep
}

function ConfigureTor {
    if CheckStep; then
        PrintTitle "Configure Tor"

        Exec "sudo cp ${SrcDir}/fix-tor/* /usr/lib/python3/dist-packages/torbrowser_launcher" "fix tor"
    fi
    NextStep
}


function СonfirmationDialog {
    read -n 1 -p "Attention! Are you sure you want to start configuring your system for user '${User}' (${Home})? y/n: " key && echo
    if [[ $key != 'y' ]]; then
        Echo "cancel the installation"
        exit
    fi
}

function Launch {
    PrintTitle "Configure for ${DistrName} ${DistrVersion} (${DistrCodeName}) ${DistrArch}"
    printf "CPU core count: ${CpuCoreCount}\n"
    if [[ $EUID == 0 ]]; then
        Fatal "the script should not be run from root"
    fi
    if (( OneStep == -1 )) && (( InitStep == 0 )) ; then
        if [ -f $StepFile ]; then
            LastStep=$(cat $StepFile)
            NextStep=$(($LastStep+1))
            echo
            echo "Last step: "$LastStep
            echo "    0. Continue from the last step [step: $LastStep]"
            echo "    1. Continue from the next step [step: $NextStep]"
            echo "    2. Start from the beginning [step: 1]"
            read -n 1 -p "Please select action: " key && echo
            if [[ $key == '0' ]]; then
                InitStep=$LastStep
            elif [[ $key == '1' ]]; then
                InitStep=$NextStep
            elif [[ $key == '2' ]]; then
                Step=0
            else
                echo "unknown command: "$key
                exit 1
            fi
        fi
    fi
    if ! eval sudo echo; then
        Fatal
    fi
    if [[ $PerformCommands == 1 ]]; then
        СonfirmationDialog
    fi
    Step=0
}

function InstallDialog {
    InstallTruecrypt
    InstallOverAptDialog
}

function Install {
    Clean
    AddAptRepositories
    Upgrading
    InstallOverApt
    InstallChrome
    InstallSmartgit
    InstallSmartsynchronize
    InstallArduino
    InstallWinBox
    InstallTeamviewer
    InstallPostman
    InstallGolang
    InstallTelegram
    InstallEtcher
    InstallSkype
    InstallStorageIndicator
    InstallOpencv
}

function Configure {
    ConfigurePath
    ConfigureAliase

    ConfigureDirs
    ConfigureHomeConfig
    ConfigureTerminal
    ConfigureEnvironment
    #ConfigureNetwork
    ConfigureLocale

    ConfigureDocker
    ConfigureGit
    ConfigureImwheel
    ConfigureIndicatorMultiload
    ConfigurePsensor
    ConfigureVirtualBox
    ConfigureTelegram
    ConfigureEtcher
    ConfigureSmartgit
    ConfigureArduino
    ConfigureMC
    ConfigureTor
}

function Сompletion {
    Step=-1
    PrintTitle "Configuration successfully completed!"
    PrintTime
    if [[ $PerformCommands == 1 ]]; then
        read -n 1 -p "System reboot is required. Reboot now? y/n: " key && echo
        if [[ $key == 'y' ]]; then
            echo "rebooting..."
            reboot
        fi
    fi
}

function Run {
    Launch
    Startup
    InstallDialog
    Install
    Configure
    Сompletion
}


Run
