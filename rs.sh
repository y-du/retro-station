#!/bin/bash


#   Copyright 2021 Yann Dumont
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.


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


UNDERVOLTED=0x1
CAPPED=0x2
THROTTLED=0x4
SOFT_TEMPLIMIT=0x8
HAS_UNDERVOLTED=0x10000
HAS_CAPPED=0x20000
HAS_THROTTLED=0x40000
HAS_SOFT_TEMPLIMIT=0x80000


RS_FLAG_FILE=".rs-flag"
RS_FLAG_RESTART="0"
RS_FLAG_REBOOT="1"
RS_FLAG_RST_CONF="2"
RS_FLAG_KILL="3"


INSTALL_PATH=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )


installRS() {
	if [ "$EUID" -ne "0" ]; then
		echo -e "${LIGHT_RED}install must be run as root${NOCOLOR}"
		exit 1
	fi
	clear
	echo -e "${LIGHT_BLUE}\** retro-station install **/${NOCOLOR}\n"
	while true; do
		echo -n -e "install for user (default $USER): "
		read input
		if [ "$input" != "" ]; then
			if ! id -u "$input"; then
				RS_USER="$input"
				break
			else
				echo -e "${LIGHT_RED}user '$input' does not exist${NOCOLOR}"
			fi
		else
			RS_USER=$USER
			break
		fi
	done
	echo "retro-station user: $RS_USER"
	echo "install retroarch and dependencies ..."
	while true; do
		if ! pacman -S --noconfirm retroarch retroarch-assets-glui retroarch-assets-ozone retroarch-assets-xmb libbluray libglvnd alsa-utils libxinerama libxrandr rxvt-unicode-terminfo polkit unzip ufw ntp; then
			break
		fi
		sleep 5
	done
	echo "create directories ..."
	su -c "mkdir -p -v /home/$RS_USER/saves" $RS_USER && \
	su -c "mkdir -p -v /home/$RS_USER/screenshots" $RS_USER && \
	su -c "mkdir -p -v /home/$RS_USER/states" $RS_USER && \
	su -c "mkdir -p -v /home/$RS_USER/cores" $RS_USER && \
	su -c "mkdir -p -v /home/$RS_USER/system" $RS_USER && \
	su -c "mkdir -p -v /home/$RS_USER/games" $RS_USER && \
	su -c "mkdir -p -v /home/$RS_USER/.config/retroarch/autoconfig" $RS_USER && \
	su -c "mkdir -p -v /home/$RS_USER/.config/retroarch/cores/info" $RS_USER
	if [ "$?" -ne "0" ]; then
		exit 1
	fi
	echo "download assets ..."
	while true; do
		su -c "curl https://buildbot.libretro.com/assets/frontend/info.zip -o /tmp/info.zip" $RS_USER
		if [ "$?" -eq "0" ]; then
			break
		fi
		rm -f /tmp/info.zip
		sleep 5
	done
	while true; do
		su -c "curl https://buildbot.libretro.com/assets/frontend/autoconfig.zip -o /tmp/autoconfig.zip" $RS_USER
		if [ "$?" -eq "0" ]; then
			break
		fi
		rm -f /tmp/autoconfig.zip
		sleep 5
	done
	echo "copy files ..."
	su -c "cp -v override.cfg /home/$RS_USER/.override.cfg" $RS_USER && \
	su -c "unzip /tmp/autoconfig.zip -d /home/$RS_USER/.config/retroarch/autoconfig" $RS_USER && \
	su -c "unzip /tmp/info.zip -d /home/$RS_USER/.config/retroarch/cores/info" $RS_USER && \
	rm -f /tmp/autoconfig.zip && \
	rm -f /tmp/info.zip
	if [ "$?" -ne "0" ]; then
		exit 1
	fi
	echo "add global alias ..."
	if ! echo "alias retro-station=$INSTALL_PATH/rs.sh" >> /etc/bash.bashrc; then
		exit 1
	fi
	echo "create retroarch service ..."
	echo "[Unit]
After=systemd-user-sessions.service network.target sound.target
Conflicts=getty@tty1.service

[Service]
User=$RS_USER
Group=$RS_USER
PAMName=login
TTYPath=/dev/tty1
ExecStart=$INSTALL_PATH/rs.sh run
StandardInput=tty

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/retroarch.service && \
	chmod 664 /etc/systemd/system/retroarch.service
	if [ "$?" -ne "0" ]; then
		exit 1
	fi
	echo "enable retroarch service ..."
	systemctl daemon-reload && systemctl enable retroarch.service
	if [ "$?" -ne "0" ]; then
		exit 1
	fi
	echo -e "\ninstall completed successfully\n"
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
}


setFirewall() {
	if [ "$EUID" -ne "0" ]; then
		echo -e "${LIGHT_RED}set-firewall must be run as root${NOCOLOR}"
		exit 1
	fi
	clear
	echo -e "getting firewall status ...\n"
	if ufw status | grep -q "inactive"; then
		echo -e "firewall is ${LIGHT_RED}inactive${NOCOLOR}\n"
		while true; do
			echo -n -e "enable firewall? (y/n): "
			read input
			if [ "$input" == "y" ] || [ "$input" == "n" ]; then
				if [ "$input" == "y" ]; then
					echo ""
					ufw default deny incoming && \
					ufw default allow outgoing && \
					ufw allow ssh && \
					ufw logging off
					echo ""
					ufw enable
					echo ""
					break
				else
					exit 0
				fi
			fi
		done
	else
		echo -e "firewall is ${LIGHT_GREEN}active${NOCOLOR}\n"
		while true; do
			echo -n -e "disable firewall? (y/n): "
			read input
			if [ "$input" == "y" ] || [ "$input" == "n" ]; then
				if [ "$input" == "y" ]; then
					echo ""
					ufw disable
					echo ""
					break
				else
					exit 0
				fi
			fi
		done
	fi
}


setAudioCard() {
	clear
	cd
	aplay -l | grep "card"
	echo ""
	while true; do
		echo -n -e "choose card (default 0): "
		read card
		if [[ $card =~ ^[0-9]+$ ]] || [ "$card" == "" ]; then
			if [ "$card" == "" ]; then
				card="0"
			fi
			break
		else
			echo -e "${LIGHT_RED}invalid input '$card'${NOCOLOR}\n"
		fi
	done
	while true; do
		echo -n -e "choose device (default 0): "
		read device
		if [[ $device =~ ^[0-9]+$ ]] || [ "$device" == "" ]; then
			if [ "$device" == "" ]; then
				device="0"
			fi
			break
		else
			echo -e "${LIGHT_RED}invalid input '$device'${NOCOLOR}\n"
		fi
	done
	if grep -q "audio_device" .override.cfg; then
		sed -i -r 's/^audio_device = .*/audio_device = "hw:'$card','$device'"/' .override.cfg
	else
		echo 'audio_device = "hw:'$card','$device'"' >> .override.cfg
	fi
	echo $RS_FLAG_RESTART > $RS_FLAG_FILE
	echo -e "\nquit retroarch for changes to take effect\n"
}


setAudioDriver() {
	clear
	cd
	echo -e "0: alsa\n1: alsathread\n"
	while true; do
		echo -n -e "choose driver (default 0): "
		read driver
		if [[ $driver =~ ^[0-9]+$ ]] && [ "$driver" -ge "0" ] && [ "$driver" -le "1" ] || [ "$driver" == "" ]; then
			if [ "$driver" == "" ] || [ "$driver" -eq "0" ]; then
				driver="alsa"
			else
				driver="alsathread"
			fi
			break
		else
			echo -e "${LIGHT_RED}invalid input '$driver'${NOCOLOR}\n"
		fi
	done
	sed -i -r 's/^audio_driver = .*/audio_driver = "'$driver'"/' .override.cfg
	echo $RS_FLAG_RESTART > $RS_FLAG_FILE
	echo -e "\nquit retroarch for changes to take effect\n"
}


hwMonitor() {
	while true; do
		clear
		echo -e "${LIGHT_BLUE}CPU frequencies:${NOCOLOR}"
		for num in 0 1 2 3 ; do
			echo "core_$num=$(($(cat /sys/devices/system/cpu/cpu$num/cpufreq/scaling_cur_freq)/1000))MHz"
		done
		echo -e "\n${LIGHT_BLUE}Temp and voltages:${NOCOLOR}"
		echo "cpu_$(/opt/vc/bin/vcgencmd measure_temp)"
		echo "cpu_$(/opt/vc/bin/vcgencmd measure_volts core)"
		echo "sdram_c_$(/opt/vc/bin/vcgencmd measure_volts sdram_c)"
		echo "sdram_i_$(/opt/vc/bin/vcgencmd measure_volts sdram_i)"
		echo "sdram_p_$(/opt/vc/bin/vcgencmd measure_volts sdram_p)"
		echo -e "\n${LIGHT_BLUE}System throttling:${NOCOLOR}"
		state=$(/opt/vc/bin/vcgencmd get_throttled)
		state=${state#*=}
		echo "current_state=${state}"
		echo -n "under_voltage="
		((($state&UNDERVOLTED)!=0)) && echo -n "yes" || echo -n "no"
		((($state&HAS_UNDERVOLTED)!=0)) && echo " (yes)" || echo " (no)"
		echo -n "frequency_capped="
		((($state&CAPPED)!=0)) && echo -n "yes" || echo -n "no"
		((($state&HAS_CAPPED)!=0)) && echo " (yes)" || echo " (no)"
		echo -n "throttled="
		((($state&THROTTLED)!=0)) && echo -n "yes" || echo -n "no"
		((($state&HAS_THROTTLED)!=0)) && echo " (yes)" || echo " (no)"
		echo -n "soft_temp_limit="
		((($state&SOFT_TEMPLIMIT)!=0)) && echo -n "yes" || echo -n "no"
		((($state&HAS_SOFT_TEMPLIMIT)!=0)) && echo " (yes)" || echo " (no)"
		echo -e "\nctrl+c to exit ..."
		sleep 1.5
	done
}


resetConfig() {
	clear
	cd
	while true; do
		echo -n -e "reset retroarch configuartion? (y/n): "
		read input
		if [ "$input" == "y" ] || [ "$input" == "n" ]; then
			if [ "$input" == "y" ]; then
				echo $RS_FLAG_RST_CONF > $RS_FLAG_FILE
				echo -e "\nquit retroarch for changes to take effect\n"
				break
			else
				exit 0
			fi
		fi
	done
}


setCoreSrc() {
	clear
	cd
	curr_src=$(grep "core_updater_buildbot_cores_url" .override.cfg | cut -d'"' -f 2)
	echo -e "\nactive: $curr_src\n"
	while true; do
		read -e -p "enter new source: " src
		if [ "$src" != "" ]; then
			exc_src=$(printf '%s\n' "$src" | sed -e 's/[\/&]/\\&/g')
			sed -i -r 's/^core_updater_buildbot_cores_url = .*/core_updater_buildbot_cores_url = "'$exc_src'"/' .override.cfg
			break
		else
			echo -e "${LIGHT_RED}invalid input '$src'${NOCOLOR}\n"
		fi
	done
	echo $RS_FLAG_RESTART > $RS_FLAG_FILE
	echo -e "\nquit retroarch for changes to take effect\n"
}


killRA() {
	clear
	cd
	echo -e "${LIGHT_RED}only use this option if retroarch is not responding${NOCOLOR}\n"
	while true; do
		echo -n -e "kill retroarch process? (y/n): "
		read input
		if [ "$input" == "y" ] || [ "$input" == "n" ]; then
			if [ "$input" == "y" ]; then
				echo $RS_FLAG_KILL > $RS_FLAG_FILE
				pkill retroarch
				break
			else
				exit 0
			fi
		fi
	done
}


updateRS() {
	if [ "$EUID" -ne "0" ]; then
		echo -e "${LIGHT_RED}update-rs must be run as root${NOCOLOR}"
		exit 1
	fi
	clear
	while true; do
		echo -n -e "update retro-station? (y/n): "
		read input
		if [ "$input" == "y" ] || [ "$input" == "n" ]; then
			if [ "$input" == "y" ]; then
				cd $INSTALL_PATH
				git pull
				cd $USER
				echo $RS_FLAG_REBOOT > $RS_FLAG_FILE
				echo -e "\nquit retroarch for changes to take effect\n"
				break
			else
				exit 0
			fi
		fi
	done
}



updateOS() {
	if [ "$EUID" -ne "0" ]; then
		echo -e "${LIGHT_RED}update-os must be run as root${NOCOLOR}"
		exit 1
	fi
	clear
	while true; do
		echo -n -e "update OS? (y/n): "
		read input
		if [ "$input" == "y" ] || [ "$input" == "n" ]; then
			if [ "$input" == "y" ]; then
				pacman -Syu
				cd $USER
				echo $RS_FLAG_REBOOT > $RS_FLAG_FILE
				echo -e "\nquit retroarch for changes to take effect\n"
				break
			else
				exit 0
			fi
		fi
	done
}


printLogo() {
	printf '\n\n'$LIGHT_MAGENTA'%s'$NOCOLOR'\n' "                   __                                   __             __                            "
	printf $LIGHT_RED'%s'$NOCOLOR'\n' "                  /\\ \\__                               /\\ \\__         /\\ \\__  __                     "
	printf $LIGHT_YELLOW'%s'$NOCOLOR'\n' "        _ __    __\\ \\ ,_\\  _ __   ___              ____\\ \\ ,_\\    __  \\ \\ ,_\\/\\_\\    ___     ___     "
	printf $LIGHT_GREEN'%s'$NOCOLOR'\n' "       /\\\`'__\\/'__\`\\ \\ \\/ /\\\`'__\\/ __\`\\  _______  /',__\\\\ \\ \\/  /'__\`\\ \\ \\ \\/\\/\\ \\  / __\`\\ /' _ \`\\   "
	printf $LIGHT_CYAN'%s'$NOCOLOR'\n' "       \\ \\ \\//\\  __/\\ \\ \\_\\ \\ \\//\\ \\_\\ \\/\\______\\/\\__, \`\\\\ \\ \\_/\\ \\_\\.\\_\\ \\ \\_\\ \\ \\/\\ \\_\\ \\/\\ \\/\\ \\  "
	printf $LIGHT_BLUE'%s'$NOCOLOR'\n' "        \\ \\_\\\\ \\____\\\\ \\__\\\\ \\_\\\\ \\____/\\/______/\\/\\____/ \\ \\__\\ \\__/.\\_\\\\ \\__\\\\ \\_\\ \\____/\\ \\_\\ \\_\\ "
	printf $LIGHT_GRAY'%s'$NOCOLOR'\n\n\n' "         \\/_/ \\/____/ \\/__/ \\/_/ \\/___/           \\/___/   \\/__/\\/__/\\/_/ \\/__/ \\/_/\\/___/  \\/_/\\/_/ "
}


run() {
	clear
	printLogo
	sleep 3
	echo -e "\n${LIGHT_GREEN}starting retroarch ...${NOCOLOR}"
	#amixer -q -c 0 cset numid=1 85%
	#amixer -q -c 1 cset numid=1 85%
	cd
	exit_code=1
	while [ "$exit_code" -ne "0" ]; do
		retroarch --appendconfig=.override.cfg >> retroarch.log 2>&1
		exit_code=$?
		if [ -f $RS_FLAG_FILE ]; then
			read -r flag < $RS_FLAG_FILE
			rm $RS_FLAG_FILE
			if [ "$flag" == $RS_FLAG_RESTART ]; then
				exit_code=1
			elif [ "$flag" == $RS_FLAG_REBOOT ]; then
				systemctl reboot
			elif [ "$flag" == $RS_FLAG_RST_CONF ]; then
				cp $INSTALL_PATH/override.cfg .override.cfg
				rm .config/retroarch/retroarch.cfg
				exit_code=1
			elif [ "$flag" == $RS_FLAG_KILL ]; then
				exit_code=1
			else
				echo -e "${LIGHT_GRAY}unknown rs-flag${NOCOLOR}"
			fi
			flag=""
		fi
		if [ "$exit_code" -gt "0" ]; then
			echo -e "${LIGHT_YELLOW}restarting retroarch ...${NOCOLOR}"
			sleep 2
		fi
	done
	echo -e "${LIGHT_CYAN}retroarch quit by user${NOCOLOR}"
	echo -e "${LIGHT_BLUE}power off system ...${NOCOLOR}"
	sleep 2
	clear
	systemctl poweroff
}


printHelp() {
	echo -e "\nusage: retro-station [command]\n"
	echo "commands:"
	echo "   audio-card      select audio card"
	echo "   audio-driver    select audio driver"
	echo "   hw-mon          show hardware monitor"
	echo "   reset-config    reset retroarch configuration"
	echo "   core-source     set source for downloading cores"
	echo "   kill-ra         kill the retroarch process"
	echo "   set-firewall    enable or disable firewall (requires root privileges)"
	echo "   update-rs       update retro-station (requires root privileges)"
	echo "   update-os       update OS (requires root privileges)"
	echo -e "   -h --help       show this help\n"
}


if [[ -z "$1" ]]; then
    printHelp
else
	case "$1" in
		"install")
			installRS
			;;
		"run")
			run
			;;
		"audio-card")
			setAudioCard
			;;
		"audio-driver")
			setAudioDriver
			;;
		"hw-mon")
			hwMonitor
			;;
		"core-source")
			setCoreSrc
			;;
		"reset-config")
			resetConfig
			;;
		"set-firewall")
			setFirewall
			;;
		"kill-ra")
			killRA
			;;
		"update-rs")
			updateRS
			;;
		"update-os")
			updateOS
			;;
		"-h")
			printHelp
			;;
		"--help")
			printHelp
			;;
		*)
          echo "unknown argument: '$1'"
          exit 1
	esac
fi