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
    local name=$(basename $url)
    url=$(dirname $url)
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
        echo "[download]: $name => $url"
        wget --timeout=240 "$url/$name"
    fi
}

function FinalUrl {
    local url=$1
    url=$(curl -LIs -o /dev/null -w %{url_effective} $url)
    echo $url
}

function RootUrl {
    local url=$1
    url=$(echo $url | grep -P -o '.*\.\w+(?=/)')
    echo $url
}

function GetUrl {
    local url=$1
    local exp=$2
    local ret=$(wget --timeout=20 -qO - $url | grep -P -o '(?<=href=").*?(?=")' | grep $exp | head -n 1)
    if ! echo $ret | grep -q -P '\.\w+/'; then
        if [[ $ret == '/'* ]]; then
            url=$(RootUrl $url)
        else
            ret="/$ret"
        fi
        local file=$(basename $url)
        if [[ $file == *'.php' ]]; then
            url=$(dirname $url)
        fi
        ret=$url$ret
    fi
    if [[ $ret == '//'* ]]; then
        ret=$(echo $ret | grep -P -o '(?<=//).*')
    fi
    local file=$(basename -- "$ret")
    local ext="${file##*.}"
    if [[ $ext == $file ]]; then
        ext=''  
    fi
    if [[ $ext == '' ]]; then
        ret=$(FinalUrl $ret)
    fi
    echo $ret
}

function DownloadSysinternals {
    local url='download.sysinternals.com/files/'
    Download $url'Autoruns.zip'
    Download $url'ProcessExplorer.zip'
    Download $url'ProcessMonitor.zip'
    Download $url'TCPView.zip'
    Download $url'RAMMap.zip'
}

function Download7z {
    local url=$(GetUrl '7-zip.org' 'x64')
    Download $url
}

function DownloadGit {
    local url=$(GetUrl 'git-scm.com/download/win' '64')
    Download $url
}

function DownloadFar {
    local url=$(GetUrl 'farmanager.com/download.php' 'x64.*msi')
    Download $url
}

function DownloadVlc {
    local url=$(GetUrl 'videolan.org' 'win64')
    Download $url
}

function DownloadSublime {
    local url=$(GetUrl 'sublimetext.com/download_thanks?target=win-x64' 'x64.*exe')
    Download $url
}

function DownloadSmartGit {
    local url=$(GetUrl 'syntevo.com/smartgit/download' 'win')
    Download $url
}

function DownloadWireshark {
    local url=$(GetUrl 'wireshark.org/download/win64' 'win')
    Download $url
}

function DownloadTelegram {
    local url=$(GetUrl 'desktop.telegram.org' 'win64')
    Download $url
}

function DownloadAll {
    DownloadSysinternals
    Download7z
    DownloadGit
    DownloadFar
    DownloadVlc
    DownloadSublime
    DownloadSmartGit
    DownloadWireshark
    DownloadTelegram
}

function Run {
    mkdir -p $TmpDir
    cd $TmpDir
    DownloadAll
    echo "Downloads: $TmpDir"
}

Run
