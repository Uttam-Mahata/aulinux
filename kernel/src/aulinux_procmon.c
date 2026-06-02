/**
 * AULinux Process Monitor
 * 
 * Kernel module for monitoring process lifecycle events.
 * Hooks into process creation/termination for system auditing.
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/kprobes.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/spinlock.h>
#include <linux/slab.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("AULinux Team");
MODULE_DESCRIPTION("AULinux Process Lifecycle Monitor");
MODULE_VERSION("1.0.0");
MODULE_SOFTDEP("pre: aulinux_core");

#define PROCMON_HISTORY_SIZE 64

/* Process event types */
enum procmon_event_type {
    PROCMON_FORK = 0,
    PROCMON_EXEC,
    PROCMON_EXIT,
};

/* Process event record */
struct procmon_event {
    enum procmon_event_type type;
    pid_t pid;
    pid_t ppid;
    char comm[TASK_COMM_LEN];
    ktime_t timestamp;
};

/* Circular buffer for event history */
static struct procmon_event event_history[PROCMON_HISTORY_SIZE];
static int event_head = 0;
static int event_count = 0;
static DEFINE_SPINLOCK(event_lock);

/* Statistics */
static atomic_long_t total_forks = ATOMIC_LONG_INIT(0);
static atomic_long_t total_execs = ATOMIC_LONG_INIT(0);
static atomic_long_t total_exits = ATOMIC_LONG_INIT(0);

/* Enable/disable monitoring */
static int monitoring_enabled = 1;

/**
 * Record a process event to the circular buffer
 */
static void record_event(enum procmon_event_type type, 
                         struct task_struct *task)
{
    unsigned long flags;

    if (!monitoring_enabled)
        return;

    spin_lock_irqsave(&event_lock, flags);

    event_history[event_head].type = type;
    event_history[event_head].pid = task->pid;
    event_history[event_head].ppid = task->real_parent ? 
                                      task->real_parent->pid : 0;
    strncpy(event_history[event_head].comm, task->comm, TASK_COMM_LEN - 1);
    event_history[event_head].comm[TASK_COMM_LEN - 1] = '\0';
    event_history[event_head].timestamp = ktime_get_real();

    event_head = (event_head + 1) % PROCMON_HISTORY_SIZE;
    if (event_count < PROCMON_HISTORY_SIZE)
        event_count++;

    spin_unlock_irqrestore(&event_lock, flags);
}

/**
 * Kprobe handler for process fork
 */
static int fork_handler_pre(struct kprobe *p, struct pt_regs *regs)
{
    atomic_long_inc(&total_forks);
    record_event(PROCMON_FORK, current);
    return 0;
}

/**
 * Kprobe handler for process exit
 */
static int exit_handler_pre(struct kprobe *p, struct pt_regs *regs)
{
    atomic_long_inc(&total_exits);
    record_event(PROCMON_EXIT, current);
    return 0;
}

/* Kprobe structures */
static struct kprobe fork_kp = {
    .symbol_name = "kernel_clone",
    .pre_handler = fork_handler_pre,
};

static struct kprobe exit_kp = {
    .symbol_name = "do_exit",
    .pre_handler = exit_handler_pre,
};

/**
 * Show process monitor statistics
 */
static int procmon_stats_show(struct seq_file *m, void *v)
{
    seq_printf(m, "AULinux Process Monitor Statistics\n");
    seq_printf(m, "===================================\n");
    seq_printf(m, "Monitoring: %s\n", monitoring_enabled ? "enabled" : "disabled");
    seq_printf(m, "Total Forks: %ld\n", atomic_long_read(&total_forks));
    seq_printf(m, "Total Execs: %ld\n", atomic_long_read(&total_execs));
    seq_printf(m, "Total Exits: %ld\n", atomic_long_read(&total_exits));
    seq_printf(m, "Event Buffer: %d/%d\n", event_count, PROCMON_HISTORY_SIZE);
    return 0;
}

/**
 * Show recent process events
 */
static int procmon_events_show(struct seq_file *m, void *v)
{
    unsigned long flags;
    int i, idx;
    static const char *type_names[] = { "FORK", "EXEC", "EXIT" };

    seq_printf(m, "Recent Process Events\n");
    seq_printf(m, "%-6s %-6s %-6s %-16s %s\n", 
               "TYPE", "PID", "PPID", "COMM", "TIMESTAMP");
    seq_printf(m, "----------------------------------------------\n");

    spin_lock_irqsave(&event_lock, flags);

    for (i = 0; i < event_count; i++) {
        idx = (event_head - event_count + i + PROCMON_HISTORY_SIZE) 
              % PROCMON_HISTORY_SIZE;
        seq_printf(m, "%-6s %-6d %-6d %-16s %lld\n",
                   type_names[event_history[idx].type],
                   event_history[idx].pid,
                   event_history[idx].ppid,
                   event_history[idx].comm,
                   ktime_to_ns(event_history[idx].timestamp));
    }

    spin_unlock_irqrestore(&event_lock, flags);
    return 0;
}

static int procmon_stats_open(struct inode *inode, struct file *file)
{
    return single_open(file, procmon_stats_show, NULL);
}

static int procmon_events_open(struct inode *inode, struct file *file)
{
    return single_open(file, procmon_events_show, NULL);
}

static const struct proc_ops procmon_stats_ops = {
    .proc_open    = procmon_stats_open,
    .proc_read    = seq_read,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};

static const struct proc_ops procmon_events_ops = {
    .proc_open    = procmon_events_open,
    .proc_read    = seq_read,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};

static struct proc_dir_entry *procmon_dir;

/**
 * Initialize process monitor
 */
static int __init aulinux_procmon_init(void)
{
    int ret;

    pr_info("AULinux: Initializing process monitor\n");

    /* Register kprobes */
    ret = register_kprobe(&fork_kp);
    if (ret < 0) {
        pr_warn("AULinux: Failed to register fork kprobe: %d\n", ret);
        /* Continue without fork monitoring */
    }

    ret = register_kprobe(&exit_kp);
    if (ret < 0) {
        pr_warn("AULinux: Failed to register exit kprobe: %d\n", ret);
        /* Continue without exit monitoring */
    }

    /* Create proc entries */
    procmon_dir = proc_mkdir("aulinux/procmon", NULL);
    if (procmon_dir) {
        proc_create("stats", 0444, procmon_dir, &procmon_stats_ops);
        proc_create("events", 0444, procmon_dir, &procmon_events_ops);
    }

    pr_info("AULinux: Process monitor initialized\n");
    return 0;
}

/**
 * Cleanup process monitor
 */
static void __exit aulinux_procmon_exit(void)
{
    unregister_kprobe(&fork_kp);
    unregister_kprobe(&exit_kp);

    if (procmon_dir)
        proc_remove(procmon_dir);

    pr_info("AULinux: Process monitor unloaded\n");
}

module_init(aulinux_procmon_init);
module_exit(aulinux_procmon_exit);
