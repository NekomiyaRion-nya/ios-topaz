#!/bin/bash
# WSL: ask iOS (USB Ethernet 192.168.7.2) to flush its log and reboot into fastboot (kernel 0158/0159).
for i in 1 2 3; do printf 'SWEET-FASTBOOT' > /dev/udp/192.168.7.2/5141; sleep 1; done
echo sent
