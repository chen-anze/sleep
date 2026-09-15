#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT="${SCRIPT_DIR}/suspend-test-${STAMP}.log"
START_EPOCH="$(date +%s)"

exec > >(tee "${RESULT}") 2>&1

echo "Redrix Chrome EC suspend test"
echo "Started: $(date --iso-8601=seconds)"
echo "Kernel: $(uname -r)"
echo "Sleep modes: $(< /sys/power/mem_sleep)"

if [[ ! -d /sys/module/cros_ec_sleep_kprobe ]]; then
	echo "FAIL: cros_ec_sleep_kprobe is not loaded." >&2
	exit 1
fi

echo
echo "Suspending now. Leave the machine asleep for at least 60 seconds."
echo "Then wake it with the power button or by opening the lid."
sync
systemctl suspend

sleep 3
echo
echo "Resumed: $(date --iso-8601=seconds)"

JOURNAL="$(journalctl -b -k --since "@${START_EPOCH}" --no-pager)"
printf '%s\n' "${JOURNAL}" | grep -E \
	'PM: suspend (entry|exit)|cros_ec_sleep_kprobe|EC detected sleep transition timeout' \
	|| true

PATCH_COUNT="$(printf '%s\n' "${JOURNAL}" | grep -c \
	'cros_ec_sleep_kprobe: set HOST_SLEEP_EVENT timeout to infinite' || true)"
TIMEOUT_COUNT="$(printf '%s\n' "${JOURNAL}" | grep -c \
	'EC detected sleep transition timeout' || true)"
ENTRY_COUNT="$(printf '%s\n' "${JOURNAL}" | grep -c 'PM: suspend entry' || true)"
EXIT_COUNT="$(printf '%s\n' "${JOURNAL}" | grep -c 'PM: suspend exit' || true)"

echo
if (( PATCH_COUNT >= 1 && TIMEOUT_COUNT == 0 && ENTRY_COUNT >= 1 && EXIT_COUNT >= 1 )); then
	echo "PASS: workaround intercepted suspend; no EC timeout was recorded."
	exit 0
fi

echo "INCONCLUSIVE/FAIL: patch=${PATCH_COUNT} timeout=${TIMEOUT_COUNT} entry=${ENTRY_COUNT} exit=${EXIT_COUNT}" >&2
echo "Review ${RESULT} and the full boot journal." >&2
exit 1

