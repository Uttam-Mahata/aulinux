/**
 * AULinux Core Kernel Module
 * 
 * Main kernel module providing AULinux-specific system features.
 * This module initializes the AULinux subsystem and registers
 * core functionality with the Linux kernel.
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/version.h>

#define AULINUX_VERSION "1.0.0"
#define AULINUX_PROC_NAME "aulinux"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("AULinux Team");
MODULE_DESCRIPTION("AULinux Core Kernel Module");
MODULE_VERSION(AULINUX_VERSION);
MODULE_SOFTDEP("pre: aulinux_sysctl");

/* Proc filesystem entry */
static struct proc_dir_entry *aulinux_proc_dir;
static struct proc_dir_entry *aulinux_version_entry;

/**
 * Show AULinux version information in /proc/aulinux/version
 */
static int aulinux_version_show(struct seq_file *m, void *v)
{
    seq_printf(m, "AULinux Version: %s\n", AULINUX_VERSION);
    seq_printf(m, "Kernel Version: %d.%d.%d\n", 
               LINUX_VERSION_MAJOR,
               LINUX_VERSION_PATCHLEVEL,
               LINUX_VERSION_SUBLEVEL);
    return 0;
}

static int aulinux_version_open(struct inode *inode, struct file *file)
{
    return single_open(file, aulinux_version_show, NULL);
}

static const struct proc_ops aulinux_version_ops = {
    .proc_open    = aulinux_version_open,
    .proc_read    = seq_read,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};

/**
 * Initialize the AULinux core module
 */
static int __init aulinux_core_init(void)
{
    pr_info("AULinux: Initializing core module v%s\n", AULINUX_VERSION);

    /* Create /proc/aulinux directory */
    aulinux_proc_dir = proc_mkdir(AULINUX_PROC_NAME, NULL);
    if (!aulinux_proc_dir) {
        pr_err("AULinux: Failed to create /proc/%s\n", AULINUX_PROC_NAME);
        return -ENOMEM;
    }

    /* Create /proc/aulinux/version entry */
    aulinux_version_entry = proc_create("version", 0444, 
                                         aulinux_proc_dir,
                                         &aulinux_version_ops);
    if (!aulinux_version_entry) {
        pr_err("AULinux: Failed to create version proc entry\n");
        proc_remove(aulinux_proc_dir);
        return -ENOMEM;
    }

    pr_info("AULinux: Core module initialized successfully\n");
    return 0;
}

/**
 * Cleanup the AULinux core module
 */
static void __exit aulinux_core_exit(void)
{
    pr_info("AULinux: Unloading core module\n");

    if (aulinux_version_entry)
        proc_remove(aulinux_version_entry);
    
    if (aulinux_proc_dir)
        proc_remove(aulinux_proc_dir);

    pr_info("AULinux: Core module unloaded\n");
}

module_init(aulinux_core_init);
module_exit(aulinux_core_exit);
