# AULinux Kernel Modules Makefile
#
# Build kernel modules for AULinux-specific features.
# Supports both in-tree and out-of-tree builds.

# Module names
obj-m += aulinux_core.o
obj-m += aulinux_sysctl.o
obj-m += aulinux_procmon.o

# Compiler flags
ccflags-y := -Wall -Wextra -O2

# Directories
SRC_DIR := $(shell pwd)/src
BUILD_DIR := $(shell pwd)/../build/kernel
KDIR ?= /lib/modules/$(shell uname -r)/build

.PHONY: all modules clean install help

# Default target: build kernel modules
all: modules

# Build kernel modules using kbuild
modules: | $(BUILD_DIR)
	@echo "Building AULinux kernel modules..."
	$(MAKE) -C $(KDIR) M=$(SRC_DIR) modules
	@cp $(SRC_DIR)/*.ko $(BUILD_DIR)/ 2>/dev/null || true
	@echo "Modules built in $(BUILD_DIR)/"

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Clean build artifacts
clean:
	$(MAKE) -C $(KDIR) M=$(SRC_DIR) clean 2>/dev/null || true
	rm -rf $(BUILD_DIR)
	rm -f $(SRC_DIR)/*.o $(SRC_DIR)/*.ko $(SRC_DIR)/*.mod*
	rm -f $(SRC_DIR)/modules.order $(SRC_DIR)/Module.symvers

# Install modules to system
install: modules
	@echo "Installing AULinux kernel modules..."
	$(MAKE) -C $(KDIR) M=$(SRC_DIR) modules_install
	depmod -a

# Load modules for testing
load:
	@echo "Loading AULinux modules..."
	insmod $(BUILD_DIR)/aulinux_sysctl.ko
	insmod $(BUILD_DIR)/aulinux_core.ko
	insmod $(BUILD_DIR)/aulinux_procmon.ko

# Unload modules
unload:
	@echo "Unloading AULinux modules..."
	-rmmod aulinux_procmon
	-rmmod aulinux_core
	-rmmod aulinux_sysctl

# Show help
help:
	@echo "AULinux Kernel Modules Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build all kernel modules (default)"
	@echo "  modules  - Build kernel modules using kbuild"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Install modules to system (requires root)"
	@echo "  load     - Load modules for testing (requires root)"
	@echo "  unload   - Unload modules (requires root)"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  KDIR     - Kernel build directory (default: /lib/modules/$(uname -r)/build)"

