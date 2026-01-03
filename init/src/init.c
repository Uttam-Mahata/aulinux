/**
 * AULinux Init System (au-init)
 * 
 * The first userspace process (PID 1) responsible for:
 * - Mounting essential filesystems
 * - Starting system services
 * - Reaping orphaned processes
 * - Handling system shutdown/reboot
 * 
 * Built with -static to run before shared libraries are available.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>

#define AUINIT_VERSION "1.0.0"
#define MAX_SERVICES 32
#define SERVICE_CONFIG "/etc/aulinux/services.conf"
#define DEFAULT_SHELL "/bin/aush"
#define FALLBACK_SHELL "/bin/sh"

/* Service states */
enum service_state {
    SERVICE_STOPPED = 0,
    SERVICE_STARTING,
    SERVICE_RUNNING,
    SERVICE_STOPPING,
    SERVICE_FAILED,
};

/* Service definition */
struct service {
    char name[64];
    char command[256];
    pid_t pid;
    enum service_state state;
    int restart_count;
    time_t last_start;
};

/* Global state */
static struct service services[MAX_SERVICES];
static int service_count = 0;
static volatile sig_atomic_t running = 1;
static volatile sig_atomic_t reboot_requested = 0;
static volatile sig_atomic_t poweroff_requested = 0;
static volatile sig_atomic_t child_exited = 0;

/* Forward declarations */
static void log_msg(const char *level, const char *fmt, ...);
static int mount_filesystems(void);
static int setup_console(void);
static void signal_handler(int sig);
static void setup_signals(void);
static void reap_children(void);
static pid_t spawn_process(const char *path, char *const argv[]);
static int start_shell(void);
static void shutdown_system(int reboot);

/**
 * Log message to console
 */
static void log_msg(const char *level, const char *fmt, ...)
{
    va_list args;
    time_t now;
    struct tm *tm_info;
    char time_buf[32];

    time(&now);
    tm_info = localtime(&now);
    strftime(time_buf, sizeof(time_buf), "%H:%M:%S", tm_info);

    fprintf(stderr, "[%s] au-init [%s]: ", time_buf, level);
    
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    
    fprintf(stderr, "\n");
}

/**
 * Mount essential filesystems
 */
static int mount_filesystems(void)
{
    log_msg("INFO", "Mounting essential filesystems...");

    /* Mount /proc */
    if (mount("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL) < 0) {
        if (errno != EBUSY) {
            log_msg("WARN", "Failed to mount /proc: %s", strerror(errno));
        }
    } else {
        log_msg("INFO", "Mounted /proc");
    }

    /* Mount /sys */
    if (mount("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL) < 0) {
        if (errno != EBUSY) {
            log_msg("WARN", "Failed to mount /sys: %s", strerror(errno));
        }
    } else {
        log_msg("INFO", "Mounted /sys");
    }

    /* Mount /dev (devtmpfs) */
    if (mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755") < 0) {
        if (errno != EBUSY) {
            log_msg("WARN", "Failed to mount /dev: %s", strerror(errno));
        }
    } else {
        log_msg("INFO", "Mounted /dev");
    }

    /* Mount /dev/pts */
    mkdir("/dev/pts", 0755);
    if (mount("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC, "gid=5,mode=620") < 0) {
        if (errno != EBUSY) {
            log_msg("WARN", "Failed to mount /dev/pts: %s", strerror(errno));
        }
    } else {
        log_msg("INFO", "Mounted /dev/pts");
    }

    /* Mount /run (tmpfs) */
    if (mount("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755") < 0) {
        if (errno != EBUSY) {
            log_msg("WARN", "Failed to mount /run: %s", strerror(errno));
        }
    } else {
        log_msg("INFO", "Mounted /run");
    }

    /* Mount /tmp (tmpfs) */
    if (mount("tmpfs", "/tmp", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777") < 0) {
        if (errno != EBUSY) {
            log_msg("WARN", "Failed to mount /tmp: %s", strerror(errno));
        }
    } else {
        log_msg("INFO", "Mounted /tmp");
    }

    return 0;
}

/**
 * Setup console I/O
 */
static int setup_console(void)
{
    int fd;

    /* Try to open console */
    fd = open("/dev/console", O_RDWR | O_NOCTTY);
    if (fd >= 0) {
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > STDERR_FILENO) {
            close(fd);
        }
        log_msg("INFO", "Console initialized");
        return 0;
    }

    /* Fallback: try /dev/tty1 */
    fd = open("/dev/tty1", O_RDWR | O_NOCTTY);
    if (fd >= 0) {
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > STDERR_FILENO) {
            close(fd);
        }
        log_msg("INFO", "TTY1 initialized as console");
        return 0;
    }

    return -1;
}

/**
 * Signal handler
 */
static void signal_handler(int sig)
{
    switch (sig) {
        case SIGCHLD:
            child_exited = 1;
            break;
        case SIGTERM:
        case SIGINT:
            running = 0;
            poweroff_requested = 1;
            break;
        case SIGUSR1:
            running = 0;
            reboot_requested = 1;
            break;
        case SIGUSR2:
            running = 0;
            poweroff_requested = 1;
            break;
        default:
            break;
    }
}

/**
 * Setup signal handlers
 */
static void setup_signals(void)
{
    struct sigaction sa;

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;

    sigaction(SIGCHLD, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);  /* Reboot */
    sigaction(SIGUSR2, &sa, NULL);  /* Poweroff */

    /* Ignore these signals */
    signal(SIGHUP, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
}

/**
 * Reap zombie processes (init's responsibility as PID 1)
 */
static void reap_children(void)
{
    pid_t pid;
    int status;
    int i;

    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        /* Check if it was a tracked service */
        for (i = 0; i < service_count; i++) {
            if (services[i].pid == pid) {
                if (WIFEXITED(status)) {
                    log_msg("INFO", "Service '%s' (PID %d) exited with status %d",
                            services[i].name, pid, WEXITSTATUS(status));
                } else if (WIFSIGNALED(status)) {
                    log_msg("WARN", "Service '%s' (PID %d) killed by signal %d",
                            services[i].name, pid, WTERMSIG(status));
                }
                services[i].pid = 0;
                services[i].state = SERVICE_STOPPED;
                break;
            }
        }
    }
    
    child_exited = 0;
}

/**
 * Spawn a new process
 */
static pid_t spawn_process(const char *path, char *const argv[])
{
    pid_t pid;

    pid = fork();
    if (pid < 0) {
        log_msg("ERROR", "fork() failed: %s", strerror(errno));
        return -1;
    }

    if (pid == 0) {
        /* Child process */
        setsid();  /* Create new session */
        execv(path, argv);
        /* If exec fails */
        fprintf(stderr, "au-init: execv(%s) failed: %s\n", path, strerror(errno));
        _exit(127);
    }

    return pid;
}

/**
 * Start the user shell
 */
static int start_shell(void)
{
    pid_t pid;
    char *shell = DEFAULT_SHELL;
    char *argv[] = { "aush", "-l", NULL };

    /* Check if default shell exists */
    if (access(shell, X_OK) != 0) {
        shell = FALLBACK_SHELL;
        argv[0] = "sh";
        
        if (access(shell, X_OK) != 0) {
            log_msg("ERROR", "No shell available");
            return -1;
        }
    }

    log_msg("INFO", "Starting shell: %s", shell);
    
    pid = spawn_process(shell, argv);
    if (pid < 0) {
        return -1;
    }

    /* Track shell as a service */
    if (service_count < MAX_SERVICES) {
        strncpy(services[service_count].name, "shell", sizeof(services[0].name) - 1);
        strncpy(services[service_count].command, shell, sizeof(services[0].command) - 1);
        services[service_count].pid = pid;
        services[service_count].state = SERVICE_RUNNING;
        services[service_count].last_start = time(NULL);
        service_count++;
    }

    return 0;
}

/**
 * Shutdown the system
 */
static void shutdown_system(int do_reboot)
{
    int i;

    log_msg("INFO", do_reboot ? "System reboot initiated" : "System shutdown initiated");

    /* Send SIGTERM to all services */
    log_msg("INFO", "Stopping services...");
    for (i = 0; i < service_count; i++) {
        if (services[i].pid > 0) {
            log_msg("INFO", "Stopping %s (PID %d)", services[i].name, services[i].pid);
            kill(services[i].pid, SIGTERM);
        }
    }

    /* Wait briefly for graceful shutdown */
    sleep(2);

    /* Send SIGKILL to any remaining processes */
    for (i = 0; i < service_count; i++) {
        if (services[i].pid > 0) {
            kill(services[i].pid, SIGKILL);
        }
    }

    /* Reap any remaining children */
    reap_children();

    /* Sync filesystems */
    log_msg("INFO", "Syncing filesystems...");
    sync();

    /* Unmount filesystems (in reverse order) */
    log_msg("INFO", "Unmounting filesystems...");
    umount2("/tmp", MNT_DETACH);
    umount2("/run", MNT_DETACH);
    umount2("/dev/pts", MNT_DETACH);
    umount2("/dev", MNT_DETACH);
    umount2("/sys", MNT_DETACH);
    umount2("/proc", MNT_DETACH);

    /* Perform reboot or poweroff */
    sync();
    
    if (do_reboot) {
        log_msg("INFO", "Rebooting...");
        reboot(RB_AUTOBOOT);
    } else {
        log_msg("INFO", "Powering off...");
        reboot(RB_POWER_OFF);
    }
}

/**
 * Print version info
 */
static void print_version(void)
{
    printf("au-init %s - AULinux Init System\n", AUINIT_VERSION);
    printf("Copyright (c) 2026 AULinux Team\n");
}

/**
 * Print usage
 */
static void print_usage(const char *prog)
{
    printf("Usage: %s [OPTIONS]\n", prog);
    printf("\nOptions:\n");
    printf("  --version    Show version information\n");
    printf("  --help       Show this help message\n");
    printf("\nSignals:\n");
    printf("  SIGUSR1      Reboot the system\n");
    printf("  SIGUSR2      Power off the system\n");
}

/**
 * Main entry point
 */
int main(int argc, char *argv[])
{
    pid_t my_pid;

    /* Handle command line arguments */
    if (argc > 1) {
        if (strcmp(argv[1], "--version") == 0) {
            print_version();
            return 0;
        }
        if (strcmp(argv[1], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        }
    }

    my_pid = getpid();

    /* Print banner */
    fprintf(stderr, "\n");
    fprintf(stderr, "  ╔═══════════════════════════════════════╗\n");
    fprintf(stderr, "  ║     AULinux Init System v%s      ║\n", AUINIT_VERSION);
    fprintf(stderr, "  ║   Absolutely Unique Linux Distribution ║\n");
    fprintf(stderr, "  ╚═══════════════════════════════════════╝\n");
    fprintf(stderr, "\n");

    /* Check if running as PID 1 */
    if (my_pid != 1) {
        log_msg("WARN", "Not running as PID 1 (current PID: %d)", my_pid);
        log_msg("INFO", "Running in test mode...");
    } else {
        log_msg("INFO", "Starting as PID 1");
    }

    /* Setup signal handlers */
    setup_signals();

    /* Setup console */
    if (my_pid == 1) {
        setup_console();
    }

    /* Mount essential filesystems */
    if (my_pid == 1) {
        mount_filesystems();
    }

    log_msg("INFO", "System initialization complete");

    /* Start the shell */
    if (start_shell() < 0) {
        log_msg("ERROR", "Failed to start shell");
        if (my_pid == 1) {
            /* As PID 1, we cannot exit - spawn emergency shell */
            log_msg("WARN", "Spawning emergency shell...");
            char *argv[] = { "sh", NULL };
            spawn_process("/bin/sh", argv);
        } else {
            return 1;
        }
    }

    /* Main loop */
    log_msg("INFO", "Entering main loop");
    while (running) {
        /* Wait for signals */
        pause();

        /* Reap any zombie processes */
        if (child_exited) {
            reap_children();
        }
    }

    /* Shutdown */
    if (reboot_requested) {
        shutdown_system(1);
    } else if (poweroff_requested) {
        shutdown_system(0);
    }

    /* Should never reach here if running as PID 1 */
    return 0;
}
