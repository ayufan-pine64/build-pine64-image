#!/bin/bash
#
# Simple script to create a rootfs for aarch64 platforms including support
# for Kernel modules created by the rest of the scripting found in this
# module.
#
# Use this script to populate the second partition of disk images created with
# the simpleimage script of this project.
#

set -e

BUILD="../build"
DEST="$1"
LINUX="$2"
PACKAGEDEB="$3"
DISTRO="$4"
BOOT="$5"
MODEL="$6"
VARIANT="$7"
RELEASE_REPO=ayufan-rock64/linux-rootfs
BUILD_ARCH=arm64

if [ -z "$MODEL" ]; then
  MODEL="pine64"
fi

export LC_ALL=C

if [ -z "$DEST" ]; then
	echo "Usage: $0 <destination-folder> [<linux-tarball>] <package.deb> [distro] [<boot-folder>] [model] [variant: mate, i3 or empty]"
	exit 1
fi

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

DEST=$(readlink -f "$DEST")
if [ -n "$LINUX" -a "$LINUX" != "-" ]; then
	LINUX=$(readlink -f "$LINUX")
fi

if [ ! -d "$DEST" ]; then
	echo "Destination $DEST not found or not a directory."
	exit 1
fi

if [ "$(ls -A -Ilost+found $DEST)" ]; then
	echo "Destination $DEST is not empty. Aborting."
	exit 1
fi

if [ -z "$DISTRO" ]; then
	DISTRO="xenial"
fi

if [ -n "$BOOT" ]; then
	BOOT=$(readlink -f "$BOOT")
fi

TEMP=$(mktemp -d)
cleanup() {
	if [ -e "$DEST/proc/cmdline" ]; then
		umount "$DEST/proc"
	fi
	if [ -d "$DEST/sys/kernel" ]; then
		umount "$DEST/sys"
	fi
	umount "$DEST/dev" || true
	umount "$DEST/tmp" || true
	if [ -d "$TEMP" ]; then
		rm -rf "$TEMP"
	fi
}
trap cleanup EXIT

ROOTFS=""
TAR=tar
TAR_OPTIONS=""

case $DISTRO in
	arch)
		version=$(date +%Y%m%d)
		TAR=bsdtar
		ROOTFS="http://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
		TAR_OPTIONS="-p"
		;;
	xenial|zesty)
		version=$(curl -s https://api.github.com/repos/$RELEASE_REPO/releases/latest | jq -r ".tag_name")
		ROOTFS="https://github.com/$RELEASE_REPO/releases/download/${version}/ubuntu-${DISTRO}-${VARIANT}-${version}-${BUILD_ARCH}.tar.xz"
		TAR_OPTIONS="-J --strip-components=1 binary"
		;;
	sid|jessie|stretch)
		version=$(curl -s https://api.github.com/repos/$RELEASE_REPO/releases/latest | jq -r ".tag_name")
		ROOTFS="https://github.com/$RELEASE_REPO/releases/download/${version}/debian-${DISTRO}-${VARIANT}-${version}-${BUILD_ARCH}.tar.xz"
		TAR_OPTIONS="-J --strip-components=1 binary"
		;;
	*)
		echo "Unknown distribution: $DISTRO"
		exit 1
		;;
esac

mkdir -p $BUILD
TARBALL="$TEMP/$(basename $ROOTFS)"

mkdir -p "$BUILD"
if [ ! -e "$TARBALL" ]; then
	echo "Downloading $DISTRO rootfs tarball ..."
	wget -O "$TARBALL" "$ROOTFS"
fi

# Extract with BSD tar
echo -n "Extracting ... "
set -x
$TAR -xf "$TARBALL" -C "$DEST" $TAR_OPTIONS
echo "OK"
#rm -f "$TARBALL"

# Add qemu emulation.
cp /usr/bin/qemu-aarch64-static "$DEST/usr/bin"
cp /usr/bin/qemu-arm-static "$DEST/usr/bin"

# Prevent services from starting
cat > "$DEST/usr/sbin/policy-rc.d" <<EOF
#!/bin/sh
exit 101
EOF
chmod a+x "$DEST/usr/sbin/policy-rc.d"

do_chroot() {
	cmd="$@"
	mount -o bind /tmp "$DEST/tmp"
	chroot "$DEST" mount -t proc proc /proc
	chroot "$DEST" mount -t sysfs sys /sys
	chroot "$DEST" mount -t devtmpfs devtmpfs /dev
	chroot "$DEST" $cmd
	chroot "$DEST" umount /sys
	chroot "$DEST" umount /proc
	chroot "$DEST" umount /dev
	umount "$DEST/tmp"
}

# Run stuff in new system.
case $DISTRO in
	arch)
		mv "$DEST/etc/resolv.conf" "$DEST/etc/resolv.conf.dist"
		cp /etc/resolv.conf "$DEST/etc/resolv.conf"
		sed -i 's|CheckSpace|#CheckSpace|' "$DEST/etc/pacman.conf"
		cat >> "$DEST/etc/pacman.conf" <<EOF
[archlinux-pine]
SigLevel = Never
Server = https://github.com/anarsoul/PKGBUILDs/releases/download/current/
EOF
		do_chroot pacman -Sy --noconfirm || true
		# Cleanup preinstalled Kernel
		do_chroot pacman -Rsn --noconfirm linux-aarch64 || true
		# Remove files installed by make_simpleimage.sh
		do_chroot rm -rf /boot/* || true
		do_chroot pacman -Sy --noconfirm || true
		do_chroot pacman -S --noconfirm --needed dosfstools curl xz iw rfkill netctl dialog wpa_supplicant \
			     alsa-utils pv linux-pine64-bsp rtl8723ds_bt networkmanager || true
		cat >> "$DEST/etc/NetworkManager/NetworkManager.conf" <<EOF
[main]
plugins=keyfile

[keyfile]
unmanaged-devices=interface-name:p2p0
EOF
		do_chroot pacman -S --noconfirm uboot-$MODEL-bin
		cp $PACKAGEDEB $DEST/$(basename $PACKAGEDEB)
		do_chroot pacman -U --noconfirm $(basename $PACKAGEDEB)
		do_chroot rm $(basename $PACKAGEDEB)
		if [ "$MODEL" = "pinebook" ]; then
			do_chroot systemctl enable pinebook-headphones
		fi
		do_chroot systemctl enable getty@tty1
		do_chroot systemctl enable NetworkManager
		do_chroot systemd-machine-id-setup
		case "$VARIANT" in
			xfce)
				do_chroot pacman -S --noconfirm xfce4 xf86-video-fbturbo-git lightdm lightdm-gtk-greeter \
								firefox network-manager-applet xorg-server \
								xf86-input-libinput firefox libvdpau-sunxi-git mpv blueman \
								pulseaudio pulseaudio-alsa pavucontrol
				do_chroot systemctl enable lightdm
				do_chroot systemctl enable NetworkManager
				do_chroot systemctl enable bluetooth
		esac
		cat > "$DEST/second-phase" <<EOF
#!/bin/sh
sed -i 's|^#en_US.UTF-8|en_US.UTF-8|' /etc/locale.gen
cd /usr/share/i18n/charmaps
# locale-gen can't spawn gzip when running under qemu-user, so ungzip charmap before running it
# and then gzip it back
gzip -d UTF-8.gz
locale-gen
gzip UTF-8
localectl set-locale LANG=en_US.utf8
localectl set-keymap us
yes | pacman -Scc
EOF
		chmod +x "$DEST/second-phase"
		do_chroot /second-phase
		do_chroot rm /second-phase
		sed -i 's|#CheckSpace|CheckSpace|' "$DEST/etc/pacman.conf"
		rm -f "$DEST/etc/resolv.conf"
		mv "$DEST/etc/resolv.conf.dist" "$DEST/etc/resolv.conf"
		mv "$DEST"/boot/* "$BOOT"/
		;;
	xenial|sid|jessie|stretch)
		rm "$DEST/etc/resolv.conf"
		cp /etc/resolv.conf "$DEST/etc/resolv.conf"
		if [ "$DISTRO" = "xenial" ]; then
			DEB=ubuntu
			DEBUSER=pine64
			DEBUSERPW=pine64
			ADDPPACMD="apt-get -y update && \
				apt-get install -y software-properties-common && \
				apt-add-repository -y ppa:longsleep/ubuntu-pine64-flavour-makers \
			"
			EXTRADEBS="\
				zram-config \
				ubuntu-minimal \
				sunxi-disp-tool \
			"
		elif [ "$DISTRO" = "sid" -o "$DISTRO" = "jessie" -o "$DISTRO" = "stretch" ]; then
			DEB=debian
			DEBUSER=pine64
			DEBUSERPW=pine64
			ADDPPACMD=""
			EXTRADEBS="sudo"
			ADDPPACMD=
			DISPTOOLCMD=
		else
			echo "Unknown DISTRO=$DISTRO"
			exit 2
		fi
		cat > "$DEST/second-phase" <<EOF
#!/bin/sh
set -ex
export DEBIAN_FRONTEND=noninteractive
locale-gen en_US.UTF-8
$ADDPPACMD
apt-get -y update
apt-get -y install dosfstools curl xz-utils iw rfkill wpasupplicant openssh-server alsa-utils \
	nano git build-essential vim jq wget ca-certificates $EXTRADEBS
apt-get -y remove --purge ureadahead
apt-get -y update
adduser --gecos $DEBUSER --disabled-login $DEBUSER --uid 1000
chown -R 1000:1000 /home/$DEBUSER
echo "$DEBUSER:$DEBUSERPW" | chpasswd
usermod -a -G sudo,adm,input,video,plugdev $DEBUSER
apt-get -y autoremove
apt-get clean
EOF
		chmod +x "$DEST/second-phase"
		do_chroot /second-phase
		cat > "$DEST/etc/network/interfaces.d/eth0" <<EOF
allow-hotplug eth0
iface eth0 inet dhcp
EOF
		cat > "$DEST/etc/hostname" <<EOF
$MODEL
EOF
		cat > "$DEST/etc/pine64_model" <<EOF
$MODEL
EOF
		cat > "$DEST/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $MODEL

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
		cp $PACKAGEDEB $DEST/package.deb
		do_chroot dpkg -i "package.deb"
		do_chroot rm "package.deb"
		case "$VARIANT" in
			mate)
				do_chroot /usr/local/sbin/install_desktop.sh mate
				do_chroot systemctl set-default graphical.target
				;;
			
			i3)
				do_chroot /usr/local/sbin/install_desktop.sh i3
				do_chroot systemctl set-default graphical.target
				;;
		esac
		do_chroot systemctl enable ssh-keygen
		if [ "$MODEL" = "pinebook" ]; then
			do_chroot systemctl enable pinebook-headphones
		fi
		sed -i 's|After=rc.local.service|#\0|;' "$DEST/lib/systemd/system/serial-getty@.service"
		rm -f "$DEST/second-phase"
		rm -f "$DEST/etc/resolv.conf"
		rm -f "$DEST"/etc/ssh/ssh_host_*
		do_chroot ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
		do_chroot apt-get -y autoremove
		do_chroot apt-get clean
		;;
	*)
		;;
esac

# Bring back folders
mkdir -p "$DEST/lib"
mkdir -p "$DEST/usr"

# Create fstab
cat <<EOF > "$DEST/etc/fstab"
# <file system>	<dir>	<type>	<options>			<dump>	<pass>
/dev/mmcblk0p1	/boot	vfat	defaults			0		2
/dev/mmcblk0p2	/	ext4	defaults,noatime		0		1
EOF

# Direct Kernel install
if [ -n "$LINUX" -a "$LINUX" != "-" -a -d "$LINUX" ]; then
	# NOTE(longsleep): Passing Kernel as folder is deprecated. Pass a tarball!

	mkdir "$DEST/lib/modules"
	# Install Kernel modules
	make -C $LINUX ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_install INSTALL_MOD_PATH="$DEST"
	# Install Kernel firmware
	make -C $LINUX ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- firmware_install INSTALL_MOD_PATH="$DEST"
	# Install Kernel headers
	make -C $LINUX ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- headers_install INSTALL_HDR_PATH="$DEST/usr"

	# Install extra mali module if found in Kernel tree.
	if [ -e $LINUX/modules/gpu/mali400/kernel_mode/driver/src/devicedrv/mali/mali.ko ]; then
		v=$(ls $DEST/lib/modules/)
		mkdir "$DEST/lib/modules/$v/kernel/extramodules"
		cp -v $LINUX/modules/gpu/mali400/kernel_mode/driver/src/devicedrv/mali/mali.ko $DEST/lib/modules/$v/kernel/extramodules
		depmod -b $DEST $v
	fi
elif [ -n "$LINUX" -a "$LINUX" != "-" ]; then
	# Install Kernel modules from tarball
	mkdir $TEMP/kernel
	tar -C $TEMP/kernel --numeric-owner -xJf "$LINUX"
	if [ -n "$BOOT" -a -e "$BOOT/uEnv.txt" ]; then
		# Install Kernel and uEnv.txt too.
		echo "Installing Kernel to boot $BOOT ..."
		rm -rf "$BOOT/pine64"
		rm -f "$BOOT/uEnv.txt"
		cp -RLp $TEMP/kernel/boot/* "$BOOT/"
		mv "$BOOT/uEnv.txt.in" "$BOOT/uEnv.txt"
	fi
	cp -RLp $TEMP/kernel/lib/* "$DEST/lib/" 2>/dev/null || true
	cp -RLp $TEMP/kernel/usr/* "$DEST/usr/"

	VERSION=""
	if [ -e "$TEMP/kernel/boot/Image.version" ]; then
		VERSION=$(cat $TEMP/kernel/boot/Image.version)
	fi

	if [ -n "$VERSION" ]; then
		# Create symlink to headers if not there.
		if [ ! -e "$DEST/lib/modules/$VERSION/build" ]; then
			ln -s /usr/src/linux-headers-$VERSION "$DEST/lib/modules/$VERSION/build"
		fi

		depmod -b $DEST $VERSION
	fi
fi

# Clean up
rm -f "$DEST/usr/bin/qemu-arm-static"
rm -f "$DEST/usr/bin/qemu-aarch64-static"
rm -f "$DEST/usr/sbin/policy-rc.d"
rm -f "$DEST/var/lib/dbus/machine-id"
rm -f "$DEST/SHA256SUMS"

echo "Done - installed rootfs to $DEST"
