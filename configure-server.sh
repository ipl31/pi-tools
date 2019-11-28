#!/bin/bash
# This script attempts to setup a PXE boot server on a raspberry pi4.
# The script accepts 3 positional arguments: 
#       - The IP address we wish to assign to the pi's ethernet interface.
#       - The broadcast address of the network, used for configuring DHCP.
#       - The DNS server on the local network.

# Set bash strict mode
set -euo pipefail

usage() {
    echo "This script must be run by a user with sudo access."
    echo "You must provide 5 arguments. Desired IP address, DHCP range start IP, DHCP range stop IP, IP of your DNS server."
    echo "usage:  $(basename "$0") IP CIDR DHCP_RANGE_START DHCP_RANGE_END DNS_IP"
    echo "example:  $(basename "$0") 192.168.2.100 24 192.168.2.101 192.168.2.200 192.168.2.1"
}

if [[ "$#" -ne 5 ]];then
    usage
fi

IP=$1
CIDR=$2
DHCP_RANGE_START=$3
DHCP_RANGE_END=$4
DNS_IP=$5
NIC="eth0"

#TODO: add dnsmasq config.
#      add raspi-config for locale setup, auto expand disk

# Setup the tftpboot directory to serve the kernel to the client.
TFTP_DIR="/tftpboot"
sudo mkdir -p "${TFTP_DIR}"
sudo chmod 777 "${TFTP_DIR}"

# Setup the base NFS directory and sub directory for the client's rootfs.
NFS_DIR="/nfs"
NFS_CLIENT_DIR="${NFS_DIR}"/client1
sudo mkdir -p "${NFS_DIR}"

#Update the OS packages
sudo apt-get -y update
sudo apt-get -y full-upgrade

PACKAGES="ssh rsync screen dnsmasq tcpdump rpi-eeprom nfs-kernel-server"
sudo apt-get -y install ${PACKAGES}
sudo systemctl enable ssh.service
sudo systemctl restart ssh

# Rsync the servers filesystem to the NFS dir.
# Exclude the NFS dir.
# Exclude the network config files for the server that force
# it to static IP. We want clients to DHCP.
# Exclude the dnsmasq config file.
sudo rsync -xa --progress --exclude "${NFS_DIR}" \
    --exclude /etc/systemd/network/10-"${NIC}".netdev \
    --exclude /etc/systemd/network/11-"${NIC}".network \
    --exclude /etc/dnsmasq.conf \
    / "${NFS_CLIENT_DIR}"

# Chroot into the new client rootfs, bind mount sysfs/dev/proc and sanitize SSH host keys.
pushd "${NFS_CLIENT_DIR}"
sudo mount --bind /dev dev
sudo mount --bind /sys sys
sudo mount --bind /proc proc
sudo chroot . rm -f /etc/ssh/ssh_host_*
sudo chroot . dpkg-reconfigure openssh-server
sudo umount dev sys proc
popd

# Config dnsmasq
DNSMASQ_TMP=$(mktemp /tmp/configure-server-dnsmasq.XXXXXXX)
cat > "${DNSMASQ_TMP}" <<-EOF
interface=${NIC}
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},12h
log-dhcp
enable-tftp
tftp-root=/tftpboot
pxe-service=0,"Raspberry Pi Boot"
EOF
sudo mv "${DNSMASQ_TMP}" /etc/dnsmasq.conf
sudo rm -f "${DNSMASQ_TMP}"
sudo chmod 644 /etc/dnsmasq.conf
sudo systemctl enable dnsmasq.service
sudo systemctl restart dnsmasq.service

# Setup networking for static IP
NETDEV_TMP=$(mktemp /tmp/configure-server-netdev.XXXXXXX)
cat > "${NETDEV_TMP}" <<-EOF
[Match]
Name=${NIC}
[Network]
DHCP=no
EOF
sudo mv "${NETDEV_TMP}" /etc/systemd/network/10-"${NIC}".netdev
sudo chmod 644 /etc/systemd/network/10-"${NIC}".netdev
sudo rm -f "${NETDEV_TMP}"

# TODO: add gateway
NETWORK_TMP=$(mktemp /tmp/configure-server-network.XXXXXXX)
cat > "${NETWORK_TMP}" <<-EOF
[Match]
Name=${NIC}

[Network]
Address=${IP}/${CIDR}
DNS=${DNS_IP}

[Route]
Gateway=
EOF
sudo mv "${NETWORK_TMP}" /etc/systemd/network/11-"${NIC}".network
sudo chmod 644 /etc/systemd/network/11-"${NIC}".network
sudo rm -f "${NETWORK_TMP}"
sudo systemctl enable systemd-networkd




# Enable/start NFS related services
sudo systemctl enable rpcbind
sudo systemctl restart rpcbind
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server
