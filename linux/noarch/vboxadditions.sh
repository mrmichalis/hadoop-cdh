#!/usr/bin/env bash

VBOX_VERSION="$(wget -q -O - http://download.virtualbox.org/virtualbox/LATEST.TXT)"
echo "* Downloading virtualbox Linux Additions version $VBOX_VERSION..."
# wget -q "http://download.virtualbox.org/virtualbox/$VBOX_VERSION/VBoxGuestAdditions_$VBOX_VERSION.iso" -O "/root/CDH/VBoxGuestAdditions_$VBOX_VERSION.iso"
curl -L -O "http://download.virtualbox.org/virtualbox/$VBOX_VERSION/VBoxGuestAdditions_$VBOX_VERSION.iso"

mount -o loop "VBoxGuestAdditions_$VBOX_VERSION.iso" /mnt
sh /mnt/VBoxLinuxAdditions.run --nox11
umount /mnt

echo "rm VBoxGuestAdditions_$VBOX_VERSION.iso"
