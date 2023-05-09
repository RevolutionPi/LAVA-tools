#!/usr/bin/env bash

SSH_HOST_RPI=$1
DEVICE_TYPE=$2
DEVICE_SERIAL=$3
DEVICE_MAC=$4

DEFAULT_USER=pi
DEFAULT_PASS=raspberry

echo "$SSH_HOST_RPI"
echo "$DEVICE_TYPE"
echo "$DEVICE_SERIAL"
echo "$DEVICE_MAC"

# wait for the device to fully reboot
while ! ping -c 1 "$SSH_HOST_RPI" > /dev/null 2>&1; do 
	sleep 1; 
done

# let us wait for another 2 seconds
sleep 2

# now do the factory reset on the DuT and reboot it afterwards
cat >/tmp/lava-key.pub <<EOX
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDTBh7TFMbVgVDALMMg4VWRO/lnlxy0h4SLlmBxo11PR Lava worker to DuT key
EOX

sshpass -p "$DEFAULT_PASS" ssh-copy-id -i /tmp/lava-key.pub "$DEFAULT_USER"@"$SSH_HOST_RPI"
sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$DEFAULT_USER"@"$SSH_HOST_RPI" /usr/sbin/revpi-factory-reset "$DEVICE_TYPE" "$DEVICE_SERIAL" "$DEVICE_MAC" && sudo reboot

exit 0

