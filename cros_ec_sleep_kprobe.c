// SPDX-License-Identifier: GPL-2.0
/*
 * Temporary workaround for Chrome EC HOST_SLEEP_EVENT timeout handling.
 *
 * Based on 5fff/linux-chromebook-sleep-dkms commit
 * 2e0b782eec92da887b44cd528b61b6e658731d60. The local changes add payload
 * length validation and preserve the kernel's register_kprobe() error code.
 */
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/platform_data/cros_ec_commands.h>
#include <linux/platform_data/cros_ec_proto.h>
#include <linux/ptrace.h>

static struct kprobe sleep_event_probe = {
	.symbol_name = "cros_ec_cmd_xfer",
};

static int set_infinite_sleep_timeout(struct kprobe *probe,
				      struct pt_regs *regs)
{
	struct cros_ec_command *msg;
	struct ec_params_host_sleep_event_v1 *request;

	msg = (struct cros_ec_command *)regs_get_kernel_argument(regs, 1);
	if (!msg || msg->command != EC_CMD_HOST_SLEEP_EVENT || msg->version != 1)
		return 0;

	if (msg->outsize < sizeof(*request))
		return 0;

	request = (struct ec_params_host_sleep_event_v1 *)msg->data;
	if (request->sleep_event != HOST_SLEEP_EVENT_S0IX_SUSPEND &&
	    request->sleep_event != HOST_SLEEP_EVENT_S3_SUSPEND &&
	    request->sleep_event != HOST_SLEEP_EVENT_S3_WAKEABLE_SUSPEND)
		return 0;

	request->suspend_params.sleep_timeout_ms = 0xffff;
	pr_info("cros_ec_sleep_kprobe: set HOST_SLEEP_EVENT timeout to infinite\n");
	return 0;
}

static int __init cros_ec_sleep_kprobe_init(void)
{
	int ret;

	sleep_event_probe.pre_handler = set_infinite_sleep_timeout;
	ret = register_kprobe(&sleep_event_probe);
	if (ret) {
		pr_err("cros_ec_sleep_kprobe: register_kprobe failed: %d\n", ret);
		return ret;
	}

	pr_info("cros_ec_sleep_kprobe: registered on %s\n",
		sleep_event_probe.symbol_name);
	return 0;
}

static void __exit cros_ec_sleep_kprobe_exit(void)
{
	unregister_kprobe(&sleep_event_probe);
	pr_info("cros_ec_sleep_kprobe: unregistered\n");
}

module_init(cros_ec_sleep_kprobe_init);
module_exit(cros_ec_sleep_kprobe_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Ray X; locally hardened for this installation");
MODULE_DESCRIPTION("Temporary Chrome EC suspend-timeout workaround");

