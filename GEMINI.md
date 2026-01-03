# AULinux Project Context

## Project Overview
AULinux (Absolutely Unique Linux) is a custom Linux distribution project designed to integrate components written in C, Go, and Java.
- **Goal:** Create a functioning OS with a custom kernel, init system, shell, utilities, and package manager.
- **Current Status:** The project has **functional implementations** of all major components.

## Directory Structure & Components

### 1. Kernel (`kernel/`)
- **Language:** C
- **Role:** Core OS kernel modules and drivers.
- **Build System:** `Makefile` with Kbuild integration.
- **Status:** ✅ Implemented - 3 kernel modules:
  - `aulinux_core.c` - Core module with /proc/aulinux interface
  - `aulinux_sysctl.c` - Sysctl configuration at /proc/sys/aulinux/
  - `aulinux_procmon.c` - Process lifecycle monitor with kprobes

### 2. Init System (`init/`)
- **Language:** C
- **Role:** PID 1, system startup and service management.
- **Build System:** `Makefile` (static linking).
- **Status:** ✅ Implemented - Full init system with:
  - Filesystem mounting (proc, sys, dev, etc.)
  - Signal handling and process reaping
  - Shell launching
  - Shutdown/reboot handling

### 3. Package Manager (`pkg-manager/`)
- **Language:** Java 17 (Maven)
- **Role:** Dependency management and package installation (`aupkg`).
- **Build System:** Maven (`pom.xml`).
- **Artifact:** `org.aulinux:aupkg:1.0.0-SNAPSHOT`
- **Status:** ✅ Implemented - CLI with commands:
  - install, remove, update, upgrade, search, info, list

### 4. Utilities (`utils/`)
- **Language:** Go
- **Role:** Core system utilities reimplemented for safety.
- **Module:** `github.com/aulinux/utils`
- **Status:** ✅ Implemented - 8 utilities:
  - ls, cat, cp, mv, rm, mkdir, pwd, echo

### 5. Shell (`shell/`)
- **Language:** Go
- **Role:** Custom shell (`aush`).
- **Module:** `github.com/aulinux/shell`
- **Status:** ✅ Implemented - Full shell with:
  - Command parsing and execution
  - Builtins (cd, pwd, echo, export, history, etc.)
  - Pipes and redirections
  - Command history
  - Colored prompt

### 6. Scripts (`scripts/`)
- **Role:** Automation and build scripts.
- **Status:** ✅ `build.sh` - Builds all components.

## Build & Run Instructions

### Full Build
```bash
./scripts/build.sh
```

### Individual Components

#### Kernel Modules
```bash
cd kernel
make
# Output: ../build/kernel/*.ko
```

#### Init System
```bash
cd init
make
# Output: ../build/init/au-init
```

#### Package Manager
```bash
cd pkg-manager
mvn package
# Output: target/aupkg-1.0.0-SNAPSHOT.jar
```

#### Shell
```bash
cd shell
go build -o ../build/shell/aush .
```

#### Utilities
```bash
cd utils
go build -o ../build/utils/ ./cmd/...
```

## Development Conventions
- **Language Specialization:**
  - **C:** Low-level system components (Kernel, Init).
  - **Go:** System userland tools (Shell, Utils).
  - **Java:** Complex application logic (Package Manager).
- **Build Output:** Artifacts collected in `build/` directory.
- **Go Modules:** Use `github.com/aulinux/` prefix.
