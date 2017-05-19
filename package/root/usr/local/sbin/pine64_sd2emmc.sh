#!/bin/bash

set -e

sed -i 's/--noclear/--autologin pine64 --noclear/g' /lib/systemd/system/getty@.service

apt-get -y update
apt-get -y install pv


cat <<EOF >> /home/pine64/.bashrc

#Install pinebook.img from microSD to eMMC
if [ -e "/pinebook.img" ]; then
	if [ -e "/dev/mmcblk1" ]; then
		echo -e "\nDo you want continue to install Ubuntu Mate from microSD Card to eMMC?\nThis action will wipe out the data in eMMC. [Y/n]"
		read KEY
		if [ "\$KEY" = "Y" ] || [ "\$KEY" = "y" ] || [ -z "\$KEY" ]; then
			echo -e "\n\nInstalling Ubuntu Mate from microSD Card to eMMC...\nDO NOT POWER OFF PINEBOOK\n\n"
			sudo /usr/bin/pv /pinebook.img | sudo /bin/dd of=/dev/mmcblk1
			echo -e "\n\nPlease long press the power button to turn off pinebook and then remove the microSD Card.\nPower on the Pinebook again and it will boot from eMMC with new Ubuntu Mate."
		else
			echo -e "\nNo action performed ...\n"
		fi
	else 
		echo -e "\n\nNo eMMC detected...\n"
	fi
else
	echo -e "\n\nNo pinebook.img found...\nPlease provide a pinebook.img into root partition (/)\n"
fi
EOF


cat <<EOF > /etc/sudoers.d/nopasswd
pine64 pinebook = (root) NOPASSWD: /usr/bin/pv
pine64 pinebook = (root) NOPASSWD: /bin/dd
EOF
chmod 0440 /etc/sudoers.d/nopasswd