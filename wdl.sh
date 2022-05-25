#!/bin/bash

TmpDir='/tmp/wdl'

function Exist {
    if [ -f "$TmpDir/$1" ]; then
        return 0
    else
        return 1
    fi
}

function Download {
    local url=$1
    local name=$2
    if Exist $name; then
        local size=$(stat -c%s "$name")
        local suff="B"
        if (( size > 1024 )); then
            size=$((size/1024))
            suff="KB"
        fi
        if (( size > 1024 )); then
            size=$((size/1024))
            suff="MB"
        fi
        echo "[ready]: $name [$size $suff]"
    else
        echo "[download]: $name"
        wget "$url/$name"
    fi
}

function DownloadSysinternals {
    local url='https://download.sysinternals.com/files'
    Download $url "Autoruns.zip"
    Download $url "ProcessExplorer.zip"
    Download $url "ProcessMonitor.zip"
    Download $url "TCPView.zip"
    Download $url "RAMMap.zip"
}

function Download7z {
    local url="https://www.7-zip.org/a"
    local file=$(wget -qO - https://www.7-zip.org/ | grep "x64.*Download" | grep -o "7z.*exe")
    Download $url $file
}

function DownloadGit {
    local url=$(wget -qO - https://git-scm.com/download/win | awk '/64-bit Git for Windows Setup/{print $0}' | grep -o "https.*exe")
    local file=$(basename $url)
    url=$(dirname $url)
    Download $url $file
}

function DownloadFar {
    local url=$(wget -qO - https://www.farmanager.com/download.php | grep -P -o "href=\".*?\"" | grep -o "files.*x64.*msi")
    local file=$(basename $url)
    url="https://www.farmanager.com/"$(dirname $url)
    Download $url $file
}

function DownloadSublime {
    local url=$(wget -qO - https://www.sublimetext.com/download | grep -P -o "href=\".*?\"" | grep -o "https.*x64.*exe")
    local file=$(basename $url)
    url=$(dirname $url)
    Download $url $file
}

function DownloadSmartGit {
    local url=$(wget -qO - https://www.syntevo.com/smartgit/download | grep -P -o "href=\".*?\"" | grep -o "/.*win.*zip")
    local file=$(basename $url)
    url="https://www.syntevo.com/"$(dirname $url)
    Download $url $file
}

function DownloadWireshark {
    local url=$(wget -qO - https://www.wireshark.org/download.html | grep -P -o "href=\".*?\"" | grep -o "https.*-win64.*exe" | head -n 1)
    local file=$(basename $url)
    url=$(dirname $url)
    Download $url $file
}

function DownloadAll {
    DownloadSysinternals
    Download7z
    DownloadGit
    DownloadFar
    DownloadSublime
    DownloadSmartGit
    DownloadWireshark
}

function Run {
    mkdir -p $TmpDir
    cd $TmpDir
    DownloadAll
    echo "Downloads: $TmpDir"
}

Run
