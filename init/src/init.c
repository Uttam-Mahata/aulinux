/**
 * AULinux Init System (au-init) v2.0
 *
 * Innovations over v1.0:
 *   - INI-style [ServiceName] config sections
 *   - Parallel startup via Kahn's topological sort
 *   - Per-service cgroup v2 isolation (auto-detected)
 *   - Per-service User= / Group= identity (setuid/setgid)
 *   - Environment= and EnvironmentFile= directives
 *   - ExecStartPre= / ExecStop= lifecycle hooks
 *   - Socket activation via ListenStream=
 *   - Timer units (OnBootSec= / OnUnitActiveSec=)
 *   - Unix socket control at /run/auinit.sock  (auctl)
 *   - Network targets (network-pre.target, network.target)
 *   - Provides=  (service declares provided virtual targets)
 *   - Restart=  policy: always | on-failure | never
 *   - ACPI power button (SIGPWR) -> clean shutdown
 *   - Persistent boot log at /var/log/au-init.log
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
#include <errno.h>
#include <time.h>
#include <fcntl.h>
#include <pwd.h>
#include <grp.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <net/if.h>
#include <arpa/inet.h>

/* ── Constants ────────────────────────────────────────────────────── */
#define AUINIT_VERSION  "2.0.0"
#define MAX_SERVICES    64
#define MAX_DEPS        16
#define MAX_ENV         32
#define MAX_PROVIDES    8
#define SERVICE_CONFIG  "/etc/aulinux/services.conf"
#define DEFAULT_SHELL   "/bin/aush"
#define FALLBACK_SHELL  "/bin/sh"
#define CONTROL_SOCK    "/run/auinit.sock"
#define INIT_LOG_FILE   "/var/log/au-init.log"
#define CGROUP_ROOT     "/sys/fs/cgroup/aulinux"

/* ── Enumerations ─────────────────────────────────────────────────── */

typedef enum {
    TYPE_SIMPLE  = 0,   /* Long-running process (default) */
    TYPE_TARGET,        /* Virtual sync point — no process */
    TYPE_TIMER,         /* Fires another unit on a schedule */
    TYPE_ONESHOT,       /* Runs once, no restart */
} ServiceType;

typedef enum {
    STATE_INACTIVE = 0, /* Not started */
    STATE_WAITING,      /* Waiting for After= deps */
    STATE_ACTIVATING,   /* Running ExecStartPre= */
    STATE_ACTIVE,       /* Main process running / target satisfied */
    STATE_DEACTIVATING, /* Running ExecStop= */
    STATE_FAILED,       /* Crashed, backing off */
    STATE_DEAD,         /* Exited cleanly, won't restart (RESTART_NEVER) */
} ServiceState;

typedef enum {
    RESTART_ALWAYS = 0,
    RESTART_ON_FAILURE,
    RESTART_NEVER,
} RestartPolicy;

/* ── Service descriptor ───────────────────────────────────────────── */

struct service {
    /* Identity */
    char        name[64];
    ServiceType type;

    /* Execution */
    char exec[512];             /* Main Exec= command line */
    char exec_start_pre[512];   /* ExecStartPre= hook */
    char exec_stop[512];        /* ExecStop= hook */

    /* Dependency graph */
    char after[MAX_DEPS][64];   /* Start after these are ACTIVE */
    int  after_count;
    char requires[MAX_DEPS][64];/* Hard dep: fail us if dep fails */
    int  requires_count;
    char wants[MAX_DEPS][64];   /* Soft dep: start but ignore failure */
    int  wants_count;
    char part_of[64];           /* Stop when parent stops */

    /* Virtual targets this service satisfies when ACTIVE */
    char provides[MAX_PROVIDES][64];
    int  provides_count;

    /* Identity */
    char user[64];
    char group[64];

    /* Environment */
    char env[MAX_ENV][256];     /* key=value strings */
    int  env_count;
    char env_file[256];

    /* Socket activation */
    char listen_stream[256];    /* UNIX path for socket activation */
    int  listen_fd;             /* -1 = not socket-activated */

    /* Timer fields (type == TYPE_TIMER only) */
    long   on_boot_sec;         /* Seconds from boot to first fire */
    long   on_active_sec;       /* Repeat interval in seconds (0 = no repeat) */
    char   timer_unit[64];      /* Service to activate */
    time_t timer_next_fire;

    /* Restart policy */
    RestartPolicy restart;
    int    restart_count;
    time_t last_start;
    time_t next_restart;

    /* Runtime */
    pid_t pid;
    pid_t pre_pid;              /* ExecStartPre child pid */
    pid_t stop_pid;             /* ExecStop child pid */
    ServiceState state;

    /* Kahn's algorithm */
    int in_degree;              /* Unsatisfied After= dep count */
};

/* ── Global state ─────────────────────────────────────────────────── */
static struct service services[MAX_SERVICES];
static int service_count = 0;

static volatile sig_atomic_t g_running    = 1;
static volatile sig_atomic_t g_reboot     = 0;
static volatile sig_atomic_t g_poweroff   = 0;
static volatile sig_atomic_t g_child_exit = 0;

static int  control_fd  = -1;   /* UNIX socket listening fd */
static time_t boot_time  = 0;   /* Absolute boot timestamp */
static int  cgroup_v2   = 0;   /* 1 if cgroup v2 hierarchy found */

/* ── Forward declarations ─────────────────────────────────────────── */
static void log_msg(const char *level, const char *fmt, ...);
static pid_t do_spawn(const char *cmdline, struct service *sv, const char *log_tag);
static void  activate_service(int idx);
static void  notify_dependents(int idx);
static void  service_stop(int idx, int force);
static void  reap_children(void);
static void  handle_control_cmd(int client_fd);
static void  shutdown_system(int do_reboot);
static int   find_service(const char *name);
static void  launch_ready_services(void);

/* ════════════════════════════════════════════════════════════════════
 *  LOGGING
 * ════════════════════════════════════════════════════════════════════ */

static void log_msg(const char *level, const char *fmt, ...)
{
    va_list args;
    time_t  now;
    struct tm *ti;
    char tbuf[32], mbuf[1024];

    time(&now);
    ti = localtime(&now);
    strftime(tbuf, sizeof(tbuf), "%H:%M:%S", ti);

    va_start(args, fmt);
    vsnprintf(mbuf, sizeof(mbuf), fmt, args);
    va_end(args);

    fprintf(stderr, "[%s] au-init [%s]: %s\n", tbuf, level, mbuf);

    FILE *lf = fopen(INIT_LOG_FILE, "a");
    if (lf) {
        fprintf(lf, "[%s] au-init [%s]: %s\n", tbuf, level, mbuf);
        fclose(lf);
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  FILESYSTEM SETUP
 * ════════════════════════════════════════════════════════════════════ */

static int mount_filesystems(void)
{
    struct {
        const char *src, *tgt, *type;
        unsigned long flags;
        const char *opts;
    } mounts[] = {
        { "proc",     "/proc",    "proc",     MS_NOSUID|MS_NODEV|MS_NOEXEC, NULL },
        { "sysfs",    "/sys",     "sysfs",    MS_NOSUID|MS_NODEV|MS_NOEXEC, NULL },
        { "devtmpfs", "/dev",     "devtmpfs", MS_NOSUID,                    "mode=0755" },
        { "devpts",   "/dev/pts", "devpts",   MS_NOSUID|MS_NOEXEC,          "gid=5,mode=620" },
        { "tmpfs",    "/run",     "tmpfs",    MS_NOSUID|MS_NODEV,           "mode=0755" },
        { "tmpfs",    "/tmp",     "tmpfs",    MS_NOSUID|MS_NODEV,           "mode=1777" },
        { "tmpfs",    "/dev/shm", "tmpfs",    MS_NOSUID|MS_NODEV,           "mode=1777" },
    };
    const char *create_dirs[] = {
        "/dev/pts", "/run", "/tmp", "/dev/shm",
        "/var", "/var/log", "/var/run",
        NULL
    };

    log_msg("INFO", "Mounting essential filesystems...");

    for (int i = 0; create_dirs[i]; i++)
        mkdir(create_dirs[i], 0755);

    for (int i = 0; i < (int)(sizeof(mounts)/sizeof(mounts[0])); i++) {
        if (mount(mounts[i].src, mounts[i].tgt,
                  mounts[i].type, mounts[i].flags, mounts[i].opts) < 0) {
            if (errno != EBUSY)
                log_msg("WARN", "mount %s: %s", mounts[i].tgt, strerror(errno));
        } else {
            log_msg("INFO", "Mounted %s", mounts[i].tgt);
        }
    }

    /* Cgroup v2 — mount if available */
    mkdir("/sys/fs/cgroup", 0755);
    if (mount("cgroup2", "/sys/fs/cgroup", "cgroup2",
              MS_NOSUID|MS_NODEV|MS_NOEXEC, NULL) == 0) {
        mkdir(CGROUP_ROOT, 0755);
        cgroup_v2 = 1;
        log_msg("INFO", "cgroup v2 mounted — per-service isolation enabled");
    } else if (errno == EBUSY) {
        /* Already mounted (e.g. host has it) */
        mkdir(CGROUP_ROOT, 0755);
        cgroup_v2 = 1;
    } else {
        log_msg("INFO", "cgroup v2 not available — skipping isolation");
    }

    /* Loopback interface */
    {
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock >= 0) {
            struct ifreq ifr;
            memset(&ifr, 0, sizeof(ifr));
            strncpy(ifr.ifr_name, "lo", IFNAMSIZ - 1);
            if (ioctl(sock, SIOCGIFFLAGS, &ifr) == 0) {
                ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
                if (ioctl(sock, SIOCSIFFLAGS, &ifr) == 0)
                    log_msg("INFO", "Interface lo is up");
                else
                    log_msg("WARN", "lo up: %s", strerror(errno));
            }
            close(sock);
        }
    }
    return 0;
}

static void setup_hostname(void)
{
    char hn[128] = "aulinux";
    FILE *fp = fopen("/etc/hostname", "r");
    if (fp) {
        if (fgets(hn, sizeof(hn), fp))
            hn[strcspn(hn, "\r\n")] = '\0';
        fclose(fp);
    }
    if (sethostname(hn, strlen(hn)) < 0)
        log_msg("WARN", "sethostname: %s", strerror(errno));
    else
        log_msg("INFO", "Hostname: %s", hn);
}

static int setup_console(void)
{
    const char *devs[] = { "/dev/console", "/dev/tty1", NULL };
    for (int i = 0; devs[i]; i++) {
        int fd = open(devs[i], O_RDWR | O_NOCTTY);
        if (fd >= 0) {
            dup2(fd, STDIN_FILENO);
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
            if (fd > STDERR_FILENO) close(fd);
            log_msg("INFO", "Console: %s", devs[i]);
            return 0;
        }
    }
    return -1;
}

/* ════════════════════════════════════════════════════════════════════
 *  SIGNAL HANDLING
 * ════════════════════════════════════════════════════════════════════ */

static void signal_handler(int sig)
{
    switch (sig) {
        case SIGCHLD: g_child_exit = 1; break;
        case SIGTERM:
        case SIGINT:
        case SIGPWR:  g_running = 0; g_poweroff = 1; break;
        case SIGUSR1: g_running = 0; g_reboot   = 1; break;
        case SIGUSR2: g_running = 0; g_poweroff = 1; break;
        default: break;
    }
}

static void setup_signals(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;

    sigaction(SIGCHLD, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);
    sigaction(SIGUSR2, &sa, NULL);
    sigaction(SIGPWR,  &sa, NULL);

    signal(SIGHUP,  SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTTOU, SIG_IGN);
    signal(SIGTTIN, SIG_IGN);
}

/* ════════════════════════════════════════════════════════════════════
 *  CONFIG PARSER  — INI-style [ServiceName] sections
 * ════════════════════════════════════════════════════════════════════ */

/* Trim leading + trailing whitespace in-place, return pointer */
static char *strtrim(char *s)
{
    while (*s == ' ' || *s == '\t') s++;
    char *e = s + strlen(s);
    while (e > s && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\r' || e[-1] == '\n'))
        *--e = '\0';
    return s;
}

/* Add a string to a multi-value array */
static void add_dep(char arr[][64], int *count, const char *val)
{
    /* Support comma-separated values on one line */
    char tmp[256];
    strncpy(tmp, val, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';
    char *tok = strtok(tmp, ",");
    while (tok && *count < MAX_DEPS) {
        tok = strtrim(tok);
        if (*tok) strncpy(arr[(*count)++], tok, 63);
        tok = strtok(NULL, ",");
    }
}

static RestartPolicy parse_restart(const char *v)
{
    if (strcmp(v, "always")     == 0) return RESTART_ALWAYS;
    if (strcmp(v, "on-failure") == 0) return RESTART_ON_FAILURE;
    return RESTART_NEVER;
}

static ServiceType parse_type(const char *v)
{
    if (strcmp(v, "target")   == 0) return TYPE_TARGET;
    if (strcmp(v, "timer")    == 0) return TYPE_TIMER;
    if (strcmp(v, "oneshot")  == 0) return TYPE_ONESHOT;
    return TYPE_SIMPLE;
}

/* Parse "5m", "30s", "1h" → seconds */
static long parse_duration(const char *v)
{
    char *end;
    long n = strtol(v, &end, 10);
    if (*end == 'm') return n * 60;
    if (*end == 'h') return n * 3600;
    return n; /* assume seconds */
}

static void load_services(void)
{
    FILE *fp = fopen(SERVICE_CONFIG, "r");
    if (!fp) {
        log_msg("WARN", "Cannot open %s: %s", SERVICE_CONFIG, strerror(errno));
        return;
    }

    log_msg("INFO", "Loading services from %s", SERVICE_CONFIG);

    char line[1024];
    int cur = -1; /* current service index */

    while (fgets(line, sizeof(line), fp)) {
        char *s = strtrim(line);
        if (!*s || *s == '#') continue;

        /* ── Section header: [ServiceName] ── */
        if (*s == '[') {
            char *end = strchr(s, ']');
            if (!end) continue;
            *end = '\0';
            const char *sname = s + 1;

            if (service_count >= MAX_SERVICES) {
                log_msg("WARN", "MAX_SERVICES reached, ignoring %s", sname);
                cur = -1;
                continue;
            }
            cur = service_count++;
            struct service *sv = &services[cur];
            memset(sv, 0, sizeof(*sv));
            strncpy(sv->name, sname, sizeof(sv->name) - 1);
            sv->type         = TYPE_SIMPLE;
            sv->restart      = RESTART_ALWAYS;
            sv->listen_fd    = -1;
            sv->on_boot_sec  = -1;  /* not set */
            sv->on_active_sec = 0;
            continue;
        }

        if (cur < 0) continue;
        struct service *sv = &services[cur];

        /* ── Key=Value pair ── */
        char *eq = strchr(s, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = strtrim(s);
        char *val = strtrim(eq + 1);

        if      (!strcmp(key, "Type"))           sv->type = parse_type(val);
        else if (!strcmp(key, "Exec"))           strncpy(sv->exec, val, sizeof(sv->exec)-1);
        else if (!strcmp(key, "ExecStartPre"))   strncpy(sv->exec_start_pre, val, sizeof(sv->exec_start_pre)-1);
        else if (!strcmp(key, "ExecStop"))       strncpy(sv->exec_stop, val, sizeof(sv->exec_stop)-1);
        else if (!strcmp(key, "After"))          add_dep(sv->after,    &sv->after_count,    val);
        else if (!strcmp(key, "Requires"))       add_dep(sv->requires, &sv->requires_count, val);
        else if (!strcmp(key, "Wants"))          add_dep(sv->wants,    &sv->wants_count,    val);
        else if (!strcmp(key, "PartOf"))         strncpy(sv->part_of, val, sizeof(sv->part_of)-1);
        else if (!strcmp(key, "Provides")) {
            /* comma-separated list of virtual targets provided */
            char tmp[256];
            strncpy(tmp, val, sizeof(tmp)-1);
            char *tok = strtok(tmp, ",");
            while (tok && sv->provides_count < MAX_PROVIDES) {
                tok = strtrim(tok);
                if (*tok) strncpy(sv->provides[sv->provides_count++], tok, 63);
                tok = strtok(NULL, ",");
            }
        }
        else if (!strcmp(key, "User"))           strncpy(sv->user,  val, sizeof(sv->user)-1);
        else if (!strcmp(key, "Group"))          strncpy(sv->group, val, sizeof(sv->group)-1);
        else if (!strcmp(key, "Environment")) {
            if (sv->env_count < MAX_ENV)
                strncpy(sv->env[sv->env_count++], val, sizeof(sv->env[0])-1);
        }
        else if (!strcmp(key, "EnvironmentFile")) strncpy(sv->env_file, val, sizeof(sv->env_file)-1);
        else if (!strcmp(key, "ListenStream"))    strncpy(sv->listen_stream, val, sizeof(sv->listen_stream)-1);
        else if (!strcmp(key, "Restart"))         sv->restart = parse_restart(val);
        else if (!strcmp(key, "OnBootSec"))       sv->on_boot_sec = parse_duration(val);
        else if (!strcmp(key, "OnUnitActiveSec")) sv->on_active_sec = parse_duration(val);
        else if (!strcmp(key, "Unit"))            strncpy(sv->timer_unit, val, sizeof(sv->timer_unit)-1);
    }
    fclose(fp);
    log_msg("INFO", "Loaded %d service entries", service_count);
}

/* ════════════════════════════════════════════════════════════════════
 *  TOPOLOGY — Kahn's algorithm for parallel dependency-aware launch
 * ════════════════════════════════════════════════════════════════════ */

/* Return index of a service by name, -1 if not found.
 * Also checks the "provides" lists of all services. */
static int find_service(const char *name)
{
    for (int i = 0; i < service_count; i++) {
        if (strcmp(services[i].name, name) == 0) return i;
        /* Check provides array */
        for (int p = 0; p < services[i].provides_count; p++)
            if (strcmp(services[i].provides[p], name) == 0) return i;
    }
    return -1;
}

/* Compute in_degree for each service: count its After= deps that exist */
static void compute_in_degrees(void)
{
    for (int i = 0; i < service_count; i++) {
        services[i].in_degree = 0;
        services[i].state     = STATE_INACTIVE;
        services[i].timer_next_fire = 0;

        /* Initialise timer fire time */
        if (services[i].type == TYPE_TIMER && services[i].on_boot_sec >= 0)
            services[i].timer_next_fire = boot_time + services[i].on_boot_sec;

        for (int j = 0; j < services[i].after_count; j++) {
            if (find_service(services[i].after[j]) >= 0)
                services[i].in_degree++;
        }
    }
}

/* Called when service `idx` becomes ACTIVE.
 * Decrement in_degree of everything waiting on it (or its provides). */
static void notify_dependents(int idx)
{
    /* Collect all names this service satisfies */
    const char *satisfies[MAX_PROVIDES + 1];
    int sc = 0;
    satisfies[sc++] = services[idx].name;
    for (int p = 0; p < services[idx].provides_count; p++)
        satisfies[sc++] = services[idx].provides[p];

    for (int i = 0; i < service_count; i++) {
        if (i == idx) continue;
        for (int j = 0; j < services[i].after_count; j++) {
            for (int s = 0; s < sc; s++) {
                if (strcmp(services[i].after[j], satisfies[s]) == 0) {
                    services[i].in_degree--;
                    if (services[i].in_degree < 0) services[i].in_degree = 0;
                }
            }
        }
    }
}

/* Launch all services whose in_degree == 0 and state == INACTIVE */
static void launch_ready_services(void)
{
    for (int i = 0; i < service_count; i++) {
        if (services[i].state == STATE_INACTIVE && services[i].in_degree == 0) {
            activate_service(i);
        }
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  CGROUP v2 HELPERS
 * ════════════════════════════════════════════════════════════════════ */

static void cgroup_create(const char *name)
{
    if (!cgroup_v2) return;
    char path[256];
    snprintf(path, sizeof(path), "%s/%s", CGROUP_ROOT, name);
    mkdir(path, 0755);
}

static void cgroup_add_pid(const char *name, pid_t pid)
{
    if (!cgroup_v2) return;
    char path[256];
    snprintf(path, sizeof(path), "%s/%s/cgroup.procs", CGROUP_ROOT, name);
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%d\n", (int)pid); fclose(f); }
}

static void cgroup_remove(const char *name)
{
    if (!cgroup_v2) return;
    char path[640];
    snprintf(path, sizeof(path), "%.100s/%.64s", CGROUP_ROOT, name);
    rmdir(path);
}

/* ════════════════════════════════════════════════════════════════════
 *  SOCKET ACTIVATION
 * ════════════════════════════════════════════════════════════════════ */

/* Create a UNIX-domain listening socket for socket-activated services.
 * The fd is stored in sv->listen_fd and passed to the child as fd 3. */
static void setup_listen_socket(struct service *sv)
{
    if (!sv->listen_stream[0]) return;

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        log_msg("WARN", "[%s] socket(): %s", sv->name, strerror(errno));
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sv->listen_stream, sizeof(addr.sun_path) - 1);
    unlink(sv->listen_stream);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
        listen(fd, 128) < 0) {
        log_msg("WARN", "[%s] bind/listen %s: %s",
                sv->name, sv->listen_stream, strerror(errno));
        close(fd);
        return;
    }
    sv->listen_fd = fd;
    log_msg("INFO", "[%s] Socket activation ready: %s", sv->name, sv->listen_stream);
}

/* ════════════════════════════════════════════════════════════════════
 *  CONTROL SOCKET  (/run/auinit.sock)
 * ════════════════════════════════════════════════════════════════════ */

static void setup_control_socket(void)
{
    control_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (control_fd < 0) { log_msg("WARN", "control socket: %s", strerror(errno)); return; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, CONTROL_SOCK, sizeof(addr.sun_path) - 1);
    unlink(CONTROL_SOCK);

    if (bind(control_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
        listen(control_fd, 8) < 0) {
        log_msg("WARN", "control bind: %s", strerror(errno));
        close(control_fd); control_fd = -1;
        return;
    }
    chmod(CONTROL_SOCK, 0600);
    log_msg("INFO", "Control socket: %s", CONTROL_SOCK);
}

static const char *state_str(ServiceState st)
{
    switch (st) {
        case STATE_INACTIVE:    return "inactive";
        case STATE_WAITING:     return "waiting";
        case STATE_ACTIVATING:  return "activating";
        case STATE_ACTIVE:      return "active";
        case STATE_DEACTIVATING:return "deactivating";
        case STATE_FAILED:      return "failed";
        case STATE_DEAD:        return "dead";
        default:                return "unknown";
    }
}

static void ctl_send(int fd, const char *fmt, ...)
{
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0) { ssize_t _r = write(fd, buf, n); (void)_r; }
}

static void handle_control_cmd(int fd)
{
    char line[256] = {0};
    ssize_t n = read(fd, line, sizeof(line) - 1);
    if (n <= 0) return;
    line[n] = '\0';
    /* Strip newline */
    char *nl = strchr(line, '\n');
    if (nl) *nl = '\0';
    nl = strchr(line, '\r');
    if (nl) *nl = '\0';

    /* Split into verb + optional service name */
    char *verb = strtok(line, " \t");
    char *arg  = strtok(NULL, " \t");
    if (!verb) return;

    /* ── STATUS / LIST ── */
    if (!strcmp(verb, "STATUS") || !strcmp(verb, "LIST")) {
        if (arg) {
            int idx = find_service(arg);
            if (idx < 0) { ctl_send(fd, "ERR Service '%s' not found\n", arg); return; }
            struct service *sv = &services[idx];
            ctl_send(fd, "OK %s\n", sv->name);
            ctl_send(fd, "  State:    %s\n",  state_str(sv->state));
            ctl_send(fd, "  PID:      %d\n",  (int)sv->pid);
            ctl_send(fd, "  Restarts: %d\n",  sv->restart_count);
            ctl_send(fd, "  Type:     %s\n",
                     sv->type == TYPE_TARGET ? "target" :
                     sv->type == TYPE_TIMER  ? "timer"  :
                     sv->type == TYPE_ONESHOT? "oneshot" : "simple");
        } else {
            ctl_send(fd, "%-24s %-14s %s\n", "SERVICE", "STATE", "PID");
            for (int i = 0; i < service_count; i++) {
                ctl_send(fd, "%-24s %-14s %d\n",
                         services[i].name,
                         state_str(services[i].state),
                         (int)services[i].pid);
            }
        }
        return;
    }

    /* ── START ── */
    if (!strcmp(verb, "START")) {
        if (!arg) { ctl_send(fd, "ERR Usage: START <service>\n"); return; }
        int idx = find_service(arg);
        if (idx < 0) { ctl_send(fd, "ERR Service '%s' not found\n", arg); return; }
        if (services[idx].state == STATE_ACTIVE || services[idx].state == STATE_ACTIVATING) {
            ctl_send(fd, "OK %s is already %s\n", arg, state_str(services[idx].state));
            return;
        }
        services[idx].in_degree    = 0;
        services[idx].next_restart = 0;
        activate_service(idx);
        ctl_send(fd, "OK Starting %s (pid %d)\n", arg, (int)services[idx].pid);
        return;
    }

    /* ── STOP ── */
    if (!strcmp(verb, "STOP")) {
        if (!arg) { ctl_send(fd, "ERR Usage: STOP <service>\n"); return; }
        int idx = find_service(arg);
        if (idx < 0) { ctl_send(fd, "ERR Service '%s' not found\n", arg); return; }
        service_stop(idx, 0);
        ctl_send(fd, "OK Stopping %s\n", arg);
        return;
    }

    /* ── RESTART ── */
    if (!strcmp(verb, "RESTART")) {
        if (!arg) { ctl_send(fd, "ERR Usage: RESTART <service>\n"); return; }
        int idx = find_service(arg);
        if (idx < 0) { ctl_send(fd, "ERR Service '%s' not found\n", arg); return; }
        service_stop(idx, 0);
        services[idx].next_restart = time(NULL) + 1;
        services[idx].restart_count = 0;
        ctl_send(fd, "OK Restarting %s\n", arg);
        return;
    }

    /* ── SHUTDOWN / REBOOT ── */
    if (!strcmp(verb, "SHUTDOWN")) { g_running = 0; g_poweroff = 1; ctl_send(fd, "OK Shutting down\n"); return; }
    if (!strcmp(verb, "REBOOT"))   { g_running = 0; g_reboot   = 1; ctl_send(fd, "OK Rebooting\n");    return; }

    /* ── HELP ── */
    ctl_send(fd, "OK Commands: STATUS [svc] | LIST | START svc | STOP svc | RESTART svc | SHUTDOWN | REBOOT\n");
}

/* ════════════════════════════════════════════════════════════════════
 *  PROCESS SPAWNING
 * ════════════════════════════════════════════════════════════════════ */

/* Parse a command line string into argv[]. Returns argc, modifies buf in-place. */
static int parse_argv(char *buf, char *argv[], int maxargv)
{
    int argc = 0;
    char *p = buf;
    while (*p && argc < maxargv - 1) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        if (*p == '"') {
            p++;
            argv[argc++] = p;
            while (*p && *p != '"') p++;
            if (*p) *p++ = '\0';
        } else {
            argv[argc++] = p;
            while (*p && *p != ' ' && *p != '\t') p++;
            if (*p) *p++ = '\0';
        }
    }
    argv[argc] = NULL;
    return argc;
}

/* Load an EnvironmentFile into the service's env array */
static void load_env_file(struct service *sv)
{
    if (!sv->env_file[0]) return;
    FILE *f = fopen(sv->env_file, "r");
    if (!f) { log_msg("WARN", "[%s] EnvironmentFile %s: %s", sv->name, sv->env_file, strerror(errno)); return; }
    char line[256];
    while (fgets(line, sizeof(line), f) && sv->env_count < MAX_ENV) {
        char *s = strtrim(line);
        if (!*s || *s == '#') continue;
        strncpy(sv->env[sv->env_count++], s, sizeof(sv->env[0]) - 1);
    }
    fclose(f);
}

/* Fork and exec a command; returns pid or -1.
 * sv may be NULL for ad-hoc spawns (e.g. ExecStop). */
static pid_t do_spawn(const char *cmdline, struct service *sv, const char *log_tag)
{
    char buf[512];
    char *argv[64];
    strncpy(buf, cmdline, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    if (!parse_argv(buf, argv, 64) || !argv[0]) return -1;

    pid_t pid = fork();
    if (pid < 0) { log_msg("ERROR", "fork: %s", strerror(errno)); return -1; }
    if (pid > 0) return pid;

    /* ── Child ── */
    setsid();

    /* Redirect stdin to /dev/null for non-shell services */
    if (!sv || strcmp(sv->name, "shell") != 0) {
        int nfd = open("/dev/null", O_RDONLY);
        if (nfd >= 0) { dup2(nfd, STDIN_FILENO); close(nfd); }
    }

    /* Redirect stdout/stderr to per-service log */
    if (log_tag && strcmp(log_tag, "shell") != 0) {
        char lpath[256];
        snprintf(lpath, sizeof(lpath), "/var/log/%s.log", log_tag);
        int lfd = open(lpath, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (lfd >= 0) { dup2(lfd, STDOUT_FILENO); dup2(lfd, STDERR_FILENO); close(lfd); }
    }

    /* Socket activation: pass listen_fd as fd 3 */
    if (sv && sv->listen_fd >= 0) {
        if (sv->listen_fd != 3) {
            dup2(sv->listen_fd, 3);
            close(sv->listen_fd);
        }
        /* Set sd_listen_fds protocol env vars */
        char pidbuf[32];
        snprintf(pidbuf, sizeof(pidbuf), "%d", (int)getpid());
        setenv("LISTEN_PID",  pidbuf, 1);
        setenv("LISTEN_FDS",  "1",    1);
        setenv("LISTEN_FDNAMES", sv->listen_stream, 1);
    }

    /* Apply per-service environment */
    if (sv) {
        load_env_file(sv);
        for (int i = 0; i < sv->env_count; i++) {
            char *eq = strchr(sv->env[i], '=');
            if (eq) {
                *eq = '\0';
                setenv(sv->env[i], eq + 1, 1);
                *eq = '=';
            }
        }
        /* Apply User= / Group= */
        if (sv->group[0]) {
            struct group *gr = getgrnam(sv->group);
            if (gr && setgid(gr->gr_gid) < 0)
                fprintf(stderr, "au-init: setgid(%s): %s\n", sv->group, strerror(errno));
        }
        if (sv->user[0]) {
            struct passwd *pw = getpwnam(sv->user);
            if (pw) {
                if (setuid(pw->pw_uid) < 0)
                    fprintf(stderr, "au-init: setuid(%s): %s\n", sv->user, strerror(errno));
                if (!getenv("HOME")) setenv("HOME", pw->pw_dir, 1);
            }
        }
    }

    execvp(argv[0], argv);
    fprintf(stderr, "au-init: execvp(%s): %s\n", argv[0], strerror(errno));
    _exit(127);
}

/* ════════════════════════════════════════════════════════════════════
 *  SERVICE LIFECYCLE
 * ════════════════════════════════════════════════════════════════════ */

/* Activate a service: run ExecStartPre first (if set), then Exec */
static void activate_service(int idx)
{
    struct service *sv = &services[idx];

    /* Targets satisfy immediately */
    if (sv->type == TYPE_TARGET) {
        sv->state = STATE_ACTIVE;
        log_msg("INFO", "[%s] target reached", sv->name);
        notify_dependents(idx);
        launch_ready_services();
        return;
    }

    /* Timer: schedule next fire */
    if (sv->type == TYPE_TIMER) {
        sv->state = STATE_ACTIVE;
        if (sv->timer_next_fire == 0 && sv->on_boot_sec >= 0)
            sv->timer_next_fire = boot_time + sv->on_boot_sec;
        log_msg("INFO", "[%s] timer armed, fires at T+%lds",
                sv->name, (long)(sv->timer_next_fire - boot_time));
        return;
    }

    /* Create cgroup */
    cgroup_create(sv->name);

    /* Setup socket activation before fork */
    if (sv->listen_stream[0] && sv->listen_fd < 0)
        setup_listen_socket(sv);

    sv->last_start = time(NULL);

    if (sv->exec_start_pre[0]) {
        sv->state  = STATE_ACTIVATING;
        sv->pre_pid = do_spawn(sv->exec_start_pre, NULL, sv->name);
        if (sv->pre_pid > 0) {
            log_msg("INFO", "[%s] ExecStartPre running (pid %d)", sv->name, (int)sv->pre_pid);
            return; /* reap_children() will continue when pre exits */
        }
        /* pre failed to spawn — proceed anyway with a warning */
        log_msg("WARN", "[%s] ExecStartPre spawn failed", sv->name);
    }

    /* Launch main exec */
    sv->state = STATE_ACTIVE;
    sv->pid   = do_spawn(sv->exec, sv, sv->name);
    if (sv->pid <= 0) {
        sv->state = STATE_FAILED;
        log_msg("ERROR", "[%s] spawn failed", sv->name);
        return;
    }
    cgroup_add_pid(sv->name, sv->pid);
    log_msg("INFO", "[%s] started (pid %d)", sv->name, (int)sv->pid);

    /* Notify anything waiting on this service */
    notify_dependents(idx);
    launch_ready_services();
}

/* Stop a service (graceful: ExecStop → SIGTERM → SIGKILL) */
static void service_stop(int idx, int force)
{
    struct service *sv = &services[idx];
    if (sv->pid <= 0 && sv->state != STATE_ACTIVE) return;

    sv->state        = STATE_DEACTIVATING;
    sv->next_restart = 0;  /* Prevent auto-restart */

    if (!force && sv->exec_stop[0]) {
        sv->stop_pid = do_spawn(sv->exec_stop, NULL, sv->name);
        if (sv->stop_pid > 0) {
            log_msg("INFO", "[%s] ExecStop running (pid %d)", sv->name, (int)sv->stop_pid);
        }
    }

    if (sv->pid > 0) {
        kill(sv->pid, force ? SIGKILL : SIGTERM);
        log_msg("INFO", "[%s] sent %s (pid %d)", sv->name,
                force ? "SIGKILL" : "SIGTERM", (int)sv->pid);
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  CHILD REAPER
 * ════════════════════════════════════════════════════════════════════ */

static void reap_children(void)
{
    pid_t pid;
    int   status;
    time_t now = time(NULL);
    if (now <= 0) now = 1;

    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        /* Determine exit reason */
        int crashed  = 0;
        int exitcode = 0;
        if (WIFEXITED(status)) {
            exitcode = WEXITSTATUS(status);
            crashed  = (exitcode != 0);
        } else if (WIFSIGNALED(status)) {
            crashed  = 1;
            exitcode = 128 + WTERMSIG(status);
        }

        /* Match against service pre_pid, stop_pid, or main pid */
        for (int i = 0; i < service_count; i++) {
            struct service *sv = &services[i];

            /* ── ExecStartPre exited ── */
            if (sv->pre_pid == pid) {
                sv->pre_pid = 0;
                if (crashed) {
                    log_msg("WARN", "[%s] ExecStartPre failed (exit %d) — aborting start",
                            sv->name, exitcode);
                    sv->state        = STATE_FAILED;
                    sv->restart_count++;
                    int delay = 1 << (sv->restart_count < 6 ? sv->restart_count - 1 : 5);
                    sv->next_restart = now + delay;
                } else {
                    log_msg("INFO", "[%s] ExecStartPre ok — launching Exec", sv->name);
                    sv->state = STATE_ACTIVE;
                    sv->pid   = do_spawn(sv->exec, sv, sv->name);
                    if (sv->pid > 0) {
                        cgroup_add_pid(sv->name, sv->pid);
                        log_msg("INFO", "[%s] started (pid %d)", sv->name, (int)sv->pid);
                        notify_dependents(i);
                        launch_ready_services();
                    } else {
                        sv->state = STATE_FAILED;
                    }
                }
                goto next_pid;
            }

            /* ── ExecStop exited ── */
            if (sv->stop_pid == pid) {
                sv->stop_pid = 0;
                log_msg("INFO", "[%s] ExecStop finished", sv->name);
                goto next_pid;
            }

            /* ── Main process exited ── */
            if (sv->pid == pid) {
                sv->pid = 0;
                cgroup_remove(sv->name);

                if (crashed)
                    log_msg("WARN", "[%s] exited with code %d", sv->name, exitcode);
                else
                    log_msg("INFO", "[%s] exited cleanly", sv->name);

                /* Reset restart counter if service ran long enough */
                if (now - sv->last_start >= 30)
                    sv->restart_count = 0;

                /* Handle PartOf= — stop any service that is part of this one */
                for (int j = 0; j < service_count; j++) {
                    if (services[j].part_of[0] &&
                        strcmp(services[j].part_of, sv->name) == 0 &&
                        services[j].state == STATE_ACTIVE) {
                        log_msg("INFO", "[%s] stopping because PartOf=%s stopped",
                                services[j].name, sv->name);
                        service_stop(j, 0);
                    }
                }

                /* Handle Requires= — fail any service that hard-requires this one */
                if (crashed) {
                    for (int j = 0; j < service_count; j++) {
                        for (int r = 0; r < services[j].requires_count; r++) {
                            if (strcmp(services[j].requires[r], sv->name) == 0 &&
                                services[j].state == STATE_ACTIVE) {
                                log_msg("WARN", "[%s] stopping because Requires=%s failed",
                                        services[j].name, sv->name);
                                service_stop(j, 0);
                            }
                        }
                    }
                }

                /* Decide restart */
                int should_restart = 0;
                if (sv->restart == RESTART_ALWAYS)      should_restart = 1;
                if (sv->restart == RESTART_ON_FAILURE && crashed) should_restart = 1;
                /* Shell always restarts immediately */
                if (strcmp(sv->name, "shell") == 0)     { should_restart = 1; }

                if (should_restart) {
                    if (strcmp(sv->name, "shell") == 0) {
                        sv->restart_count = 0;
                        sv->next_restart  = now;
                        sv->state         = STATE_INACTIVE;
                    } else if (crashed) {
                        sv->restart_count++;
                        int delay = 1 << (sv->restart_count < 6 ? sv->restart_count - 1 : 5);
                        if (delay > 60) delay = 60;
                        sv->next_restart = now + delay;
                        sv->state        = STATE_FAILED;
                        log_msg("WARN", "[%s] crash restart in %ds (attempt %d)",
                                sv->name, delay, sv->restart_count);
                    } else {
                        sv->restart_count = 0;
                        sv->next_restart  = now + 1;
                        sv->state         = STATE_INACTIVE;
                    }
                } else {
                    sv->state = STATE_DEAD;
                    log_msg("INFO", "[%s] will not restart (policy: %s)",
                            sv->name,
                            sv->restart == RESTART_NEVER ? "never" : "on-failure (clean exit)");
                }
                goto next_pid;
            }
        }
        /* Unknown child (e.g. ExecStop subprocess) — silently reaped */
        next_pid:;
    }
    g_child_exit = 0;
}

/* ════════════════════════════════════════════════════════════════════
 *  TIMER ENGINE
 * ════════════════════════════════════════════════════════════════════ */

static void check_timers(time_t now)
{
    for (int i = 0; i < service_count; i++) {
        struct service *sv = &services[i];
        if (sv->type != TYPE_TIMER) continue;
        if (sv->state != STATE_ACTIVE) continue;
        if (sv->timer_next_fire <= 0 || now < sv->timer_next_fire) continue;

        /* Fire: activate the target unit */
        int tidx = find_service(sv->timer_unit);
        if (tidx >= 0) {
            log_msg("INFO", "[%s] timer firing → %s", sv->name, sv->timer_unit);
            services[tidx].in_degree    = 0;
            services[tidx].next_restart = 0;
            activate_service(tidx);
        }

        /* Schedule next fire */
        if (sv->on_active_sec > 0)
            sv->timer_next_fire = now + sv->on_active_sec;
        else
            sv->timer_next_fire = 0;  /* one-shot timer */
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  SHUTDOWN
 * ════════════════════════════════════════════════════════════════════ */

static void shutdown_system(int do_reboot)
{
    log_msg("INFO", do_reboot ? "Rebooting..." : "Shutting down...");

    /* Run ExecStop and send SIGTERM */
    for (int i = 0; i < service_count; i++) {
        if (services[i].pid > 0) {
            service_stop(i, 0);
        }
    }
    sleep(2);

    /* Reap exited children */
    int st;
    while (waitpid(-1, &st, WNOHANG) > 0) {}

    /* SIGKILL anything that survived */
    for (int i = 0; i < service_count; i++) {
        if (services[i].pid > 0 && kill(services[i].pid, 0) == 0) {
            kill(services[i].pid, SIGKILL);
            log_msg("WARN", "Force-killed %s (pid %d)",
                    services[i].name, (int)services[i].pid);
            services[i].pid = 0;
        }
    }

    /* Close control socket */
    if (control_fd >= 0) { close(control_fd); unlink(CONTROL_SOCK); }

    sync();
    umount2("/tmp",     MNT_DETACH);
    umount2("/run",     MNT_DETACH);
    umount2("/dev/shm", MNT_DETACH);
    umount2("/dev/pts", MNT_DETACH);
    umount2("/dev",     MNT_DETACH);
    umount2("/sys",     MNT_DETACH);
    umount2("/proc",    MNT_DETACH);
    sync();

    reboot(do_reboot ? RB_AUTOBOOT : RB_POWER_OFF);
}

/* ════════════════════════════════════════════════════════════════════
 *  MAIN
 * ════════════════════════════════════════════════════════════════════ */

int main(int argc, char *argv[])
{
    if (argc > 1) {
        if (!strcmp(argv[1], "--version"))
            { printf("au-init %s\n", AUINIT_VERSION); return 0; }
        if (!strcmp(argv[1], "--help"))
            { printf("AULinux init v%s\nSignals: SIGUSR1=reboot SIGUSR2=poweroff\n", AUINIT_VERSION); return 0; }
    }

    boot_time = time(NULL);
    pid_t my_pid = getpid();

    /* Boot banner */
    fprintf(stderr, "\n  ╔══════════════════════════════════════════╗\n");
    fprintf(stderr,   "  ║   AULinux au-init v%-8s              ║\n", AUINIT_VERSION);
    fprintf(stderr,   "  ║   Parallel | cgroup | Socket-activated  ║\n");
    fprintf(stderr,   "  ╚══════════════════════════════════════════╝\n\n");

    if (my_pid != 1)
        log_msg("WARN", "Not PID 1 (pid=%d) — running in test mode", (int)my_pid);
    else
        log_msg("INFO", "Starting as PID 1");

    /* Essential env */
    setenv("GOGC",      "50",    1);
    setenv("GOMEMLIMIT","512MiB",1);
    setenv("PATH",      "/bin:/sbin:/usr/bin:/usr/sbin", 1);

    setup_signals();

    if (my_pid == 1) {
        setup_console();
        mount_filesystems();
        setup_hostname();
        setup_control_socket();
    }

    log_msg("INFO", "System ready — loading service graph");

    /* Load + resolve dependency graph */
    load_services();
    compute_in_degrees();

    /* Parallel launch: start all services with no unsatisfied deps */
    log_msg("INFO", "Launching initial ready services...");
    launch_ready_services();

    /* Ensure shell is tracked (it may be in services.conf now) */
    if (find_service("shell") < 0) {
        /* Legacy: start shell if not declared in services.conf */
        if (service_count < MAX_SERVICES) {
            int idx = service_count++;
            struct service *sv = &services[idx];
            memset(sv, 0, sizeof(*sv));
            strcpy(sv->name, "shell");
            sv->type    = TYPE_SIMPLE;
            sv->restart = RESTART_ALWAYS;
            sv->listen_fd = -1;
            const char *sh = access(DEFAULT_SHELL, X_OK) == 0 ? DEFAULT_SHELL : FALLBACK_SHELL;
            snprintf(sv->exec, sizeof(sv->exec), "%s -l", sh);
            activate_service(idx);
        }
    }

    log_msg("INFO", "Entering supervision loop");

    /* ── Main supervision loop ── */
    while (g_running) {
        struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = 0;

        if (control_fd >= 0) {
            FD_SET(control_fd, &rfds);
            if (control_fd > maxfd) maxfd = control_fd;
        }

        select(maxfd + 1, &rfds, NULL, NULL, &tv);

        /* Reap dead children */
        if (g_child_exit) reap_children();

        /* Accept control command */
        if (control_fd >= 0 && FD_ISSET(control_fd, &rfds)) {
            int client = accept(control_fd, NULL, NULL);
            if (client >= 0) {
                /* Set a short read timeout */
                struct timeval rtv = { .tv_sec = 2, .tv_usec = 0 };
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &rtv, sizeof(rtv));
                handle_control_cmd(client);
                close(client);
            }
        }

        /* Fire timers */
        time_t now = time(NULL);
        if (now <= 0) now = 1;
        check_timers(now);

        /* Restart services due for restart */
        for (int i = 0; i < service_count; i++) {
            struct service *sv = &services[i];
            if (sv->pid == 0
                && sv->state != STATE_ACTIVATING
                && sv->state != STATE_ACTIVE
                && sv->state != STATE_DEAD
                && sv->next_restart > 0
                && now >= sv->next_restart) {
                sv->state        = STATE_INACTIVE;
                sv->next_restart = 0;
                sv->in_degree    = 0;
                activate_service(i);
            }
        }
    }

    shutdown_system(g_reboot ? 1 : 0);
    return 0;
}
