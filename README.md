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
- **Go**: Shell, core utilities (system tools)
- **Rust**: Package manager (complex application logic)

## Getting Started

### Prerequisites

- GCC (for C components)
- Go 1.21+
- Rust 1.70+
- Make

### Building

```bash
./scripts/build.sh
```

## Components

### Kernel (C)
Custom kernel modules and drivers for AULinux-specific features.

### Init System (C)
Lightweight init system managing services and system startup.

### Shell - aush (Go)
**A**bsolutely **U**nique **Sh**ell - Custom shell with modern features.

### Utilities (Go)
Core system utilities reimplemented in Go for safety and performance.

### Package Manager - aupkg (Rust)
Full-featured package manager with dependency resolution.


