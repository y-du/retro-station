#!/bin/bash


NOCOLOR="\e[0m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
WHITE="\e[97m"
DARKGRAY="\e[90m"
LIGHT_GRAY="\e[37m"
LIGHT_RED="\e[91m"
LIGHT_GREEN="\e[92m"
LIGHT_YELLOW="\e[93m"
LIGHT_BLUE="\e[94m"
LIGHT_MAGENTA="\e[95m"
LIGHT_CYAN="\e[96m"


KEYMAP="de"
LOCALE="en_US.UTF-8"
TZ="Europe/Berlin"
HOSTNAME="retro-station"


clear

echo -e "${LIGHT_BLUE}\** retro-station system setup **/${NOCOLOR}\n"
if [ "$EUID" -ne "0" ]; then
	echo -e "${LIGHT_RED}system setup must be run as root${NOCOLOR}"
	exit 1
fi

while true; do
	echo -n -e "choose keymap (default $KEYMAP): "
	read input
	if [ "$input" != "" ]; then
		if localectl list-keymaps | grep -x -q "$input"; then
			KEYMAP="$input"
			break
		else
			echo -e "${LIGHT_RED}invalid keymap '$input'${NOCOLOR}"
		fi
	else
		break
	fi	
done

while true; do
	echo -n -e "choose time zone (default $TZ): "
	read input
	if [ "$input" != "" ]; then
		if timedatectl list-timezones | grep -x -q "$input"; then
			TZ="$input"
			break
		else
			echo -e "${LIGHT_RED}invalid time zone '$input'${NOCOLOR}"
		fi
	else
		break
	fi	
done

echo ""
while true; do
	echo -n -e "are the settings correct? (y/n): "
	read input
	if [ "$input" == "y" ] || [ "$input" == "n" ]; then
		if [ "$input" == "y" ]; then
			break
		else
			exit 0
		fi
	fi	
done

echo -e "\nsetting time zone ..."
if ! timedatectl set-timezone $TZ; then
	exit 1
fi

echo "setting keymap ..."
if ! localectl set-keymap $KEYMAP; then
	exit 1
fi

echo "generating locale ..."
if ! echo "$LOCALE UTF-8" >> /etc/locale.gen; then
	exit 1
fi

if ! locale-gen; then
	exit 1
fi

echo "setting locale ..."
if ! localectl set-locale LANG=$LOCALE; then
	exit 1
fi

echo "suppress kernel messages on tty ..."
if ! echo "kernel.printk = 3 4 1 6" > /etc/sysctl.d/00-printk.conf; then
	exit 1
fi

echo -e "setting hostname ..."
if ! hostnamectl set-hostname $HOSTNAME; then
	exit 1
fi

echo "init pacman ..."
while true; do
	if ! pacman-key --init; then
		break
	fi
	sleep 5
done

while true; do
	if ! pacman-key --populate archlinuxarm; then
		break
	fi
	sleep 5
done

echo "update system ..."
while true; do
	pacman -S --noconfirm retroarch retroarch-assets-glui retroarch-assets-ozone retroarch-assets-xmb libbluray libglvnd alsa-utils libxinerama libxrandr rxvt-unicode-terminfo polkit unzip ufw
	if [ "$?" -eq "0" ]; then
		break
	fi
	sleep 5
done

echo -e "\nsystem-setup completed successfully\n"
while true; do
	echo -n -e "reboot system? (y/n): "
	read input
	if [ "$input" == "y" ] || [ "$input" == "n" ]; then
		if [ "$input" == "y" ]; then
			reboot
		else
			exit 0
		fi
	fi	
done

