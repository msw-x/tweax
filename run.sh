#!/bin/bash

TmpDir='/tmp/install-'$(date +%s%N)
PwdDir=$(pwd)

DistrName=$(cat /etc/*-release | sed -n 's/^ID=//p')
DistrVersion=$(cat /etc/*-release | sed -n 's/^DISTRIB_RELEASE=//p')
DistrCodeName=$(cat /etc/*-release | sed -n 's/^DISTRIB_CODENAME=//p')

User=$(who | awk '(NR == 1)' | awk '{print $1}')
Home='/home/'$User
OptDir='/opt'

SrcDir=$PwdDir'/src'
SrcHomeDir=$SrcDir'/home'
SrcDconfDir=$SrcDir'/dconf'
SrcDebDir=$SrcDir'/deb'

Wallpaper="wallpaper.jpg"

GitUser=$User
GitEmail=$(cat email)

PrintCommands=1
PerformCommands=1

Step=-1
OneStep=-1
InitStep=0


function Fatal {
    msg=$*
    step=""
    if [[ $Step != -1 ]]; then
        step="[$Step]"
    fi
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
    if [[ $title != "" ]]; then
        if [[ $Step == -1 ]]; then
            printf "\n${title}\n"
        else
            printf "\n[$Step]: ${title}\n"
        fi
    fi
}

function PrintSubTitle {
    title=$*
    if [[ $title != "" ]]; then
        printf "\n{$Step}: ${title}\n"
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

function AptInstall {
    cmd=$1
    title=$2
    if [[ $title == "" ]]; then
        title=$cmd
    fi
    Exec 'sudo apt install -y '$cmd "install ${title}"
}

function NextStep {
    Step=$(($Step+1))
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
    if grep "$alias" ${Home}/.bashrc; then
        echo "[Warning] alias ${alias} already exist"
    else
        AddToBashRC "alias "$alias
    fi
}

function AddPath {
    path=$*
    if grep $path ${Home}/.profile; then
        echo "[Warning] path ${path} already exist"
    else
        AddToProfile 'export PATH=$PATH:'$path
    fi
}

function CheckStep {
    if (( OneStep != -1 )); then
        if (( Step == OneStep )); then
            return 0
        fi
        return 1
    fi
    if (( Step >= InitStep )); then
        return 0
    fi
    return 1
}

for i in "$@"; do
    case $i in
        verbose)
            PrintCommands=1
        ;;
        list)
            PerformCommands=0
        ;;
        step=*)
            # init step
            s=$i
            s=${s#*step=} 
            InitStep=$s
        ;;
        one-step=*)
            # only one step
            s=$i
            s=${s#*one-step=} 
            OneStep=$s
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
    balena-etcher-electron

    imwheel
    dconf-editor
    gnome-tweak-tool

    psensor
    indicator-multiload

    mc

    git
    gitk

    build-essential
    cmake
    curl
    pkg-config
    libboost-all-dev

    wine
    virtualbox-ext-pack
    virtualbox-guest-additions-iso

    p7zip-full
    unrar

    nmap
    traceroute

    picocom
    minicom

    stardict
    sublime-text

    qalculate

    vlc
    gimp
    openshot
    audacity
    gtk-recordmydesktop

    torbrowser-launcher
'
AptListDialog='
    wireshark
    virtualbox
'


function Startup {
    PrintTitle "Startup"
    Exec 'mkdir '${TmpDir}
    Exec 'cd '${TmpDir}

    if sudo grep timestamp_timeout /etc/sudoers; then
        echo "[Warning] can't disable sudo timeout"
    else
        Exec 'sudo sed -i "10i Defaults        timestamp_timeout=-1" /etc/sudoers'
    fi
    NextStep
}

function Clean {
    if CheckStep; then
        PrintTitle "Clean"

        Exec 'rm -rf ~/Documents ~/Music ~/Pictures ~/Public ~/Templates ~/Videos'

        Exec 'sudo apt purge -y firefox' "Remove firefox"
        Exec 'sudo apt purge -y update-notifier' "Update Notifier"
        Exec 'sudo apt autoremove -y'
        Exec 'sudo snap remove gnome-calculator' "Remove gnome-calculator"
    fi
    NextStep
}

function AddAptRepositories {
    if CheckStep; then
        PrintTitle "Add repositories"

        Exec 'echo "deb https://deb.etcher.io stable etcher" | sudo tee /etc/apt/sources.list.d/balena-etcher.list'
        Exec 'sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 379CE192D401AB61' "add Etcher repository"

        Exec 'wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -' "add Sublime-text repository"
        Exec 'echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list'
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

        Exec 'wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb' "download Chrome"
        Exec 'sudo dpkg -i google-chrome-stable_current_amd64.deb' "install Chrome"
    fi
    NextStep
}


function InstallSmartgit {
    if CheckStep; then
        PrintTitle "Install Smartgit"

        version=$(wget -qO - https://www.syntevo.com/smartgit/download/ | awk '/Version [0-9]/{print $2}')
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

        version=$(wget -qO - https://www.syntevo.com/smartsynchronize/download/ | awk '/Version [0-9]/{print $2}')
        Echo "version: "$version
        version=$(echo "${version}" | sed 's/\./_/g')
        Exec "wget https://www.syntevo.com/downloads/smartsynchronize/smartsynchronize-${version}.deb" "download Smartsynchronize"
        Exec "sudo dpkg -i smartsynchronize-${version}.deb" "install Smartsynchronize"
    fi
    NextStep
}

function InstallArduino {
    if CheckStep; then
        PrintTitle "Install Arduino"

        Exec 'wget https://www.arduino.cc/download.php?f=/arduino-nightly-linux64.tar.xz' "download Arduino"
        Exec 'tar xf download.php\?f\=%2Farduino-nightly-linux64.tar.xz' "unpack Arduino"
        Exec 'cd arduino-nightly'
        Exec 'sudo ./install.sh' "install Arduino"
        Exec 'rm -rf ~/Desktop/*'
    fi
    NextStep
}

function InstallWinBox {
    if CheckStep; then
        PrintTitle "Install Winbox"

        WinBoxDir=$OptDir'/winbox'
        exename='winbox.exe'
        ref=$(wget -qO - http://www.mikrotik.com/download/ | egrep -o 'download.mikrotik.com/routeros/winbox/.*?/'$exename)
        Exec 'wget '$ref "download Winbox"
        Exec 'sudo mkdir '${WinBoxDir}
        Exec "sudo mv $exename ${WinBoxDir}"
    fi
    NextStep
}

function InstallTeamviewer {
    if CheckStep; then
        PrintTitle "Install Teamviewer"

        Exec 'wget https://download.teamviewer.com/download/linux/teamviewer_amd64.deb' "download Teamviewer"
        Exec "sudo dpkg -i teamviewer_amd64.deb ; apt install -y -f" "install Teamviewer"
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

        ref=$(wget -qO - https://golang.org/dl/ | egrep -o 'https://dl.google.com/go/go.*?linux-amd64.tar.gz' -m 1)
        filename=$(echo $ref | sed -n 's|http.*go/||p')
        Exec "wget ${ref}" "download Golang"
        Exec "sudo tar -C $OptDir -xzf $filename" "install Golang"
    fi
    NextStep
}

function InstallTelegram {
    if CheckStep; then
        PrintTitle "Install Telegram"

        Exec "torsocks wget https://telegram.org/dl/desktop/linux -O tsetup.tar.xz" "download Telegram"
        Exec "sudo tar -C $OptDir xvf tsetup.tar.xz" "install Telegram"
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


function ConfigurePath {
    if CheckStep; then
        PrintTitle "Configure Path"

        AddPath $OptDir'/tco/bin'
        AddPath $OptDir'/go/bin'
        AddPath $Home'/go/bin'
    fi
    NextStep
}

function ConfigureAliase {
    if CheckStep; then
        PrintTitle "Configure Aliase"

        AddAliase "hs='history | grep'"
        AddAliase "winbox='nohup wine ${WinBoxDir}/$exename </dev/null >/dev/null 2>&1 &'"
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

        Exec "gsettings set com.ubuntu.update-notifier show-apport-crashes false"
        Exec "gsettings set org.gnome.desktop.privacy report-technical-problems false"

        Exec "gsettings set org.gnome.desktop.interface clock-show-seconds true"
        Exec "gsettings set org.gnome.desktop.interface clock-show-weekday true"
        Exec "gsettings set org.gnome.desktop.interface clock-show-date true"
        Exec "gsettings set org.gnome.desktop.interface clock-format '24h'"

        Exec "gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark'"

        LangToggle="['grp:alt_shift_toggle']"
        Exec 'gsettings set org.gnome.desktop.input-sources xkb-options "'$LangToggle'"'

        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys terminal '<Alt>t'"

        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-up '<Alt>Page_Up'"
        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute '<Alt>Pause'"
        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-down '<Alt>Page_Down'"

        FavoriteApps="['google-chrome.desktop', 'org.gnome.Terminal.desktop', 'virtualbox.desktop', 'qalculate-gtk.desktop', 'syntevo-smartgit.desktop']"
        Exec "gsettings set org.gnome.shell favorite-apps \"${FavoriteApps}\""

        WallpaperPath=$Home/.$Wallpaper
        Exec "cp ${SrcDir}/${Wallpaper} ${WallpaperPath}"
        Exec "gsettings set org.gnome.desktop.background picture-uri file://$WallpaperPath"

        Exec "gsettings set org.gnome.desktop.background show-desktop-icons false"
        Exec "gsettings set org.gnome.shell.extensions.desktop-icons show-home false"
        Exec "gsettings set org.gnome.shell.extensions.desktop-icons show-trash false"
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

function ConfigureStardict {
    if CheckStep; then
        PrintTitle "Configure Stardict"

        #https://www.sites.google.com/site/gtonguedict/home/stardict-dictionaries
        Exec "wget http://downloads.sourceforge.net/xdxf/stardict-comn_sdict05_eng_rus_full-2.4.2.tar.bz2"
        Exec "wget http://downloads.sourceforge.net/xdxf/stardict-comn_sdict05_rus_eng_full-2.4.2.tar.bz2"
        for f in stardict*tar.bz2
        do
            Exec "sudo tar -xjvf $f -C /usr/share/stardict/dic"
        done
    fi
    NextStep
}


function СonfirmationDialog {
    sudo echo
    read -n 1 -p "Attention! Are you sure you want to start configuring your system for user '${User}' (${Home})? y/n: " key && echo
    if [[ $key != 'y' ]]; then
        Echo "cancel the installation"
        exit
    fi
}

function Launch {
    PrintTitle "Configure for ${DistrName} ${DistrVersion} (${DistrCodeName})"
    if [[ $EUID == 0 ]]; then
        Fatal "the script should not be run from root"
    fi
    if [[ $PerformCommands == 1 ]]; then
        СonfirmationDialog
    fi
    Step=0
}

function InstallDialog {
    InstallOverAptDialog
    InstallTruecrypt
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
}

function Configure {
    ConfigurePath
    ConfigureAliase

    ConfigureHomeConfig
    ConfigureTerminal
    ConfigureEnvironment
    ConfigureGit
    ConfigureImwheel
    ConfigureIndicatorMultiload
    ConfigurePsensor
    ConfigureStardict
}

function Сompletion {
    Step=-1
    PrintTitle "Configuration successfully completed!"
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
