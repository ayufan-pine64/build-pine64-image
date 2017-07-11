#!/bin/sh

set -e

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

VERSION="$1"

if [ -z "$1" ]; then
	VERSION=$(curl -s https://api.github.com/repos/ayufan-pine64/linux-build/releases/latest | jq -r ".tag_name")
	if [ -z "$VERSION" ]; then
		echo "Latest release was not found. Please go to: $LATEST_LIST"
		exit 1
	fi

	echo "Using latest release: $VERSION."
fi

URL="https://github.com/ayufan-pine64/linux-build/releases/download/$VERSION/linux-pine64-$VERSION.tar.xz"
# URL="https://www.stdin.xyz/downloads/people/longsleep/pine64-images/linux/linux-pine64$VARIANT-$VERSION.tar.xz"
# PUBKEY="https://www.stdin.xyz/downloads/people/longsleep/longsleep.asc"
CURRENTFILE="/var/lib/misc/pine64_update_kernel.status"

TEMP=$(mktemp -d -p /var/tmp)

cleanup() {
	if [ -d "$TEMP" ]; then
		rm -rf "$TEMP"
	fi
}
trap cleanup EXIT INT

CURRENT=""
if [ -e "${CURRENTFILE}" ]; then
	CURRENT=$(cat $CURRENTFILE)
fi

FILENAME=$TEMP/$(basename ${URL})

downloadAndApply() {
	echo "Downloading Linux Kernel ..."
	curl -L "${URL}" -f --progress-bar --output "${FILENAME}"
	# echo "Downloading signature ..."
	# curl "${URL}.asc" -f --progress-bar --output "${FILENAME}.asc"
	# echo "Downloading public key ..."
	# curl "${PUBKEY}" -f --progress-bar --output "${TEMP}/pub.asc"

	# echo "Verifying signature ..."
	# gpg --homedir "${TEMP}" --yes -o "${TEMP}/pub.gpg" --dearmor "${TEMP}/pub.asc"
	# gpg --homedir "${TEMP}" --status-fd 1 --no-default-keyring --keyring "${TEMP}/pub.gpg" --trust-model always --verify "${FILENAME}.asc" 2>/dev/null

	echo "Extracting ..."
	mkdir $TEMP/update
	tar -C $TEMP/update --numeric-owner -xJf "${FILENAME}"
	cp -RLp $TEMP/update/boot/* /boot/
	cp -RLp $TEMP/update/lib/* /lib/ 2>/dev/null || true
	cp -RLp $TEMP/update/usr/* /usr/

	echo "Fixing up ..."
	if [ ! -e "/boot/uEnv.txt" -a -e "/boot/uEnv.txt.in" ]; then
		# Install default uEnv.txt when not there.
		mv "/boot/uEnv.txt.in" "/boot/uEnv.txt"
	fi

	VERSION=""
	if [ -e "$TEMP/update/boot/Image.version" ]; then
		VERSION=$(cat $TEMP/update/boot/Image.version)
	fi

	if [ -n "$VERSION" ]; then
		# Create symlink to headers if not there.
		if [ ! -e /lib/modules/$VERSION/build ]; then
			ln -s /usr/src/linux-headers-$VERSION /lib/modules/$VERSION/build
		fi

		# New Kernel with postinst support ...
		depmod "$VERSION"

		echo "Running postinst for $VERSION ..."
		if [ -e "/etc/kernel/header_postinst.d" ]; then
			run-parts -v -a "$VERSION" /etc/kernel/header_postinst.d
		fi
	fi

}

if [ -z "$MARK_ONLY" ]; then
	downloadAndApply
	sync
	echo "Done - you should reboot now."
else
	echo "Mark only."
fi
echo "$ETAG" > "$CURRENTFILE"
sync
