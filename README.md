# AULinux (Absolutely Unique Linux)

A custom Linux distribution built with C, Go, and Rust.

## Project Structure

```
AULinux/
├── kernel/          # C - Kernel modules and drivers
├── bootloader/      # C - Boot process and GRUB configuration
├── init/            # C - Init system (PID 1)
├── shell/           # Go - Custom shell (aush)
├── utils/           # Go - Core utilities (ls, cat, cp, etc.)
├── pkg-manager/     # Rust - Package manager (aupkg)
├── docs/            # Documentation
├── build/           # Build output
└── scripts/         # Build and automation scripts
```

## Language Distribution

- **C**: Kernel, bootloader, init system (low-level components)
- **Go**: Shell, core utilities (system tools, compiled into `auutils` multicall binary)
- **Rust**: Package manager (`aupkg` dependency and installer utility)

## Getting Started

### Prerequisites

- **QEMU** (specifically `qemu-system-x86_64`)
- **GCC** (for compiling C components)
- **Go 1.21+** (for Go utilities and custom shell)
- **Rust 1.70+** (with Cargo, for the package manager)
- **Make** & **cpio** (for kernel building and initramfs packaging)

### Building all Components

To compile all low-level, userland, shell, and package management components:
```bash
./scripts/build.sh all
```

### Verifying Build Integrity

To run the automated verification suite which performs host tests for the multicall tool, shell execution flags, and package manager databases:
```bash
./scripts/verify.sh
```

### Booting AULinux in QEMU

An automated, non-root QEMU direct kernel booting script is provided. It automatically compiles all components, generates the rootfs structure, dynamically obtains a bootable kernel (`vmlinuz`), packages the rootfs as a compressed `initramfs`, and launches it:
```bash
./scripts/run_qemu.sh
```

*   **Terminal Mode (Default)**: Redirects the serial console directly to your shell. **To exit QEMU, press `Ctrl+A` then `X`.**
*   **GUI Window Mode**: Launch QEMU in a separate graphical window using:
    ```bash
    ./scripts/run_qemu.sh --gui
    ```

### Building the Live Installation ISO

To create a bootable hybrid ISO (`build/aulinux.iso`) that can be flashed onto a USB drive or booted inside VM hypervisors (supporting both console and interactive graphical installation screens):
```bash
./scripts/build_iso.sh
```

> [!NOTE]
> The GitHub repository has an active GitHub Actions workflow configured under `.github/workflows/build-iso.yml` that compiles this ISO on every push and makes it available as a download.

### Installing Desktop Environments

Once booted into AULinux, you can use the built-in package manager `aupkg` to download and install full graphical desktop suites from the integrated repository:

*   **GNOME Desktop**:
    ```bash
    aupkg install gnome
    ```
*   **KDE Plasma Desktop**:
    ```bash
    aupkg install plasma
    ```


## Components

### Kernel (C)
Custom kernel modules and drivers for AULinux-specific features (sysctl interfaces, process monitoring).

### Init System (C)
Lightweight init system (`au-init`) managing system startup, mounts, service spawning, and orphan process reaping.

### Shell - aush (Go)
**A**bsolutely **U**nique **Sh**ell - Custom shell featuring built-in history, job control, cd/pwd, and background execution. Integrated as a space-saving entry point inside the multicall binary.

### Utilities (Go)
Core system utilities reimplemented in Go for safety and performance, running off a single symlinked multicall binary `auutils` (supporting `ls`, `cat`, `cp`, `mv`, `rm`, `chmod`, `echo`, etc.).

### Package Manager - aupkg (Rust)
Full-featured package manager written in Rust with dynamic mirror support, configuration parsing, archive extraction, and installation tracking.
