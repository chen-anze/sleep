#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME="cros-ec-sleep-fix"
MODULE_VERSION="1.0-local"
KERNEL_VERSION="$(uname -r)"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DKMS_SOURCE_DIR="/usr/src/${MODULE_NAME}-${MODULE_VERSION}"

if [[ ${EUID} -ne 0 ]]; then
	echo "Run this script as root (for example: sudo $0)." >&2
	exit 1
fi

if [[ "$(< /sys/class/dmi/id/product_name)" != "Redrix" ]]; then
	echo "Refusing to install: this recorded workaround targets Redrix." >&2
	exit 1
fi

if ! grep -qw cros_ec_cmd_xfer /proc/kallsyms; then
	echo "Refusing to install: cros_ec_cmd_xfer is unavailable." >&2
	exit 1
fi

dnf install -y dkms gcc make "kernel-devel-${KERNEL_VERSION}"

install -d -m 0755 "${DKMS_SOURCE_DIR}"
install -m 0644 "${SOURCE_DIR}/cros_ec_sleep_kprobe.c" "${DKMS_SOURCE_DIR}/"
install -m 0644 "${SOURCE_DIR}/Makefile" "${DKMS_SOURCE_DIR}/"
install -m 0644 "${SOURCE_DIR}/dkms.conf" "${DKMS_SOURCE_DIR}/"

if dkms status -m "${MODULE_NAME}" -v "${MODULE_VERSION}" | grep -q .; then
	dkms remove -m "${MODULE_NAME}" -v "${MODULE_VERSION}" --all
fi

dkms add -m "${MODULE_NAME}" -v "${MODULE_VERSION}"
dkms build -m "${MODULE_NAME}" -v "${MODULE_VERSION}" -k "${KERNEL_VERSION}"
dkms install -m "${MODULE_NAME}" -v "${MODULE_VERSION}" -k "${KERNEL_VERSION}"

install -m 0644 "${SOURCE_DIR}/cros-ec-sleep-fix.modules-load.conf" \
	/etc/modules-load.d/cros-ec-sleep-fix.conf
install -m 0644 "${SOURCE_DIR}/cros-ec-sleep-fix.modprobe.conf" \
	/etc/modprobe.d/cros-ec-sleep-fix.conf

# Install the S0ix blocker mitigations documented in firmware issue #851.
"${SOURCE_DIR}/install-power-tweaks.sh"

depmod -a "${KERNEL_VERSION}"
modprobe cros_ec_proto
modprobe cros_ec_sleep_kprobe

test -d /sys/module/cros_ec_sleep_kprobe
modinfo cros_ec_sleep_kprobe
dkms status -m "${MODULE_NAME}" -v "${MODULE_VERSION}"
journalctl -b -k --no-pager | grep 'cros_ec_sleep_kprobe: registered' | tail -1

echo "Chrome EC sleep-timeout workaround installed and loaded."
