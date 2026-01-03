# AULinux Copilot Instructions

## Project Overview
AULinux is a custom Linux distribution with components written in three languages:
- **C**: Low-level system components (kernel modules, bootloader, init system)
- **Go**: User-space tools (shell `aush`, core utilities)
- **Java**: Package manager `aupkg` (Maven-based)

## Architecture & Component Boundaries

| Component | Language | Build System | Output Location |
|-----------|----------|--------------|-----------------|
| `kernel/` | C | Make | `build/kernel/` |
| `init/` | C (static linking) | Make | `build/init/au-init` |
| `shell/` | Go | Go modules | TBD |
| `utils/` | Go | Go modules (`github.com/aulinux/utils`) | TBD |
| `pkg-manager/` | Java 17 | Maven | `pkg-manager/target/` |

## Build Commands

```bash
# C components (from respective directories)
cd kernel && make        # Builds kernel modules as PIC objects
cd init && make          # Builds static init binary

# Java package manager
cd pkg-manager && mvn package    # Entry point: org.aulinux.aupkg.Main

# Go utilities
cd utils && go build ./...
```

## Language-Specific Conventions

### C Components
- Use `-Wall -Wextra -O2` compiler flags
- Kernel modules: Build as position-independent (`-fPIC`)
- Init system: Build as static binary (`-static`) for early boot
- Source files go in `src/` subdirectory within each component

### Go Components
- Module path: `github.com/aulinux/utils`
- Target Go version: 1.21+

### Java (pkg-manager)
- Group ID: `org.aulinux`
- Artifact: `aupkg`
- Dependencies: Gson (JSON), Commons Compress (archive handling)
- Main class: `org.aulinux.aupkg.Main`

## Key Design Decisions
1. **Static init binary**: The init system links statically to run before shared libraries are available
2. **Go for userspace**: Shell and utilities use Go for memory safety and simpler concurrency
3. **Java for package manager**: Leverages mature dependency resolution libraries

## File Organization
- Place new C source files in `<component>/src/`
- Build artifacts go to `build/<component>/` (not in source directories)
- Scripts for automation belong in `scripts/`
