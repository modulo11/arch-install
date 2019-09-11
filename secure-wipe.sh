#!/bin/bash

echo "If you see any errors, try to unfreeze your SSD, e.g.:"
echo "systemctl suspend"

if (( UID != 0 )); then
    echo "run as root!"
	exit
fi

hdparm --user-master u --security-set-pass PasSWorD /dev/sda
hdparm --user-master u --security-erase PasSWorD /dev/sda
