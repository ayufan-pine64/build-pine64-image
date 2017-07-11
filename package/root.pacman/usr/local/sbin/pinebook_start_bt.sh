#!/bin/sh
sleep 10
rfkill unblock 0
/usr/sbin/rtk_hciattach -n -s 115200 /dev/ttyS1 rtk_h5
