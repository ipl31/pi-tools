#!/bin/bash
#TODO - do some bash linting on this script
set -euo pipefail

echo "Installing deps"
#sudo apt-get install -y qemu-user-static debootstrap
sudo apt-get update -y
sudo apt-get install -y debootstrap

CHROOT_DIR=$(mktemp -d -t ci-XXXXXXXXXX)
echo "Created CHROOT dir: ${CHROOT_DIR}"

DEBOOTSTRAP_CMD="sudo debootstrap --verbose --no-check-gpg --foreign --arch=armhf buster ${CHROOT_DIR} http://archive.raspbian.org/raspbian"
echo "Running debootstrap command: ${DEBOOTSTRAP_CMD}"
eval "${DEBOOTSTRAP_CMD}"

# echo "Copying qemu-arm-static to ${CHROOT_DIR}/usr/bin"
# cp /usr/bin/qemu-arm-static "${CHROOT_DIR}/usr/bin"

echo "Running debootstrap second stage in ${CHROOT_DIR}"
sudo chroot "${CHROOT_DIR}" /bin/bash -c 'DEBIAN_FRONTEND=noninteractive; DEBCONF_NONINTERACTIVE_SEEN=true; /debootstrap/debootstrap --verbose --second-stage'

echo "Cleaning apt cache in ${CHROOT_DIR}"
sudo chroot "${CHROOT_DIR}" apt-get clean

#cp ./configure-server.sh "${CHROOT_DIR}"/usr/bin/
#sudo chmod +x "${CHROOT_DIR}"/usr/bin/configure-server.sh

echo "Taring up debootstrap build in ${CHROOT_DIR}"
tar -czvf raspian-image.tgz -C "${CHROOT_DIR}" ./

echo "Cleaning up"
rm --preserve-root -rf "${CHROOT_DIR}"