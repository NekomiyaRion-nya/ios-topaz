#!/bin/bash
# Load the USB/IP client + CDC-ECM modules shipped with the WSL kernel.
modprobe -a vhci-hcd usbnet cdc_ether
grep -E '^(usbcore|usbip_core|vhci_hcd|usbnet|cdc_ether) ' /proc/modules | awk '{print $1}'
