#!/usr/bin/env bash

SSH_HOST_RPI=$1
DEVICE_TYPE=$2
DEVICE_SERIAL=$3
DEVICE_MAC=$4

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
ssh -i /sshkey/lava_worker_ed25519 -o PasswordAuthentication=no -o StrictHostKeyChecking=no root@"$SSH_HOST_RPI" /usr/sbin/revpi-factory-reset "$DEVICE_TYPE" "$DEVICE_SERIAL" "$DEVICE_MAC"
ssh -i /sshkey/lava_worker_ed25519 -o PasswordAuthentication=no -o StrictHostKeyChecking=no root@"$SSH_HOST_RPI" reboot

exit 0

