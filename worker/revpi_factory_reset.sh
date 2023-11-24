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

ssh-keygen -f "/root/.ssh/known_hosts" -R "$SSH_HOST_RPI"
sshpass -p "$DEFAULT_PASS" ssh-copy-id -o "StrictHostKeyChecking=no" -f -i /sshkey/lava_worker_ed25519.pub "$DEFAULT_USER"@"$SSH_HOST_RPI"
sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$DEFAULT_USER"@"$SSH_HOST_RPI" "sudo cp -r /home/pi/.ssh /root"
sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$DEFAULT_USER"@"$SSH_HOST_RPI" "sudo chown -R root: /root/.ssh"
sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no "$DEFAULT_USER"@"$SSH_HOST_RPI" "sudo /usr/sbin/revpi-factory-reset \"$DEVICE_TYPE\" \"$DEVICE_SERIAL\" \"$DEVICE_MAC\" && sudo reboot"

exit 0
