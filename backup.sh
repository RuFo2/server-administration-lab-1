#!/usr/bin/env bash

set -uo pipefail

readonly PROG=$(basename "$0")

readonly E_USAGE=64
readonly E_BAD_DIR=65
readonly E_BAD_NET=66
readonly E_NO_CREDS=67
readonly E_NO_FTP=68
readonly E_UPLOAD=69

readonly PORT_TIMEOUT=2
readonly UPLOAD_DIR=${BACKUP_UPLOAD_DIR:-/tmp}

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$PROG" "$*"
}

die() {
    local code=$1; shift
    log "ERROR: $*" >&2
    exit "$code"
}

usage() {
    cat >&2 <<EOF
Использование:
  $PROG <dir> <ip>/<n>
  $PROG <dir> <ip> <маска>
EOF
    exit "$E_USAGE"
}

valid_ip() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local o
    for o in "${BASH_REMATCH[@]:1}"; do
        (( o >= 0 && o <= 255 )) || return 1
    done
    return 0
}

valid_prefix() {
    local n=$1
    [[ $n =~ ^[0-9]{1,2}$ ]] || return 1
    (( 10#$n >= 0 && 10#$n <= 32 ))
}

ip_to_int() {
    local IFS=.
    local -a o=($1)
    echo $(( (o[0] << 24) + (o[1] << 16) + (o[2] << 8) + o[3] ))
}

int_to_ip() {
    local i=$1
    echo "$(( (i >> 24) & 255 )).$(( (i >> 16) & 255 )).$(( (i >> 8) & 255 )).$(( i & 255 ))"
}

mask_to_prefix() {
    local mask_ip=$1
    valid_ip "$mask_ip" || return 1

    local m w
    m=$(ip_to_int "$mask_ip")
    w=$(( (~m) & 0xFFFFFFFF ))

    (( (w & (w + 1)) == 0 )) || return 1

    local count=0 bit
    for (( bit = 0; bit < 32; bit++ )); do
        (( (m >> bit) & 1 )) && (( count++ ))
    done
    echo "$count"
}

prefix_to_mask_int() {
    local prefix=$1
    if (( prefix == 0 )); then
        echo 0
    else
        echo $(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    fi
}

hosts_in_range() {
    local net=$1 prefix=$2
    local total=$(( 1 << (32 - prefix) ))
    local broadcast=$(( net + total - 1 ))

    if (( prefix == 32 )); then
        echo "$net"
    elif (( prefix == 31 )); then
        echo "$net"
        echo $(( net + 1 ))
    else
        local h
        for (( h = net + 1; h <= broadcast - 1; h++ )); do
            echo "$h"
        done
    fi
}

port21_open() {
    local ip=$1
    timeout "$PORT_TIMEOUT" bash -c ": < /dev/tcp/${ip}/21" 2>/dev/null
}

if (( $# == 2 )); then
    dir=$1
    net_arg=$2
    [[ $net_arg == */* ]] || usage
    ip=${net_arg%/*}
    prefix=${net_arg#*/}
    valid_ip "$ip" || die "$E_BAD_NET" "невалидный IP: '$ip'"
    valid_prefix "$prefix" || die "$E_BAD_NET" "невалидный префикс: '$prefix'"
    prefix=$(( 10#$prefix ))
elif (( $# == 3 )); then
    dir=$1
    ip=$2
    mask=$3
    valid_ip "$ip" || die "$E_BAD_NET" "невалидный IP: '$ip'"
    if ! prefix=$(mask_to_prefix "$mask"); then
        die "$E_BAD_NET" "невалидная маска подсети: '$mask'"
    fi
else
    usage
fi

[[ $dir == /* ]] || die "$E_BAD_DIR" "путь должен быть абсолютным: '$dir'"
[[ -d $dir ]] || die "$E_BAD_DIR" "каталог не найден: '$dir'"

[[ -n ${FTP_USER:-} && -n ${FTP_PASS:-} ]] \
    || die "$E_NO_CREDS" "не заданы переменные окружения FTP_USER/FTP_PASS"

ip_int=$(ip_to_int "$ip")
mask_int=$(prefix_to_mask_int "$prefix")
network_int=$(( ip_int & mask_int ))

log "поиск FTP-сервера в $(int_to_ip "$network_int")/$prefix"

ftp_host=""
while read -r host_int; do
    host_ip=$(int_to_ip "$host_int")
    if port21_open "$host_ip"; then
        ftp_host=$host_ip
        break
    fi
done < <(hosts_in_range "$network_int" "$prefix")

[[ -n $ftp_host ]] || die "$E_NO_FTP" "в подсети не найден ни один хост с открытым портом 21"

log "найден FTP-сервер: $ftp_host"

archive_name="$(basename "$dir")-$(date '+%Y%m%d%H%M%S').tar.gz"
archive_path="$UPLOAD_DIR/$archive_name"

log "архивирую $dir -> $archive_path"
tar -C "$(dirname "$dir")" -czf "$archive_path" "$(basename "$dir")" \
    || die "$E_BAD_DIR" "не удалось создать архив"

log "заливаю $archive_name на ftp://$ftp_host"
if curl --fail --silent --show-error \
        --user "${FTP_USER}:${FTP_PASS}" \
        -T "$archive_path" \
        "ftp://${ftp_host}/${archive_name}"; then
    log "готово: $archive_name загружен на $ftp_host"
    rm -f "$archive_path"
    exit 0
else
    die "$E_UPLOAD" "не удалось загрузить архив на $ftp_host"
fi
