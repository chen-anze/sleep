#!/usr/bin/env bash
set -euo pipefail

echo "Kernel: $(uname -r)"
echo "Sleep modes: $(< /sys/power/mem_sleep)"
echo "DMI product: $(< /sys/class/dmi/id/product_name)"
echo "Firmware: $(< /sys/class/dmi/id/bios_version)"

echo "--- DKMS ---"
dkms status -m cros-ec-sleep-fix -v 1.0-local

echo "--- Module ---"
test -d /sys/module/cros_ec_sleep_kprobe
modinfo cros_ec_sleep_kprobe | grep -E '^(filename|version|description|vermagic):'

echo "--- S0ix power settings ---"
test "$(< /sys/module/iwlwifi/parameters/power_save)" = Y
echo "iwlwifi power_save=Y"
for file in \
	/etc/modprobe.d/redrix-iwlwifi-s0ix.conf \
	/etc/environment.d/50-redrix-no-ddcutil.conf \
	/etc/wireplumber/wireplumber.conf.d/51-redrix-alsa-suspend.conf; do
	test -r "${file}"
	echo "present: ${file}"
done

echo "--- Current-boot workaround messages ---"
journalctl -b -k --no-pager | grep 'cros_ec_sleep_kprobe'

echo "--- Current-boot EC timeout warnings ---"
journalctl -b -k --no-pager | grep 'EC detected sleep transition timeout' || true
