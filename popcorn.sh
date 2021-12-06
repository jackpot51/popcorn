#!/usr/bin/env bash

# Add Microsoft keys
MICROSOFT="0"

# Root device UUID
ROOT_UUID="$(findmnt --noheadings --output UUID --mountpoint /)"

# Linux command line
CMDLINE="root=UUID=${ROOT_UUID} ro quiet loglevel=0 systemd.show_status=false splash lockdown=integrity"

set -ex

if [ ! -f /etc/initramfs-tools/hooks/tpm2-totp ]
then
	git submodule update --init tpm2-totp
	pushd tpm2-totp

	sudo apt -y install \
		autoconf \
		autoconf-archive \
		automake \
		build-essential \
		doxygen \
		gcc \
		iproute2 \
		liboath-dev \
		libplymouth-dev \
		libqrencode-dev \
		libtool \
		libtss2-dev \
		m4 \
		pandoc \
		pkg-config \
		plymouth
	./bootstrap
	./configure --sysconfdir=/etc
	make
	sudo make install
	sudo ldconfig
	sudo update-initramfs -u
	#TODO: sudo tpm2-totp init -p 0,2,7

	popd
fi

# Create keys
if [ ! -d secret ]
then
	sudo apt-get install -y efitools

	rm -rf secret.partial
	mkdir -p secret.partial
	pushd secret.partial

	# Owner GUID
	uuidgen --random > GUID.txt

	# Platform key
	openssl req -newkey rsa:4096 -nodes -keyout PK.key -new -x509 -sha256 -days 3650 -subj "/CN=Owner PK/" -out PK.crt
	openssl x509 -outform DER -in PK.crt -out PK.cer
	cert-to-efi-sig-list -g "$(< GUID.txt)" PK.crt PK.esl
	sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt PK PK.esl PK.auth

	# Empty file for removing platform key
	sign-efi-sig-list -g "$(< GUID.txt)" -c PK.crt -k PK.key PK /dev/null noPK.auth

	# Key Exchange key
	openssl req -newkey rsa:4096 -nodes -keyout KEK.key -new -x509 -sha256 -days 3650 -subj "/CN=Owner KEK/" -out KEK.crt
	openssl x509 -outform DER -in KEK.crt -out KEK.cer
	cert-to-efi-sig-list -g "$(< GUID.txt)" KEK.crt KEK.esl
	sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt KEK KEK.esl KEK.auth

	# Signature database key:
	openssl req -newkey rsa:4096 -nodes -keyout db.key -new -x509 -sha256 -days 3650 -subj "/CN=Owner DB/" -out db.crt
	openssl x509 -outform DER -in db.crt -out db.cer
	cert-to-efi-sig-list -g "$(< GUID.txt)" db.crt db.esl
	sign-efi-sig-list -g "$(< GUID.txt)" -k KEK.key -c KEK.crt db db.esl db.auth

	popd
	mv secret.partial secret
fi

# Recreate build directory
rm -rf build
mkdir -p build

# Create unified Linux EFI executable
echo "${CMDLINE}" > "build/cmdline"
sudo objcopy \
	--add-section .osrel="/usr/lib/os-release" --change-section-vma .osrel=0x20000 \
    --add-section .cmdline="build/cmdline" --change-section-vma .cmdline=0x30000 \
    --add-section .linux="/boot/vmlinuz" --change-section-vma .linux=0x2000000 \
    --add-section .initrd="/boot/initrd.img" --change-section-vma .initrd=0x3000000 \
    "/usr/lib/systemd/boot/efi/linuxx64.efi.stub" "build/linux.efi"

# Sign Linux EFI executable
sbsign --key secret/db.key --cert secret/db.crt --output build/linux-signed.efi build/linux.efi

# Sign systemd-boot EFI executable
sbsign --key secret/db.key --cert secret/db.crt --output build/systemd-boot-signed.efi /usr/lib/systemd/boot/efi/systemd-bootx64.efi

# Copy signed Linux EFI executable to EFI partition
sudo mkdir -pv /boot/efi/EFI/Linux
sudo cp -v build/linux-signed.efi "/boot/efi/EFI/Linux/Pop_OS-${ROOT_UUID}.efi"

# Copy signed systemd-boot EFI executable to EFI partition
sudo mkdir -pv /boot/efi/EFI/BOOT
sudo cp -v build/systemd-boot-signed.efi /boot/efi/EFI/BOOT/BOOTX64.efi

# Set keys if in setup mode
if sudo bootctl status | grep 'Setup Mode: setup'
then
	# Add key exchange key
	sudo efi-updatevar -e -f secret/KEK.esl KEK

	# Add db key
	sudo efi-updatevar -e -f secret/db.esl db

	# Optionally add Microsoft db keys
	if [ "${MICROSOFT}" == "1" ]
	then
		sudo efi-updatevar -a -e -f secret/MS_db.esl db
	fi

	# Add platform key, which will probably lock other variables
	sudo efi-updatevar -f secret/PK.auth PK
fi

# Initiate tpm2-totp if not already set up
if ! sudo tpm2-totp show &>/dev/null
then
	sudo tpm2-totp init -l "$(hostname) TPM2-TOTP" -p 0,2,7
fi

echo "popcorn setup complete - rerun on firmware or kernel updates"
