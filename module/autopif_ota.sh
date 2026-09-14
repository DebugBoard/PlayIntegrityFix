#!/bin/sh

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
MODDIR=/data/adb/modules/playintegrityfix

# lets try to use tmpfs for processing
TEMPDIR="$MODDIR/temp" #fallback
[ -w /sbin ] && TEMPDIR="/sbin/playintegrityfix"
[ -w /debug_ramdisk ] && TEMPDIR="/debug_ramdisk/playintegrityfix"
[ -w /dev ] && TEMPDIR="/dev/playintegrityfix"
mkdir -p "$TEMPDIR"

# curl_works(), shared with autopif.sh; if this file is missing the fallback
# below still downloads with busybox wget
. "$MODDIR/common_func.sh" 2>/dev/null

download() {
    if command -v curl_works > /dev/null 2>&1 && curl_works; then
        curl --connect-timeout 10 -Ls "$1" > "$2"
    else
        busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2"
    fi
}

# fetch script
fetch_autopif() {
    if download "$1" "$TEMPDIR/temp_autopif.sh"; then
        if ! grep -q "^#!/bin/sh" $TEMPDIR/temp_autopif.sh; then
            return 1
        fi

        # hash
        curhash="$(cat $MODDIR/autopif.sh | busybox crc32)"
        newhash="$(cat $TEMPDIR/temp_autopif.sh | busybox crc32)"

        if [ ! "$newhash" = "$curhash" ]; then
            cat "$TEMPDIR/temp_autopif.sh" > "$MODDIR/autopif.sh"
            echo "[+] autopif has been updated"
        fi

        return 0
    else
        return 1
    fi
}

main_link="https://raw.githubusercontent.com/KOWX712/PlayIntegrityFix/inject_s/module/autopif.sh"
fallback_link="https://raw.gitmirror.com/KOWX712/PlayIntegrityFix/inject_s/module/autopif.sh"

if fetch_autopif "$main_link"; then
    true
elif fetch_autopif "$fallback_link"; then
    true
else
    echo "[!] OTA failed, skipping autopif update."
fi

rm -rf "$TEMPDIR"

# EOF
