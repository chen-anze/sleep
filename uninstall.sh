#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME="cros-ec-sleep-fix"
MODULE_VERSION="1.0-local"
DKMS_SOURCE_DIR="/usr/src/${MODULE_NAME}-${MODULE_VERSION}"

if [[ ${EUID} -ne 0 ]]; then
	echo "Run this script as root (for example: sudo $0)." >&2
	exit 1
fi

modprobe -r cros_ec_sleep_kprobe 2>/dev/null || true
dkms remove -m "${MODULE_NAME}" -v "${MODULE_VERSION}" --all 2>/dev/null || true
rm -f /etc/modules-load.d/cros-ec-sleep-fix.conf
rm -f /etc/modprobe.d/cros-ec-sleep-fix.conf
rm -f /etc/modprobe.d/redrix-iwlwifi-s0ix.conf
rm -f /etc/environment.d/50-redrix-no-ddcutil.conf
rm -f /etc/wireplumber/wireplumber.conf.d/51-redrix-alsa-suspend.conf
rm -rf -- "${DKMS_SOURCE_DIR}"
depmod -a

echo "Chrome EC sleep-timeout workaround removed. Reboot recommended."
