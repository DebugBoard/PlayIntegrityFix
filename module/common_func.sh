# resetprop_if_diff <prop name> <expected value>
resetprop_if_diff() {
    local NAME="$1"
    local EXPECTED="$2"
    local CURRENT="$(resetprop "$NAME")"

    [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || resetprop -n "$NAME" "$EXPECTED"
}

# resetprop_if_match <prop name> <value match string> <new value>
resetprop_if_match() {
    local NAME="$1"
    local CONTAINS="$2"
    local VALUE="$3"

    [[ "$(resetprop "$NAME")" = *"$CONTAINS"* ]] && resetprop -n "$NAME" "$VALUE"
}

# stub for boot-time
ui_print() { return; }

sleep_pause() {
    # APatch and KernelSU needs this
    # but not KSU_NEXT, MMRL
    if [ -z "$MMRL" ] && [ -z "$KSU_NEXT" ] && { [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; }; then
        sleep 5
    fi
}

download_fail() {
    dl_domain=$(echo "$1" | awk -F[/:] '{print $4}')
    # Clean up on download fail
    rm -rf "$TEMPDIR"
    ping -c 1 -W 5 "$dl_domain" > /dev/null 2>&1 || {
        echo "[!] Unable to connect to $dl_domain, please check your internet connection and try again"
        sleep_pause
        exit 1
    }
    conflict_module=$(ls /data/adb/modules | grep busybox)
    for i in $conflict_module; do 
        echo "[!] Please remove $i and try again." 
    done
    echo "[!] download failed!"
    echo "[x] bailing out!"
    sleep_pause
    exit 1
}

# curl can be present but unusable, e.g. a partially upgraded Termux leaves a
# curl binary that the linker rejects ("cannot locate symbol ..."), so run it
# instead of trusting `command -v`. The result is cached and only probed on the
# first download, to keep sourcing this file at boot free of extra spawns.
curl_works() {
    if [ -z "$CURL_WORKS" ]; then
        if ! command -v curl > /dev/null 2>&1; then
            CURL_WORKS=false
        elif curl --version > /dev/null 2>&1; then
            CURL_WORKS=true
        else
            CURL_WORKS=false
            echo "[!] curl is installed but not usable, falling back to busybox wget"
        fi
    fi
    [ "$CURL_WORKS" = true ]
}

download() {
    if curl_works; then
        curl --connect-timeout 10 -s "$1" > "$2" || download_fail "$1"
    else
        busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2" || download_fail "$1"
    fi
}
