#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${EUID} -ne 0 ]]; then
	echo "Run this script as root (for example: sudo $0)." >&2
	exit 1
fi

if [[ "$(< /sys/class/dmi/id/product_name)" != "Redrix" ]]; then
	echo "Refusing to install: these recorded settings target Redrix." >&2
	exit 1
fi

install -d -m 0755 /etc/environment.d
install -d -m 0755 /etc/wireplumber/wireplumber.conf.d
install -m 0644 "${SOURCE_DIR}/iwlwifi-s0ix.conf" \
	/etc/modprobe.d/redrix-iwlwifi-s0ix.conf
install -m 0644 "${SOURCE_DIR}/50-no-ddcutil.conf" \
	/etc/environment.d/50-redrix-no-ddcutil.conf
install -m 0644 "${SOURCE_DIR}/51-alsa-suspend.conf" \
	/etc/wireplumber/wireplumber.conf.d/51-redrix-alsa-suspend.conf

restorecon -RF \
	/etc/modprobe.d/redrix-iwlwifi-s0ix.conf \
	/etc/environment.d/50-redrix-no-ddcutil.conf \
	/etc/wireplumber/wireplumber.conf.d/51-redrix-alsa-suspend.conf \
	2>/dev/null || true

echo "Installed Redrix S0ix power settings:"
echo "  /etc/modprobe.d/redrix-iwlwifi-s0ix.conf"
echo "  /etc/environment.d/50-redrix-no-ddcutil.conf"
echo "  /etc/wireplumber/wireplumber.conf.d/51-redrix-alsa-suspend.conf"
echo
echo "Reboot is required before retesting S0ix residency."

