#!/bin/sh

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
MODDIR=/data/adb/modules/playintegrityfix
version=$(grep "^version=" $MODDIR/module.prop | sed 's/version=//g')

. $MODDIR/common_func.sh

# lets try to use tmpfs for processing
TEMPDIR="$MODDIR/temp" #fallback
[ -w /sbin ] && TEMPDIR="/sbin/playintegrityfix"
[ -w /debug_ramdisk ] && TEMPDIR="/debug_ramdisk/playintegrityfix"
[ -w /dev ] && TEMPDIR="/dev/playintegrityfix"
mkdir -p "$TEMPDIR"
cd "$TEMPDIR"

echo "[+] PlayIntegrityFix $version"
echo "[+] $(basename "$0")"
printf "\n\n"

pifProp="$MODDIR/pif.prop"
[ -f "/data/adb/pif.prop" ] && pifProp="/data/adb/pif.prop"

bail_out() {
	echo "$1"
	rm -rf "$TEMPDIR"
	sleep_pause
	exit 1
}

# read a field from the pif.prop currently in use
prop_value() {
	[ -f "$pifProp" ] || return 1
	grep "^$1=" "$pifProp" | head -n1 | cut -d= -f2-
}

# $1 is an optional offset, it lets callers walk to another device when the
# first pick turns out to have no Canary build
set_random_beta() {
	count=$(echo "$PRODUCT_LIST" | wc -l)
	if [ -z "$PRODUCT_LIST" ] || [ "$(echo "$MODEL_LIST" | wc -l)" -ne "$count" ]; then
		echo "Warning: MODEL_LIST and PRODUCT_LIST have different lengths, using Pixel 6 fallback"
		MODEL="Pixel 6"
		PRODUCT="oriole_beta"
	else
		rand_index=$(( ($$ + ${1:-0}) % count ))
		MODEL=$(echo "$MODEL_LIST" | sed -n "$((rand_index + 1))p")
		PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "$((rand_index + 1))p")
	fi
}

# a MODEL that doesn't belong to PRODUCT describes a device that doesn't exist,
# so always take the model name from the device list when the product is listed
sync_model() {
	index=$(echo "$PRODUCT_LIST" | grep -nxF "$PRODUCT" | cut -d: -f1 | head -n1)
	[ -n "$index" ] && MODEL=$(echo "$MODEL_LIST" | sed -n "${index}p")
}

get_model_product_list() {
	printf "{\"model\":["
	count=0
	total=$(echo "$MODEL_LIST" | wc -l)
	echo "$MODEL_LIST" | while read -r model; do
		count=$((count + 1))
		printf "\"%s\"" "$model"
		[ $count -lt $total ] && printf ","
	done
	printf "],\"product\":["
	count=0
	total=$(echo "$PRODUCT_LIST" | wc -l)
	echo "$PRODUCT_LIST" | while read -r product; do
		count=$((count + 1))
		printf "\"%s\"" "$product"
		[ $count -lt $total ] && printf ","
	done
	printf "]}"

	rm -rf "$TEMPDIR"
	exit 0
}

# Look up the Canary build of $1, sets ID / INCREMENTAL / CANARY_ID.
# Returns non-zero when that product has no Canary build published.
fetch_canary_build() {
	if command -v curl > /dev/null 2>&1; then
		curl --connect-timeout 10 -H "Referer: https://flash.android.com" -s "https://content-flashstation-pa.googleapis.com/v1/builds?product=$1&key=$FLASH_KEY" > PIXEL_STATION_JSON || download_fail "https://flash.android.com"
	else
		busybox wget -T 10 --header "Referer: https://flash.android.com" -qO - "https://content-flashstation-pa.googleapis.com/v1/builds?product=$1&key=$FLASH_KEY" > PIXEL_STATION_JSON || download_fail "https://flash.android.com"
	fi
	busybox tac PIXEL_STATION_JSON | busybox grep -m1 -A13 '"canary": true' > PIXEL_CANARY_JSON
	ID="$(grep 'releaseCandidateName' PIXEL_CANARY_JSON | cut -d\" -f4)"
	INCREMENTAL="$(grep 'buildId' PIXEL_CANARY_JSON | cut -d\" -f4)"
	CANARY_ID="$(grep '"id"' PIXEL_CANARY_JSON | sed -e 's;.*canary-\(.*\)".*;\1;' -e 's;^\(.\{4\}\);\1-;')"
	[ -n "$ID" ] && [ -n "$INCREMENTAL" ]
}

# Get latest Pixel Canary information
download https://developer.android.com/about/versions PIXEL_VERSIONS_HTML
# Platform links come in absolute and relative form, and sorting them as text
# ranks "9" above "17", which pins the device list to an old release. Pull the
# version numbers out and sort them as numbers instead.
LATEST_VERSION=$(grep -oE 'href="(https://developer\.android\.com)?/about/versions/[0-9]+"' PIXEL_VERSIONS_HTML | grep -oE '[0-9]+' | sort -rn | head -n1)
[ -n "$LATEST_VERSION" ] || bail_out "! Failed to determine the latest Android version"
download "https://developer.android.com/about/versions/$LATEST_VERSION" PIXEL_LATEST_HTML

# Get FI and OTA information and use the longer device list
FI_PATH="$(grep -oE 'href="[^"]*/download"' PIXEL_LATEST_HTML | cut -d\" -f2 | sort -ru | head -n1)"
OTA_PATH="$(grep -oE 'href="[^"]*/download-ota"' PIXEL_LATEST_HTML | cut -d\" -f2 | sort -ru | head -n1)"
[ -n "$FI_PATH" ] || FI_PATH="$OTA_PATH"
[ -n "$OTA_PATH" ] || OTA_PATH="$FI_PATH"
[ -n "$FI_PATH" ] || bail_out "! Failed to find the Pixel download page for Android $LATEST_VERSION"
download "https://developer.android.com$FI_PATH" PIXEL_FI_HTML
download "https://developer.android.com$OTA_PATH" PIXEL_OTA_HTML
SRC=FI; [ "$(grep 'tr id=' PIXEL_FI_HTML | sed 's;.*<tr id="\(.*\)">.*;\1;' | wc -w)" -lt "$(grep 'tr id=' PIXEL_OTA_HTML | sed 's;.*<tr id="\(.*\)">.*;\1;' | wc -w)" ] && SRC=OTA

# Extract device information
MODEL_LIST="$(grep -A1 'tr id=' PIXEL_${SRC}_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>.*;\1;')";
PRODUCT_LIST="$(grep 'tr id=' PIXEL_${SRC}_HTML | sed 's;.*<tr id="\(.*\)">.*;\1_beta;')";

# List available devices
if [ "$1" = "--list" ] || [ "$1" = "-l" ]; then
	get_model_product_list
fi

download https://flash.android.com PIXEL_FLASH_HTML
FLASH_KEY=$(grep -o '<body data-client-config=.*' PIXEL_FLASH_HTML | cut -d\; -f2 | cut -d\& -f1)

# Select and configure device
echo "- Selecting Pixel Canary device ..."
if [ -z "$PRODUCT" ]; then
	# Nothing was requested, so keep the device that is already configured
	# instead of rerolling it on every run
	PRODUCT="$(prop_value FINGERPRINT | cut -d/ -f2)"
	[ -n "$PRODUCT" ] && MODEL="$(prop_value MODEL)"
fi
sync_model
[ -n "$MODEL" ] && [ -n "$PRODUCT" ] || set_random_beta

# The device list and the Canary channel don't always cover the same devices,
# a newly announced Pixel can be listed months before it gets a Canary build
attempt=0
while ! fetch_canary_build "$PRODUCT"; do
	echo "! No Pixel Canary build published for $MODEL ($PRODUCT)"
	attempt=$((attempt + 1))
	[ "$attempt" -le "$(echo "$PRODUCT_LIST" | wc -l)" ] || bail_out "! Failed to get pif.prop"
	set_random_beta "$attempt"
	echo "- Falling back to $MODEL ($PRODUCT)"
done
echo "$MODEL ($PRODUCT)"

# Get device fingerprint and security patch from Flash Tool and bulletins
DEVICE="$(echo "$PRODUCT" | sed 's/_beta//')"
FINGERPRINT="google/$PRODUCT/$DEVICE:CANARY/$ID/$INCREMENTAL:user/release-keys"
download https://source.android.com/docs/security/bulletin/pixel PIXEL_SECBULL_HTML
SECURITY_PATCH="$(grep "<td>$CANARY_ID" PIXEL_SECBULL_HTML | sed 's;.*<td>\(.*\)</td>;\1;')"

if [ -z "$SECURITY_PATCH" ]; then
	echo "! Failed to determine exact security patch level"
	echo "- Assuming probable security patch level from Canary build info"
	SECURITY_PATCH="${CANARY_ID}-05"
fi

# Preserve previous setting
spoofConfig="spoofBuild spoofProps spoofProvider spoofSignature spoofVendingBuild spoofVendingSdk DEBUG"
for config in $spoofConfig; do
	if grep -q "$config=true" "$pifProp" 2>/dev/null; then
		eval "$config=true"
	else
		eval "$config=false"
	fi
done

echo "- Dumping values to pif.prop ..."
echo ""
cat <<EOF | tee pif.prop
FINGERPRINT=$FINGERPRINT
MANUFACTURER=Google
MODEL=$MODEL
SECURITY_PATCH=$SECURITY_PATCH
spoofBuild=$spoofBuild
spoofProps=$spoofProps
spoofProvider=$spoofProvider
spoofSignature=$spoofSignature
spoofVendingBuild=$spoofVendingBuild
spoofVendingSdk=$spoofVendingSdk
DEBUG=$DEBUG
EOF

cat "$TEMPDIR/pif.prop" > /data/adb/pif.prop
echo ""
echo "- new pif.prop saved to /data/adb/pif.prop"

if [ -e "/data/adb/tricky_store/pif_auto_security_patch" ]; then
	sh "$MODDIR/security_patch.sh"
else
	rm -f $MODDIR/system.prop
fi

echo "- Cleaning up ..."
rm -rf "$TEMPDIR"

for i in $(busybox pidof com.google.android.gms.unstable com.android.vending); do
	echo "- Killing pid $i"
	kill -9 "$i"
done

echo "- Done!"
sleep_pause
