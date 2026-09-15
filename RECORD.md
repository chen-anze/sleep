# Redrix suspend workaround record

Date: 2026-09-14  
Machine: Google Redrix rev3  
Operating system: Fedora Linux 44 KDE Plasma Desktop Edition  
Running kernel: `7.2.5-200.fc44.x86_64`  
Firmware: `MrChromebox-2606.1` (2026-07-14)

## Purpose

Install a temporary, reversible workaround for the Chrome EC suspend timeout
reported in [MrChromebox/firmware#851](https://github.com/MrChromebox/firmware/issues/851).

The Linux `cros_ec` driver sends a version 1 `HOST_SLEEP_EVENT` with its default
timeout value of zero. On the affected EC firmware this arms a short sleep
transition watchdog. The workaround uses a kprobe on `cros_ec_cmd_xfer` to
replace the timeout with `0xffff` (`EC_HOST_SLEEP_TIMEOUT_INFINITE`) immediately
before the command is sent to the EC.

## Evidence collected before installation

- `/sys/power/mem_sleep`: `[s2idle] deep` (`s2idle` selected).
- `cros_ec_lpcs`, `cros_ec`, and `cros_ec_proto` were loaded.
- The boot journal recorded `EC detected sleep transition timeout` and a warning
  in `cros_ec_sleep_event` during a failed suspend.
- The kernel configuration has `CONFIG_KPROBES=y` and `CONFIG_MODULES=y`.
- `cros_ec_cmd_xfer` exists in `/proc/kallsyms` in `cros_ec_proto`.
- Secure Boot is disabled and kernel lockdown is `none`.
- Fedora's exact matching `kernel-devel-7.2.5-200.fc44.x86_64` package is
  available.
- The simpler debugfs method is unavailable: Fedora did not enable
  `CONFIG_CROS_EC_DEBUGFS`, and `cros_ec_debugfs` is not shipped as a module.

## Source and local changes

The module is based on
[`5fff/linux-chromebook-sleep-dkms`](https://github.com/5fff/linux-chromebook-sleep-dkms),
commit `2e0b782eec92da887b44cd528b61b6e658731d60` (2026-09-01).

Local changes:

- Validate the outgoing payload length before accessing it.
- Return the actual `register_kprobe()` error code.
- Use internally consistent DKMS name `cros-ec-sleep-fix` and version
  `1.0-local`.
- Do not apply the upstream RPM's unrelated Wi-Fi power-saving or KDE/DDC
  configuration changes.
- Abort installation on a non-Redrix system or when the target kernel symbol is
  absent.

## Files

- `cros_ec_sleep_kprobe.c`: kernel-module source.
- `Makefile`: external kernel-module build instructions.
- `dkms.conf`: DKMS metadata and automatic rebuild configuration.
- `cros-ec-sleep-fix.modules-load.conf`: load the module during boot.
- `cros-ec-sleep-fix.modprobe.conf`: ensure `cros_ec_proto` loads first.
- `install.sh`: dependency installation, DKMS deployment, load, and checks.
- `verify.sh`: non-mutating installation and journal checks.
- `test-suspend.sh`: suspends once, captures the relevant post-resume journal,
  and writes a timestamped test log beside this record.
- `test-s0ix.sh`: measures the Intel platform low-power-idle residency counter
  across a suspend and calculates the percentage of the interval spent in S0ix.
- `iwlwifi-s0ix.conf`: enables Intel Wi-Fi power saving.
- `50-no-ddcutil.conf`: prevents KDE PowerDevil from loading/polling DDCUtil.
- `51-alsa-suspend.conf`: explicitly suspends idle WirePlumber ALSA nodes.
- `install-power-tweaks.sh`: installs the three S0ix blocker mitigations.
- `uninstall.sh`: complete rollback procedure.
- `README.md`: user-facing installation, validation, maintenance, and rollback
  guide suitable as the repository entry point.
- `collect-state.sh`: captures a shareable snapshot of relevant system state,
  configuration, module metadata, and current-boot suspend evidence.
- `LICENSE`: license text preserved verbatim from upstream commit
  `2e0b782eec92da887b44cd528b61b6e658731d60` for future redistribution.
- `CHECKSUMS.sha256`: final SHA-256 integrity manifest for the reproducible
  bundle and captured evidence (excluding the manifest itself).

## System changes made by `install.sh`

The installer will install Fedora build dependencies, copy the three build files
to `/usr/src/cros-ec-sleep-fix-1.0-local`, register/build/install the module with
DKMS, create the two configuration files under `/etc`, run `depmod`, and load
`cros_ec_sleep_kprobe` immediately.

No firmware is flashed. `cros_ec_lpcs` remains loaded, so normal EC-backed
features remain available. The workaround modifies only matching suspend-event
messages while its module is loaded.

## Installation and validation result

The first automated attempt reached the local `sudo` password prompt and was
cancelled before making system changes. The machine owner then ran
`sudo ./sleep/install.sh` interactively.

Installation succeeded on `7.2.5-200.fc44.x86_64`:

- DKMS built and installed `cros-ec-sleep-fix/1.0-local` for `x86_64`.
- The module was installed at
  `/lib/modules/7.2.5-200.fc44.x86_64/extra/cros_ec_sleep_kprobe.ko.xz`.
- Its vermagic exactly matches the running kernel.
- It was signed with the locally generated DKMS module-signing key.
- `cros_ec_sleep_kprobe` loaded and logged
  `registered on cros_ec_cmd_xfer` at 19:28:42.
- Persistent module-load and soft-dependency configuration files exist under
  `/etc/modules-load.d` and `/etc/modprobe.d`.

DKMS warned that its `CLEAN` directive is deprecated. This is non-fatal; the
build and installation completed. The running kernel also reports the expected
out-of-tree-module taint and says the locally generated signing key is not in
its trusted keyring. Secure Boot and kernel lockdown are disabled on this
machine, so that did not prevent module loading. If Secure Boot is enabled in
the future, its DKMS MOK must first be enrolled.

The pre-installation timeout warning at 19:16:25 remains in the current boot
journal as historical evidence.

Test command:

```bash
./sleep/test-suspend.sh
```

### Functional test: PASS

The test ran from 19:30:40 through 19:31:13 on 2026-09-14. Relevant kernel
events were:

```text
Sep 14 19:30:41 dragonfly kernel: PM: suspend entry (s2idle)
Sep 14 19:31:12 dragonfly kernel: cros_ec_sleep_kprobe: set HOST_SLEEP_EVENT timeout to infinite
Sep 14 19:31:12 dragonfly kernel: PM: suspend exit
```

The system remained suspended for approximately 31 seconds, crossing the
former EC watchdog's 10/20/30-second escalation window. It resumed normally,
the kprobe confirmed that it rewrote the outgoing timeout, and no new
`EC detected sleep transition timeout` warning appeared. After resume, the
module remained loaded and DKMS still reported it installed for the running
kernel.

The complete captured output is in `suspend-test-20260914-193040.log`.

Status: **implemented and functionally validated**. Automatic loading after a
full reboot can be checked separately with `./sleep/verify.sh`.

### Power LED observation

The power LED remained illuminated during the functional test. This does not
invalidate the EC-timeout fix: the journal proves that userspace and devices
entered the kernel's `s2idle` suspend path, the outgoing EC timeout was
rewritten, the old watchdog window was crossed, and the system resumed without
another EC timeout.

It may indicate that the platform remained in a shallower s2idle hardware
substate instead of attaining its deepest S0ix residency. Local follow-up checks
found Intel Wi-Fi power saving disabled (`iwlwifi power_save=N`) and found KDE
PowerDevil plus `ddcutil` installed. These are known candidates for preventing
deep S0ix residency. The resume journal also contains
`intel_ipu6.psys.40: Failed to get runtime PM`; this is recorded as a possible
secondary power-management issue, not yet established as the cause of the LED
state. No extra power-tuning changes have been applied.

The authoritative test for S0ix entry is a positive change in
`/sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us` across a
suspend. Run `./sleep/test-s0ix.sh`, leave the machine suspended for at least
two minutes, and then wake it. Any positive delta proves S0ix entry; a ratio
above 80% indicates that most of the test interval was spent there. The script
does not distinguish individual S0ix substates such as S0i2 versus S0i3.

### First S0ix measurement correction

The initial `test-s0ix.sh` output incorrectly reported a 0.18-second suspend
and zero residency. It read wall time and PMC telemetry immediately after
`systemctl suspend` returned, before resume timekeeping and telemetry had
refreshed. The kernel journal is authoritative for the interval and shows:

```text
Sep 14 19:34:55 dragonfly kernel: PM: suspend entry (s2idle)
Sep 14 19:37:44 dragonfly kernel: cros_ec_sleep_kprobe: set HOST_SLEEP_EVENT timeout to infinite
Sep 14 19:37:44 dragonfly kernel: PM: suspend exit
```

The system actually remained suspended for approximately 169 seconds. The
platform counter subsequently increased from 76,204,587 us to 80,039,648 us,
a gain of 3,835,061 us (approximately 2.3% of the suspend interval). This
proves S0ix entry but shows very low residency. `test-s0ix.sh` now waits five
seconds after resume before reading clocks and telemetry.

### Additional issue-recommended S0ix mitigations

The issue's three applicable blocker mitigations are staged for installation:

1. Enable `iwlwifi power_save=1` so the CNVi Wi-Fi device can leave D0.
2. Set `POWERDEVIL_NO_DDCUTIL=1` to prevent KDE display polling from keeping
   the GPU/PCH active.
3. Explicitly set WirePlumber ALSA node suspension to five seconds.

The current boot already has `s2idle` selected. ACPI/USB wake sources are not
being disabled because the corrected journal shows that the system stayed
asleep until the deliberate wake. The Type-C initramfs workaround is not being
applied because both `cros_ec_typec` and `intel_pmc_mux` loaded, Type-C port 0
bound successfully, and no deferred probe failure appears in the boot journal.

The three power settings require a reboot to take effect reliably before the
next S0ix residency test.

An automated `sudo -n ./sleep/install-power-tweaks.sh` attempt stopped because
local administrator authentication is required. Since sudo rejected the command
before starting the script, that attempt made no system changes. The machine
owner must run the installer interactively, then reboot.

The machine owner subsequently installed the settings and rebooted. Post-reboot
verification found:

- `cros_ec_sleep_kprobe` automatically loaded at 19:46:22 and registered on
  `cros_ec_cmd_xfer`.
- DKMS reports the module installed for `7.2.5-200.fc44.x86_64`.
- All three power-setting files are present under `/etc`.
- The live `iwlwifi` parameter is `power_save=Y`, proving that the module option
  took effect at boot.
- The Fedora package versions used were DKMS 3.4.3, GCC 16.2.1, Make 4.4.1,
  kernel-devel 7.2.5-200, WirePlumber 0.5.14, PowerDevil 6.7.5, and DDCUtil
  2.2.1.

### Post-tuning S0ix test

Test log: `s0ix-test-20260914-194728.log`.

The kernel journal shows suspend entry at 19:47:29 and exit at 19:47:33. The
platform low-power-idle counter increased by 3,231,914 us during this short
sample, proving that the platform entered S0ix promptly. The script displayed
42.9%, but that percentage is not a meaningful residency-efficiency result:
the requested two-minute duration was not observed, and the script's
post-`systemctl` wait was included in its wall interval.

`test-s0ix.sh` has been corrected to remain alive while the asynchronous
suspend request is processed and to refrain from grading samples shorter than
60 seconds. A future efficiency measurement should leave the machine suspended
for at least 120 seconds. The functional outcome is nevertheless confirmed:
the additional settings took effect and S0ix entry occurred.

## Rollback

Run:

```bash
sudo ./sleep/uninstall.sh
```

Then reboot. The rollback unloads the kprobe module, removes its DKMS entry,
removes only the two configuration files created by this deployment, deletes
its dedicated `/usr/src` directory, and regenerates module dependencies.
