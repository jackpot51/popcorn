#!/usr/bin/env bash

# Add Microsoft db if set
MICROSOFT_DB="$(realpath data/MS_db.esl)"

# Root device UUID
ROOT_UUID="$(findmnt --noheadings --output UUID --mountpoint /)"

# Linux command line
CMDLINE="root=UUID=${ROOT_UUID} ro quiet loglevel=0 systemd.show_status=false splash lockdown=integrity"

if [ "${EUID}" != "0" ]
then
    exec sudo "$0" "$@"
fi

set -ex

mkdir -p /etc/popcorn
cd /etc/popcorn

# Create keys
if [ ! -d secret ]
then
	apt-get install -y efitools

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

# Copy DB cert and key to kernelstub path
cp -v secret/db.crt /etc/kernelstub/db.crt
cp -v secret/db.key /etc/kernelstub/db.key

# Run kernelstub in unified kernel executable mode
kernelstub --unified --verbose

# Set keys if in setup mode
if bootctl status | grep 'Setup Mode: setup'
then
	# Add db key
	efi-updatevar -e -f secret/db.esl db

	# Optionally add Microsoft db keys
	if [ -n "${MICROSOFT_DB}" ]
	then
		efi-updatevar -a -e -f "${MICROSOFT_DB}" db
	fi

	# Add key exchange key, which may lock db
	efi-updatevar -e -f secret/KEK.esl KEK

	# Add platform key, which will probably lock other variables
	efi-updatevar -f secret/PK.auth PK
fi

echo "popcorn setup complete - rerun on firmware or kernel updates"
