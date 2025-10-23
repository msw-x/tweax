#!/bin/bash

start=$(date +%s)

TmpDir='/tmp/install-'$(date +%s%N)
PwdDir=$(pwd)

DistrName=$(cat /etc/*-release | sed -n 's/^PRETTY_NAME=//p')
DistrArch=$(lscpu | grep Architecture | grep -oP '(?<=:)[^:]*$' | xargs)

CpuCoreCount=$(nproc)
Gpu=''

User=$(whoami)
Home='/home/'$User
Media='/media/'$User
LocalBin='/usr/local/bin'
MntExt='/mnt/ext/ext'
VmPath=$MntExt'/vm'

SrcDir=$PwdDir'/src'
SrcHomeDir=$SrcDir'/home'

Email=''
EmailFile=$PwdDir'/email'

StepFile=$PwdDir'/step'

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

function AppInstall {
    cmd=$1
    title=$2
    if [[ $title == "" ]]; then
        title=$cmd
    fi
    Exec 'sudo pacman --noconfirm -S '$cmd "install ${title}"
}

function YayInstall {
    cmd=$1
    title=$2
    if [[ $title == "" ]]; then
        title=$cmd
    fi
    Exec 'yay --noconfirm -S '$cmd "install ${title}"
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

function AddAliase {
    alias=$*
    if ! grep -q "$alias" ${Home}/.bashrc; then
        AddToBashRC "alias "$alias
    fi
}

function AddPath {
    path=$*
    if ! grep -q $path ${Home}/.bashrc; then
        AddToBashRC 'export PATH=$PATH:'$path
    fi
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
            echo "help   - print this help"
            echo "list   - print list of operations"
            echo "heads  - print list heads of operations"
            echo "from   - initial step"
            echo "only   - perform only one step"
            echo "ignore - list of ignored steps, for example: 4,8,26"
            exit 0
        ;;
        list)
            PerformCommands=0
        ;;
        heads)
            PerformCommands=0
            PrintCommands=0
        ;;
        from=*)
            # init step
            s=$i
            s=${s#*from=}
            InitStep=$s
        ;;
        only=*)
            # only one step
            s=$i
            s=${s#*only=}
            OneStep=$s
        ;;
        ignore=*)
            s=$i
            s=${s#*ignore=}
            DisabledStepsList=$s
            DisabledStepsList=$(echo "$DisabledStepsList" | sed 's/,/ /g')
        ;;
        *)
            Fatal "unknown command: "$i
        ;;
    esac
done

AppList='
    extra/networkmanager
    extra/openssh

    extra/dbeaver
    aur/postman-bin

    extra/git
    extra/git-lfs
    aur/smartgit

    extra/htop
    extra/btop
    extra/iftop
    extra/nvtop
    extra/lshw
    aur/gpustat-git

    extra/mc
    extra/filezilla
    extra/gparted
    aur/etcher-bin

    core/curl
    extra/wget

    extra/go

    extra/virtualbox
    extra/wine
    aur/winetricks-git
    extra/docker
    extra/docker-compose
    extra/docker-buildx

    extra/unrar
    aur/p7zip-full-bin

    extra/nmap
    extra/socat
    extra/ethtool
    extra/traceroute
    extra/smartmontools
    extra/wireshark-qt
    aur/winbox

    extra/picocom
    extra/minicom

    extra/lnav
    extra/code
    aur/sublime-text-4

    extra/vlc
    extra/gimp
    extra/ffmpeg
    extra/audacity
    
    aur/kazam
    extra/vokoscreen
    extra/recordmydesktop
    aur/simplescreenrecorder

    aur/opera
    aur/google-chrome
    aur/yandex-browser

    extra/telegram-desktop
'
#aur/arduino
#extra/pulseaudio
#extra/easyeffects
#aur/teamviewer

function Update {
    if CheckStep; then
        PrintTitle "Update"

        Exec 'sudo pacman --noconfirm -Syu' "Update"
    fi
    NextStep
}

function InstallApps {
    if CheckStep; then
        PrintTitle "Install from Pacman"

        for i in $AppList; do
            YayInstall $i
        done
    fi
    NextStep
}

function InstallSly {
    if CheckStep; then
        PrintTitle "Install Sly"

        Exec "sudo cp -rv ${SrcDir}/sly/ ${LocalBin}/" "install sly"
    fi
    NextStep
}

function InstallStamina {
    if CheckStep; then
        PrintTitle "Install Stamina"

        Exec "winetricks mfc42" "install mfc42 for wine"
        Exec 'wine reg add "HKCU\Keyboard Layout\Preload" /f /v "2" /t REG_SZ /d "00000419"'

        local dir=$OptDir'/stamina'
        Exec "wget https://stamina.ru/files/Stamina.zip -O stamina.zip" "download Stamina"
        Exec "unzip stamina.zip" "install Stamina"
        Exec "sudo mkdir $dir"
        Exec "sudo mv Stamina/* $dir"
        StaminaExe="$dir/stamina.exe"
        Exec "sudo mv $dir/Stamina.exe $StaminaExe"
        Exec "sudo chown -R $User:$User $dir"
    fi
    NextStep
}

function ConfigurePath {
    if CheckStep; then
        PrintTitle "Configure Path"

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
        #AddAliase "winbox='nohup wine ${WinBoxExe} </dev/null >/dev/null 2>&1 &'"
        #AddAliase "stamina='export LC_ALL=ru_RU.UTF-8 && nohup wine ${StaminaExe} </dev/null >/dev/null 2>&1 &'"
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
            Exec "ln -s /mnt/local/$disk/$name $Home/msw/$name"
        }
        maketcln "d" "dnn"
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

        Exec "gsettings set org.gnome.TextEditor show-line-numbers true"
        Exec "gsettings set org.gnome.TextEditor spellcheck false"
        Exec "gsettings set org.gnome.TextEditor highlight-current-line true"

        LangToggle="['grp:alt_shift_toggle']"
        Exec 'gsettings set org.gnome.desktop.input-sources xkb-options "'$LangToggle'"'

        #Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys terminal \"['<Alt>t']\""

        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-up \"['<Alt>Page_Up']\""
        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute \"['<Alt>Pause']\""
        Exec "gsettings set org.gnome.settings-daemon.plugins.media-keys volume-down \"['<Alt>Page_Down']\""

        FavoriteApps="['google-chrome.desktop', 'org.gnome.Terminal.desktop', 'virtualbox.desktop', 'syntevo-smartgit.desktop']"
        Exec "gsettings set org.gnome.shell favorite-apps \"${FavoriteApps}\""
    fi
    NextStep
}

function ConfigureLocale {
    if CheckStep; then
        PrintTitle "Configure Locale"

        Exec "sudo locale-gen ru_RU.UTF-8"
        layouts="[('xkb', 'us'), ('xkb', 'ru')]"
        Exec "gsettings set org.gnome.desktop.input-sources sources \"$layouts\""
        #Exec "sudo sed -i 's/ru_RU/en_US/' /etc/default/locale"

        local loc="en_US.UTF-8"
        Exec "sudo update-locale LANG=${loc} LC_NUMERIC=${loc} LC_TIME=${loc} LC_MONETARY=${loc} LC_PAPER=${loc} LC_NAME=${loc}"
        Exec "sudo update-locale LC_ADDRESS=${loc} LC_TELEPHONE=${loc} LC_MEASUREMENT=${loc} LC_IDENTIFICATION=${loc}"
    fi
    NextStep
}

function ConfigureGit {
    if CheckStep; then
        PrintTitle "Configure Git"

        Exec 'git config --global user.name '$User
        Exec 'git config --global user.email '$Email

        Exec 'git config --global gc.autoDetach false'
        Exec 'git config --global pull.rebase false'

        Exec 'git lfs install'
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
        Exec "sed -i 's/^skin=.*/skin=yadt256-defbg/' $Config"
        Exec "sed -i 's/^old_esc_mode=.*/old_esc_mode=true/' $Config"
        Exec "sed -i 's/^old_esc_mode_timeout=.*/old_esc_mode_timeout=1000/' $Config"
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
    PrintTitle "Configure for ${DistrName} ${DistrArch}"
    printf "CPU (cores): ${CpuCoreCount}\n"
    if [ ! -z "$Gpu" ]; then
        printf "GPU: ${Gpu}\n"
    else
        printf "GPU: not found\n"
    fi
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

function Startup {
    PrintTitle "Startup"
    Exec 'mkdir '${TmpDir}
    Exec 'cd '${TmpDir}

    local sudoers='/etc/sudoers'
    if sudo grep -q -v timestamp_timeout $sudoers; then
        Exec "sudo sed -i \"10i Defaults timestamp_timeout=-1\" $sudoers"
    fi
    NextStep
}

function SetPersonal {
    if [ -f $EmailFile ]; then
        Email=$(cat $EmailFile)
    else
        read -p "Email: " Email
        echo $Email > $EmailFile
    fi
}

function InstallGnome {
    if CheckStep; then
        PrintTitle "Install Gnome"

        AppInstall 'xorg'
        AppInstall 'gnome'
        AppInstall 'gdm'
        Exec "sudo systemctl enable gdm.service"
        Exec 'rm -rf ~/Documents ~/Music ~/Pictures ~/Public ~/Templates ~/Videos'
        AppInstall 'dconf-editor gnome-tweaks gnome-shell-extensions'
        Exec "sudo systemctl enable NetworkManager.service"
    fi
    NextStep
}

function InstallYay {
    if CheckStep; then
        PrintTitle "Install Yay"

        AppInstall 'git base-devel go'
        Exec 'git clone https://aur.archlinux.org/yay.git'
        Exec 'cd yay'
        Exec 'makepkg --noconfirm -si'
        Exec 'cd ..'
    fi
    NextStep
}

function Install {
    Update
    InstallGnome
    InstallYay
    InstallApps
    InstallSly
    #InstallStamina
}

function Configure {
    ConfigurePath
    ConfigureAliase
    ConfigureDirs
    ConfigureHomeConfig
    ConfigureEnvironment
    #ConfigureLocale
    ConfigureGit
    #ConfigureVirtualBox
    #ConfigureSmartgit
    #ConfigureArduino
    ConfigureMC
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
    SetPersonal
    Install
    Configure
    Сompletion
}


Run
