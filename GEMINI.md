# AULinux Project Context

## Project Overview
AULinux (Absolutely Unique Linux) is a custom Linux distribution project designed to integrate components written in C, Go, and Rust.
- **Goal:** Create a functioning OS with a custom kernel, init system, shell, utilities, and package manager.
- **Current Status:** The project currently appears to be a **skeleton or template**. While build configuration files (`Makefile`, `Cargo.toml`, `go.mod`) exist, the actual source code directories (`src/`, etc.) and implementation files are largely missing from the repository (except for `pkg-manager` which is implemented in Rust).

## Directory Structure & Components

### 1. Kernel (`kernel/`)
- **Language:** C
- **Role:** Core OS kernel modules and drivers.
- **Build System:** `Makefile` (targets `src/*.c`).
- **Status:** Makefile exists, but `src/` directory is missing.

### 2. Init System (`init/`)
- **Language:** C
- **Role:** PID 1, system startup and service management.
- **Build System:** `Makefile` (targets `src/init.c`).
- **Status:** Makefile exists, but `src/` directory is missing.

### 3. Package Manager (`pkg-manager/`)
- **Language:** Rust (Cargo)
- **Role:** Dependency management and package installation (`aupkg`).
- **Build System:** Cargo (`Cargo.toml`).
- **Status:** `Cargo.toml` exists. `src/` is populated.

### 4. Utilities (`utils/`)
- **Language:** Go
- **Role:** Core system utilities (ls, cp, cat) reimplemented for safety.
- **Module:** `github.com/aulinux/utils`
- **Status:** `go.mod` exists. No `.go` source files present.

### 5. Shell (`shell/`)
- **Language:** Go (intended)
- **Role:** Custom shell (`aush`).
- **Status:** Directory is empty.

### 6. Bootloader (`bootloader/`)
- **Language:** C (intended)
- **Role:** Boot process handling.
- **Status:** Directory is empty.

### 7. Scripts (`scripts/`)
- **Role:** Automation and build scripts.
- **Status:** Directory is empty. The `README.md` references a `scripts/build.sh` which is currently missing.

## Build & Run Instructions (Theoretical)

Since the `scripts/build.sh` is missing, components must be built individually. **Note:** These commands will currently fail due to missing source files.

### Kernel
```bash
cd kernel
make
# Intended output: ../build/kernel/*.o
```

### Init System
```bash
cd init
make
# Intended output: ../build/init/au-init
```

### Package Manager
```bash
cd pkg-manager
cargo build --release
# Intended output: target/release/aupkg
```

### Utilities
```bash
cd utils
go build ./...
```

## Development Conventions (Inferred)
- **Language Specialization:**
  - **C:** Low-level system components (Kernel, Init, Bootloader).
  - **Go:** System userland tools (Shell, Utils).
  - **Rust:** Complex application logic (Package Manager).
- **Build Output:** Build artifacts seem intended to be collected in a top-level `build/` directory (referenced in Makefiles).
