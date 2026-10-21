#!/bin/bash
# Windows side: whenever the phone's iOS USB Ethernet (1209:0001) shows up, attach it to WSL
# with usbipd (bound automatically by the AutoBind policy). Runs forever.
U="/c/Program Files/usbipd-win/usbipd.exe"
while :; do
	line=$("$U" list 2>/dev/null | grep -i '1209:0001')
	if [ -n "$line" ] && ! echo "$line" | grep -q 'Attached'; then
		busid=$(echo "$line" | awk '{print $1}')
		echo "[$(date +%H:%M:%S)] attaching $busid to WSL"
		"$U" attach --wsl --busid "$busid" 2>&1 | tail -2
	fi
	sleep 3
done
