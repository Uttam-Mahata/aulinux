/**
 * AULinux Sysctl Interface
 * 
 * Provides sysctl entries for runtime configuration of AULinux features.
 * Accessible via /proc/sys/aulinux/
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/sysctl.h>

#include "aulinux.h"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("AULinux Team");
MODULE_DESCRIPTION("AULinux Sysctl Configuration Interface");
MODULE_VERSION("1.0.0");

/* Configurable parameters */
static int aulinux_debug_level = 0;      /* 0=off, 1=basic, 2=verbose */
static int aulinux_feature_flags = 0;     /* Bitfield for feature toggles */
static int aulinux_max_processes = 4096;  /* Max tracked processes */

/* Parameter bounds */
static int debug_level_min = 0;
static int debug_level_max = 2;
static int max_proc_min = 128;
static int max_proc_max = 65536;

/* Sysctl table for /proc/sys/aulinux/ */
static struct ctl_table aulinux_sysctl_table[] = {
    {
        .procname    = "debug_level",
        .data        = &aulinux_debug_level,
        .maxlen      = sizeof(int),
        .mode        = 0644,
        .proc_handler = proc_dointvec_minmax,
        .extra1      = &debug_level_min,
        .extra2      = &debug_level_max,
    },
    {
        .procname    = "feature_flags",
        .data        = &aulinux_feature_flags,
        .maxlen      = sizeof(int),
        .mode        = 0644,
        .proc_handler = proc_dointvec,
    },
    {
        .procname    = "max_processes",
        .data        = &aulinux_max_processes,
        .maxlen      = sizeof(int),
        .mode        = 0644,
        .proc_handler = proc_dointvec_minmax,
        .extra1      = &max_proc_min,
        .extra2      = &max_proc_max,
    },
};

static struct ctl_table_header *aulinux_sysctl_header;

/**
 * Get current debug level (for use by other modules)
 */
int aulinux_get_debug_level(void)
{
    return aulinux_debug_level;
}
EXPORT_SYMBOL(aulinux_get_debug_level);

/**
 * Check if a feature flag is enabled
 */
int aulinux_feature_enabled(int flag)
{
    return (aulinux_feature_flags & flag) != 0;
}
EXPORT_SYMBOL(aulinux_feature_enabled);

/**
 * Initialize sysctl interface
 */
static int __init aulinux_sysctl_init(void)
{
    pr_info("AULinux: Registering sysctl interface\n");

    aulinux_sysctl_header = register_sysctl("aulinux", aulinux_sysctl_table);
    if (!aulinux_sysctl_header) {
        pr_err("AULinux: Failed to register sysctl table\n");
        return -ENOMEM;
    }

    pr_info("AULinux: Sysctl interface registered at /proc/sys/aulinux/\n");
    return 0;
}

/**
 * Cleanup sysctl interface
 */
static void __exit aulinux_sysctl_exit(void)
{
    if (aulinux_sysctl_header)
        unregister_sysctl_table(aulinux_sysctl_header);

    pr_info("AULinux: Sysctl interface unregistered\n");
}

module_init(aulinux_sysctl_init);
module_exit(aulinux_sysctl_exit);
