/**
 * AULinux Kernel Module Common Header
 * 
 * Shared definitions, macros, and declarations for all AULinux
 * kernel modules.
 */

#ifndef _AULINUX_H
#define _AULINUX_H

#include <linux/types.h>

/* Version information */
#define AULINUX_VERSION_MAJOR  1
#define AULINUX_VERSION_MINOR  0
#define AULINUX_VERSION_PATCH  0
#define AULINUX_VERSION_STRING "1.0.0"

/* Feature flags (for aulinux_feature_enabled) */
#define AULINUX_FEATURE_PROCMON     (1 << 0)  /* Process monitoring */
#define AULINUX_FEATURE_AUDIT       (1 << 1)  /* Security auditing */
#define AULINUX_FEATURE_SANDBOX     (1 << 2)  /* Process sandboxing */
#define AULINUX_FEATURE_NETMON      (1 << 3)  /* Network monitoring */

/* Debug macros */
#define AULINUX_DEBUG_NONE    0
#define AULINUX_DEBUG_BASIC   1
#define AULINUX_DEBUG_VERBOSE 2

/* External function declarations (from aulinux_sysctl.c) */
extern int aulinux_get_debug_level(void);
extern int aulinux_feature_enabled(int flag);

/* Logging macros with debug level checking */
#define aulinux_pr_debug(level, fmt, ...) \
    do { \
        if (aulinux_get_debug_level() >= (level)) \
            pr_debug("AULinux: " fmt, ##__VA_ARGS__); \
    } while (0)

#define aulinux_pr_info(fmt, ...) \
    pr_info("AULinux: " fmt, ##__VA_ARGS__)

#define aulinux_pr_warn(fmt, ...) \
    pr_warn("AULinux: " fmt, ##__VA_ARGS__)

#define aulinux_pr_err(fmt, ...) \
    pr_err("AULinux: " fmt, ##__VA_ARGS__)

/* IOCTL definitions for userspace communication */
#define AULINUX_IOC_MAGIC  'A'
#define AULINUX_IOC_GET_VERSION   _IOR(AULINUX_IOC_MAGIC, 0, int)
#define AULINUX_IOC_GET_FEATURES  _IOR(AULINUX_IOC_MAGIC, 1, int)
#define AULINUX_IOC_SET_FEATURES  _IOW(AULINUX_IOC_MAGIC, 2, int)

/* Maximum limits */
#define AULINUX_MAX_NAME_LEN     256
#define AULINUX_MAX_PATH_LEN     4096
#define AULINUX_MAX_PROCESSES    65536

/* Return codes */
#define AULINUX_SUCCESS          0
#define AULINUX_ERR_NOMEM       -1
#define AULINUX_ERR_INVAL       -2
#define AULINUX_ERR_PERM        -3
#define AULINUX_ERR_BUSY        -4

#endif /* _AULINUX_H */
