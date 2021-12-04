#!/usr/bin/env bash

# Add Microsoft keys
MICROSOFT="1"

# Root device UUID
ROOT_UUID="$(findmnt --noheadings --output UUID --mountpoint /)"

set -ex

# Create secretes
if [ ! -d secret ]
then
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

	# Create sbkeysync keystore
	mkdir -p keystore/{PK,KEK,db}
	cp PK.auth keystore/PK
	cp KEK.auth keystore/KEK
	cp db.auth keystore/db

	popd
	mv secret.partial secret
fi

# Optionally add Microsoft keys
if [ "${MICROSOFT}" == "1" ]
then
	sign-efi-sig-list -a -g 77fa9abd-0359-4d32-bd60-28f4e78f784b -k secret/KEK.key -c secret/KEK.crt db data/MS_db.esl secret/keystore/db/MS_db.auth
else
	rm -f secret/keystore/db/MS_db.auth
fi

# Recreate build directory
rm -rf build
mkdir -p build

# Create unified Linux EFI executable
echo "root=UUID=${ROOT_UUID} ro quiet loglevel=0 systemd.show_status=false splash" > "build/cmdline"
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

# Sync secure boot keys: dry run for verification
sbkeysync --keystore secret/keystore --verbose --dry-run
sbkeysync --keystore secret/keystore --pk --verbose --dry-run

# Sync secure boot keys
sudo sbkeysync --keystore secret/keystore --verbose
sudo sbkeysync --keystore secret/keystore --pk --verbose

# Copy signed Linux EFI executable to EFI partition
sudo mkdir -pv /boot/efi/EFI/Linux
sudo cp -v build/linux-signed.efi "/boot/efi/EFI/Linux/Pop_OS-${ROOT_UUID}"

# Copy signed systemd-boot EFI executable to EFI partition
sudo mkdir -pv /boot/efi/EFI/BOOT
sudo cp -v build/systemd-boot-signed.efi /boot/efi/EFI/BOOT/BOOTX64.efi
