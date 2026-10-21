#!/bin/bash
# WSL (root) side of the phone's USB Ethernet (kernel sweetusb=2, sweet patches 0075-0077 + spes 0148-0150).
# Windows: usbipd attaches the phone (1209:0001) to WSL (tools/usb-attach.sh keeps that going).
# Here: wait for the CDC-ECM link (host MAC 02:00:5e:77:ee:01), give it 192.168.7.1/24
# (the phone is 192.168.7.2) and append the UDP/5140 live console to logs/live.txt,
# re-arming after every phone reboot.
LOG=/mnt/c/Users/matsu/Documents/hackinOS/logs/live.txt
MAC=02:00:5e:77:ee:01
bash /mnt/c/Users/matsu/Documents/hackinOS/tools/load-usbnet-ko.sh >/dev/null
python3 -u - "$LOG" <<'EOF' &
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 5140))
with open(sys.argv[1], 'ab', buffering=0) as f:
    while True:
        data, _ = s.recvfrom(65535)
        f.write(data)
EOF
while :; do
	ifname=$(ip -o link | grep -i "$MAC" | awk -F': ' '{print $2}' | cut -d@ -f1)
	if [ -n "$ifname" ] && ! ip -o addr show dev "$ifname" | grep -q 192.168.7.1; then
		ip addr replace 192.168.7.1/24 dev "$ifname"
		ip link set "$ifname" up
		echo "[$(date +%H:%M:%S)] $ifname up: 192.168.7.1 <-> phone 192.168.7.2" | tee -a "$LOG"
	fi
	sleep 1
done
