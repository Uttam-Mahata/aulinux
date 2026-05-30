# AULinux Project Context

## Project Overview
AULinux (Absolutely Unique Linux) is a functioning custom Linux distribution that integrates components written in C, Go, and Rust.
*   **Goal**: Create a custom OS environment using a standard Linux kernel with a custom init system, system utilities, interactive shell, and packaging manager.
*   **Current Status**: All codebases (C, Go, Rust) are **fully implemented and verified to build and run**. A robust verification suite and unprivileged QEMU direct kernel bootrunner have been built and tested successfully.

---

## Directory Structure & Components

### 1. Kernel (`kernel/`)
*   **Language**: C
*   **Role**: Core OS features including process monitoring, custom sysctls, and core module logic.
*   **Build System**: `Makefile` (invokes `kbuild` using the host kernel header path).
*   **Status**: Source code exists (`kernel/src/`). Compiles kernel modules (`aulinux_core.ko`, `aulinux_sysctl.ko`, `aulinux_procmon.ko`) successfully inside the build workspace.

### 2. Init System (`init/`)
*   **Language**: C
*   **Role**: PID 1 system boot manager, mounting systems (`proc`, `sys`, `dev`, `run`), spawning shell, parsing services, and harvesting zombie processes.
*   **Build System**: `Makefile` (targets `src/init.c` producing a static `au-init` binary).
*   **Status**: Fully implemented at `init/src/init.c`. Compiles successfully.

### 3. Package Manager (`pkg-manager/`)
*   **Language**: Rust (Cargo)
*   **Role**: Custom package installer, updater, and search manager (`aupkg`).
*   **Build System**: Cargo (`Cargo.toml`).
*   **Status**: Fully functional at `pkg-manager/src/`. Compiles and saves metadata safely to local database files.

### 4. Utilities & Shell (`utils/` & `shell/`)
*   **Language**: Go (compiled in Go modules context)
*   **Role**: Bundles custom shell `aush` and core CLI utility replacements (e.g. `ls`, `cat`, `cp`, `chmod`, `echo`, `pwd`) into a single multicall binary (`auutils`).
*   **Status**: Fully implemented. Combines Go shell sources at `shell/shell.go` with command controllers inside `utils/cmd/` to build a link farm where symlinks trigger targeted tools.

---

## Build, Verify, & Run System

AULinux includes three central entry-point scripts in `scripts/`:

### 1. Build All Components
To compile all modules and build artifacts to `build/`:
```bash
./scripts/build.sh all
```

### 2. Run Local Verification
To execute the automated local test suite to verify binary behaviors before booting:
```bash
./scripts/verify.sh
```

### 3. Boot inside QEMU
To package the rootfs, fetch/download a kernel, and boot inside QEMU without requiring root permissions:
```bash
./scripts/run_qemu.sh
```
*   **Terminal Serial Mode (Default)**: Press **`Ctrl+A`** then **`X`** to terminate QEMU.
*   **GUI Window Mode**: Run `./scripts/run_qemu.sh --gui` to launch in a graphical window.

### 4. Build Bootable Live Installation ISO
To package the entire operating system, dynamically loader runtimes, package repositories, and local utilities into a bootable ISO image:
```bash
./scripts/build_iso.sh
```
*   **Outputs**: Generates a bootable hybrid ISO image `build/aulinux.iso` using GRUB (`grub-mkrescue` & `xorriso`).
*   **GitHub Actions CI**: A workflow `.github/workflows/build-iso.yml` is configured to build and publish this ISO automatically on every push or pull request as a downloadable artifact.

### 5. Interactive OS Installer Wizard
AULinux includes an interactive, easy-to-use installation wizard executable.
*   **Bootloader Option**: Select the "Install AULinux to Hard Disk" option from the GRUB boot menu to boot directly into the installer.
*   **Interactive Command**: Alternatively, run `install-os` (or `/bin/au-install`) directly from any active `aush` terminal in the Live environment to run the partition, format, filesystem copying, and boot sector installation simulation wizard.

### 6. Installing Desktop Environments (GNOME & Plasma)
AULinux's package manager `aupkg` includes pre-configured topological package definitions for modern graphical desktop suites:
*   **GNOME Suite**: Install GNOME and its core dependencies (`glib`, `dbus`, `mesa`):
    ```bash
    aupkg install gnome
    ```
*   **KDE Plasma Suite**: Install KDE Plasma and its core graphical/workspace dependencies (`qt5-base`, `kwin`, `plasma-workspace`):
    ```bash
    aupkg install plasma
    ```

