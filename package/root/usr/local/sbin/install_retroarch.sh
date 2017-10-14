#!/bin/bash

#check for root
if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

#echo commands and arguments, and exit if any command returns non-zero status
set -xe

#add extra repositories
add-apt-repository ppa:libretro/testing -y
apt-add-repository -y ppa:ayufan/pine64-ppa -y

#Installs x for retroarch to run in
PACKAGES=(
	x-window-system
	xterm
	twm
	)

#Necessary dependencies
PACKAGES+=(
	libsdl1.2-dev
	libsdl1.2debian
	pkg-config
	build-essential
	)

#Add libretro and retroarch
PACKAGES+=(
	retroarch*
	libretro*
	)

#Add Samba for SMB file shares
PACKAGES+=(
	samba
	samba-common-bin
	)

#Add the gpu support stuff
PACKAGES+=(
	xserver-xorg-video-armsoc-sunxi
	libmali-sunxi-utgard0-r6p0
	)

# Install
apt-get update -y
apt-get -y --no-install-recommends install ${PACKAGES[@]}

# Kill parport module loading, not available on arm64.
if [ -e "/etc/modules-load.d/cups-filters.conf" ]; then
	echo "" >/etc/modules-load.d/cups-filters.conf
fi

#enable autologin
mkdir -pv /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pine64 --noclear %I 38400 linux
EOF
systemctl enable getty@tty1.service

#Autostart retroarch on login
cat > /etc/profile.d/10-start-retroarch.sh <<EOF
# autolaunch retroarch if not serial console login
if [ -z "\$DISPLAY" ] && [ "\$(tty)" != "/dev/ttyS0" ]; then
	/usr/local/bin/powerdown-on-retroarch-close.sh &
	echo -e "\n\nRetroarch will start momentarily...\n\n"
	sleep 2
	startx retroarch
fi
EOF
chmod +x /etc/profile.d/10-start-retroarch.sh

#shutdown script run when retroarch autolaunched
cat > /usr/local/bin/powerdown-on-retroarch-close.sh <<EOF
#!/bin/bash

#wait for retroarch
while [[ \$(pgrep retroarch | wc -l) -eq 0 ]]; do
	sleep 2
done

#wait for retroarch to close
while [[ \$(pgrep retroarch | wc -l) -ne 0 ]]; do
	sleep 2
done

#shutdown system
echo -e "\n\nRetroarch no longer running... powering off system!\n\n"
sudo /sbin/poweroff
EOF
chmod +x /usr/local/bin/powerdown-on-retroarch-close.sh

#change hostname (will also update motd banner)
echo "retroarch" > /etc/hostname
sed -i "s/pine64/retroarch/g" /etc/hosts

#retropie header
cat > /etc/update-motd.d/05-figlet <<EOF
#!/bin/sh
figlet \$(hostname)
EOF
chmod +x /etc/update-motd.d/05-figlet

#hide other MOTD banners
chmod -x /etc/update-motd.d/00-header
chmod -x /etc/update-motd.d/10-help-text
chmod -x /etc/update-motd.d/11-pine-a64-help-text

#prevent any tty permission X.org errors
usermod pine64 -aG tty

#allow passwordless shutdown
cat >> /etc/sudoers <<EOF
pine64 ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown
EOF

#download custom wallpaper from extras repo
curl -L -o "/home/pine64/pine64-retroarch-wallpaper.png" https://github.com/pfeerick-pine64/linux-extras/raw/master/retroarch/

#backup stock default config
DEFAULT_CFG="/etc/retroarch.cfg"
cp ${DEFAULT_CFG} /etc/retroarch.cfg.stock

#download optimised version
curl -L -o ${DEFAULT_CFG} https://raw.githubusercontent.com/pfeerick-pine64/linux-extras/master/retroarch/optimised_config

#Set up SMB sharefolder for ROMs and BIOS
mkdir -pv /home/pine64/ROMs
chown nobody:nogroup -R /home/pine64/ROMs

cat >> /etc/samba/smb.conf <<EOF
[ROMs]
comment = ROMs Folder
path = /home/pine64/ROMs
writeable = yes
browseable = yes
guest ok = yes
create mask = 0644
directory mask = 2777
EOF

#Enables mali + drm
exec /usr/local/sbin/pine64_enable_sunxidrm.sh

exit 0
