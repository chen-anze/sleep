# Redrix Linux S0ix suspend workaround

This directory is a reproducible, reversible workaround for the Chrome EC
suspend problem reported in
[MrChromebox/firmware#851](https://github.com/MrChromebox/firmware/issues/851).
It was built and validated on:

- Google Redrix rev3
- Fedora Linux 44 KDE Plasma Desktop Edition
- Linux `7.2.5-200.fc44.x86_64`
- MrChromebox firmware `2606.1`

The implementation record, evidence, decisions, and test history are in
[`RECORD.md`](RECORD.md).

## What it changes

The workaround has two layers:

1. `cros_ec_sleep_kprobe` intercepts version 1 Chrome EC suspend events and
   replaces the zero-millisecond EC watchdog timeout with `0xffff` (infinite).
   This stops the EC from waking or resetting Linux during a valid S0ix
   transition while retaining normal EC communication.
2. Three configuration files remove locally observed or issue-documented S0ix
   blockers: Intel Wi-Fi is allowed to power down, KDE PowerDevil DDC polling
   is disabled, and idle ALSA nodes are explicitly suspended by WirePlumber.

This does not flash firmware, blacklist `cros_ec_lpcs`, disable wake devices,
or change the selected Linux sleep mode.

## Install

Review the source and scripts first, then run:

```bash
cd /path/to/this/repository
sudo ./sleep/install.sh
sudo reboot
```

The installer refuses to run unless DMI identifies the machine as `Redrix` and
the target kernel symbol exists. It installs the matching Fedora build tools
and kernel headers, registers the module with DKMS, configures automatic module
loading, and installs the three power settings.

Secure Boot was disabled on the validated machine. With Secure Boot enabled,
the DKMS signing certificate must be enrolled before the module can load.

## Verify after every reboot or kernel update

```bash
./sleep/verify.sh
```

Expected essentials:

- DKMS reports `cros-ec-sleep-fix/1.0-local` installed for the running kernel.
- `/sys/module/cros_ec_sleep_kprobe` exists.
- The boot journal says the kprobe registered on `cros_ec_cmd_xfer`.
- `/sys/module/iwlwifi/parameters/power_save` contains `Y`.

## Test suspend stability

```bash
./sleep/test-suspend.sh
```

Leave the machine asleep for at least 60 seconds. A pass requires the kprobe
message, suspend entry and exit, and no new EC transition-timeout warning.

## Test S0ix residency

```bash
./sleep/test-s0ix.sh
```

Leave the machine asleep for at least 120 seconds. A positive platform
low-power-idle counter delta proves S0ix entry. The percentage is useful only
for a sufficiently long test; short tests prove entry but are not graded for
residency efficiency. Each test saves a timestamped log in this directory.

The power LED is not used as evidence because its behavior depends on firmware
and EC policy.

## Roll back

```bash
sudo ./sleep/uninstall.sh
sudo reboot
```

This removes the DKMS module, boot-load configuration, and all three power
settings created by this bundle. It does not remove the Fedora compiler, DKMS,
or kernel-header packages because they may be used by other software.

## Maintenance and upstream transition

DKMS should rebuild the module for new Fedora kernels. Always run `verify.sh`
after a kernel update; a successful compilation does not guarantee that an
internal kprobe target remains compatible.

This is a temporary out-of-tree kernel workaround. When MrChromebox releases
and documents an EC-firmware fix for this timeout, uninstall this workaround,
apply the firmware update according to its official instructions, reboot, and
repeat both suspend tests without the module.

## File inventory

- `LICENSE` — upstream GPL license retained for redistribution.
- `CHECKSUMS.sha256` — integrity manifest for every documented artifact and
  captured test log in this directory.
- `cros_ec_sleep_kprobe.c` — kernel module.
- `Makefile`, `dkms.conf` — external-module and DKMS build metadata.
- `cros-ec-sleep-fix.*.conf` — module loading and dependency order.
- `iwlwifi-s0ix.conf` — Intel Wi-Fi power-saving option.
- `50-no-ddcutil.conf` — PowerDevil DDC polling opt-out.
- `51-alsa-suspend.conf` — WirePlumber ALSA idle policy.
- `install.sh`, `install-power-tweaks.sh` — deployment scripts.
- `verify.sh` — non-mutating state checks.
- `test-suspend.sh`, `test-s0ix.sh` — functional tests and log capture.
- `uninstall.sh` — rollback.
- `RECORD.md` — system-specific investigation and results.
- `suspend-test-*.log`, `s0ix-test-*.log` — captured test evidence.
