# Tools

timestamp=$(date +%s)

Bold='\033[1m'
Red='\e[31m'
Green='\e[32m'
Yellow='\e[33m'
Blue='\e[34m'
Purple='\e[35m'
Cyan='\e[36m'
NC='\e[0m'

Time() {
    local time="$(date -d @$(($(date +%s)-$timestamp)) +"%Mm %Ss")"
    echo
    echo -e "${Bold}${Blue}time: $time${NC}"
}

Fatal() {
    msg=$*
    Time
    echo
    echo -e "⛔️ ${Red}$msg${NC}"
    exit 1
}

Title() {
    local value="$1"
    echo
    echo -e "${Bold}${Green}${value}${NC}"
}

SubTitle() {
    local value="$1"
    echo
    echo -e "${Green}${value}${NC}"
}

Ls() {
    local dir=$1
    echo
    echo -e "${Bold}${Blue}$dir${NC}"
    ls -1 $dir
    echo
}

Cat() {
    local file=$1
    echo
    echo -e "${Bold}${Blue}$file:${NC}"
    cat $file
    echo
    echo -e "${Blue}==============================${NC}"
}

New() {
    local file="$1"
    local value="$2"
    echo $value | tee $file > /dev/null
}

Add() {
    local file="$1"
    local value="$2"
    echo $value | tee -a $file > /dev/null
}

Set() {
    local file="$1"
    local name="$2"
    local value="$3"
    local separator="${4:-|}"
    # update
    sed -i "s${separator}.*${name}=.*${separator}${name}=${value}${separator}" "$file"
    # insert
    grep -q "$name" $file || echo -e "\n$name=$value" | tee -a $file > /dev/null
}

Put() {
    local file="$1"
    local placeholder="$2"
    local value="$3"
    local separator="${4:-|}"
    sed -i "s${separator}@${placeholder}${separator}${value}${separator}g" $file
}

ToLower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

GetUsers() {
    local root="${1:-/}"
    local users=()
    local UID_MIN=$(awk '/^UID_MIN/ {print $2}' /etc/login.defs)
    local UID_MAX=$(awk '/^UID_MAX/ {print $2}' /etc/login.defs)
    while IFS=: read -r user _ uid _ _ _ _; do
        if [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -ge "$UID_MIN" ] && [ "$uid" -le "$UID_MAX" ]; then
            users+=("$user")
        fi
    done < $root/etc/passwd
    printf '%s\n' "${users[@]}"
}
