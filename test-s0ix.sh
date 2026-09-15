#!/usr/bin/env bash
set -euo pipefail

COUNTER=/sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT="${SCRIPT_DIR}/s0ix-test-${STAMP}.log"

exec > >(tee "${RESULT}") 2>&1

if [[ ! -r ${COUNTER} ]]; then
	echo "FAIL: platform low-power-idle counter is unavailable: ${COUNTER}" >&2
	exit 1
fi

if [[ ! -d /sys/module/cros_ec_sleep_kprobe ]]; then
	echo "FAIL: cros_ec_sleep_kprobe is not loaded." >&2
	exit 1
fi

BEFORE_US="$(< "${COUNTER}")"
START_NS="$(date +%s%N)"

echo "Redrix S0ix residency test"
echo "Started: $(date --iso-8601=seconds)"
echo "Kernel: $(uname -r)"
echo "Sleep modes: $(< /sys/power/mem_sleep)"
echo "Initial platform low-power-idle residency: ${BEFORE_US} us"
echo
echo "Suspending now. Leave the machine asleep for at least 120 seconds,"
echo "then wake it with the power button or lid."
sync
systemctl suspend

# systemctl may return as soon as suspend is queued, before the kernel has
# actually entered suspend. Keep this process alive across the transition and
# allow resume timekeeping and Intel PMC telemetry to settle.
sleep 10
END_NS="$(date +%s%N)"
AFTER_US="$(< "${COUNTER}")"
ELAPSED_US="$(( (END_NS - START_NS) / 1000 ))"
DELTA_US="$(( AFTER_US - BEFORE_US ))"
PERCENT="$(awk -v delta="${DELTA_US}" -v elapsed="${ELAPSED_US}" \
	'BEGIN { if (elapsed > 0) printf "%.1f", delta * 100 / elapsed; else print "0.0" }')"

echo
echo "Resumed: $(date --iso-8601=seconds)"
echo "Final platform low-power-idle residency: ${AFTER_US} us"
echo "Residency gained: ${DELTA_US} us"
echo "Wall-clock test interval: ${ELAPSED_US} us"
echo "Platform low-power-idle residency ratio: ${PERCENT}%"

if (( DELTA_US <= 0 )); then
	echo "FAIL: the platform did not enter S0ix." >&2
	exit 1
fi

echo "PASS: the Intel platform entered S0ix during this interval."
if (( ELAPSED_US < 60000000 )); then
	echo "NOTE: this was a short test; the percentage is not a reliable efficiency measurement."
	echo "Repeat and remain suspended for at least 120 seconds to grade residency."
elif awk -v ratio="${PERCENT}" 'BEGIN { exit !(ratio < 80) }'; then
	echo "NOTE: residency below 80% suggests delayed entry or a low-power blocker."
else
	echo "GOOD: residency above 80% indicates that most of the interval was spent in S0ix."
fi

echo "Saved result: ${RESULT}"
