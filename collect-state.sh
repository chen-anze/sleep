#!/usr/bin/env bash
set -euo pipefail

echo "Collected: $(date --iso-8601=seconds)"
echo "Kernel: $(uname -r)"
echo "OS: $(. /etc/os-release; echo "${PRETTY_NAME}")"
echo "Product: $(< /sys/class/dmi/id/product_name) $(< /sys/class/dmi/id/product_version)"
echo "Firmware: $(< /sys/class/dmi/id/bios_version) $(< /sys/class/dmi/id/bios_date)"
echo "Sleep modes: $(< /sys/power/mem_sleep)"
echo "Platform S0ix residency: $(< /sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us) us"
echo "Wi-Fi power saving: $(< /sys/module/iwlwifi/parameters/power_save)"
echo
echo "--- DKMS ---"
dkms status -m cros-ec-sleep-fix -v 1.0-local || true
echo "--- Module ---"
lsmod | grep '^cros_ec_sleep_kprobe\b' || true
modinfo cros_ec_sleep_kprobe 2>/dev/null | grep -E \
	'^(filename|description|vermagic|signer|sig_hashalgo):' || true
echo "--- Configuration ---"
for file in \
	/etc/modules-load.d/cros-ec-sleep-fix.conf \
	/etc/modprobe.d/cros-ec-sleep-fix.conf \
	/etc/modprobe.d/redrix-iwlwifi-s0ix.conf \
	/etc/environment.d/50-redrix-no-ddcutil.conf \
	/etc/wireplumber/wireplumber.conf.d/51-redrix-alsa-suspend.conf; do
	if [[ -r ${file} ]]; then
		echo "### ${file}"
		cat "${file}"
	else
		echo "MISSING: ${file}"
	fi
done
echo "--- Current-boot suspend evidence ---"
journalctl -b -k --no-pager | grep -E \
	'PM: suspend (entry|exit)|cros_ec_sleep_kprobe|EC detected sleep transition timeout' \
	|| true

