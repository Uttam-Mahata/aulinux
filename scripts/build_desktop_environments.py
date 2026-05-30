#!/usr/bin/env python3
"""
build_desktop_environments.py
Automates building mock packages for GNOME and Plasma desktop environments,
compressing them into .tar.gz, saving them inside AULinux's rootfs packages repository,
and atomically merging their rich package metadata and dependencies into AULinux's repo.db.
"""

import os
import sys
import json
import shutil
import subprocess
import platform

# Define the file paths relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ROOTFS_DIR = os.path.join(PROJECT_ROOT, "rootfs")
REPO_DIR = os.path.join(ROOTFS_DIR, "var", "lib", "aupkg")
PACKAGES_DIR = os.path.join(REPO_DIR, "packages")
TMP_DIR = os.path.join(PROJECT_ROOT, "pkg_tmp_desktops")

# Check and create target directories in rootfs
os.makedirs(REPO_DIR, exist_ok=True)
os.makedirs(PACKAGES_DIR, exist_ok=True)

# Definition of the GNOME and KDE Plasma components to configure
PACKAGES_INFO = [
    # ------------------ GNOME STACK ------------------
    {
        "name": "glib",
        "version": "2.76.3",
        "description": "Low-level core library used by GNOME",
        "license": "LGPL-2.1-or-later",
        "dependencies": [],
        "files": {
            "usr/lib/libglib-2.0.so.0": "/* Mock GLib core library */\n",
            "usr/share/doc/glib/copyright": "Mock GLib license: LGPL-2.1\n"
        }
    },
    {
        "name": "dbus",
        "version": "1.14.8",
        "description": "Simple message bus system for software coordination",
        "license": "AFL-2.1",
        "dependencies": [],
        "files": {
            "usr/bin/dbus-daemon": (
                "#!/bin/sh\n"
                "echo '==========================================='\n"
                "echo '   AuLinux DBus - System Message Daemon    '\n"
                "echo '==========================================='\n"
                "echo 'System message bus daemon is running...'\n"
            ),
            "usr/lib/libdbus-1.so.3": "/* Mock DBus communication library */\n",
            "usr/share/doc/dbus/copyright": "Mock DBus license: AFL-2.1 or GPL-2.0\n"
        }
    },
    {
        "name": "mesa",
        "version": "23.1.3",
        "description": "Open-source OpenGL/Vulkan graphics driver stack",
        "license": "MIT",
        "dependencies": [],
        "files": {
            "usr/lib/libGL.so.1": "/* Mock OpenGL GLX library */\n",
            "usr/lib/libgbm.so.1": "/* Mock Generic Buffer Management library */\n",
            "usr/share/doc/mesa/copyright": "Mock Mesa license: MIT\n"
        }
    },
    {
        "name": "gnome",
        "version": "44.2",
        "description": "GNOME Desktop Environment Meta-Package",
        "license": "GPL-2.0-or-later",
        "dependencies": ["glib", "dbus", "mesa"],
        "files": {
            "usr/bin/gnome-session": (
                "#!/bin/sh\n"
                "echo '==========================================='\n"
                "echo '   AuLinux Desktop - GNOME Session Mock    '\n"
                "echo '==========================================='\n"
                "echo 'Initializing GNOME session components...'\n"
                "echo 'Loading DBus services, GLib runtimes, and Mesa 3D stacks...'\n"
                "echo 'Starting gnome-shell and GDM...'\n"
            ),
            "usr/bin/gnome-shell": (
                "#!/bin/sh\n"
                "echo 'gnome-shell: Running GNOME shell mock environment'\n"
            ),
            "usr/share/doc/gnome/copyright": "Mock GNOME license: GPL-2.0\n"
        }
    },
    # ------------------ KDE PLASMA STACK ------------------
    {
        "name": "qt5-base",
        "version": "5.15.10",
        "description": "KDE core framework application base library",
        "license": "LGPL-3.0-only",
        "dependencies": [],
        "files": {
            "usr/lib/libQt5Core.so.5": "/* Mock Qt5 Base Core library */\n",
            "usr/lib/libQt5Gui.so.5": "/* Mock Qt5 GUI component library */\n",
            "usr/share/doc/qt5-base/copyright": "Mock Qt5 license: LGPL-3.0\n"
        }
    },
    {
        "name": "kwin",
        "version": "5.27.6",
        "description": "KDE Plasma Window Manager",
        "license": "GPL-2.0-or-later",
        "dependencies": ["qt5-base", "mesa"],
        "files": {
            "usr/bin/kwin_x11": (
                "#!/bin/sh\n"
                "echo 'kwin_x11: Initializing KDE Window Manager over X11...'\n"
            ),
            "usr/bin/kwin_wayland": (
                "#!/bin/sh\n"
                "echo 'kwin_wayland: Initializing KDE Window Manager over Wayland...'\n"
            ),
            "usr/share/doc/kwin/copyright": "Mock KDE KWin license: GPL-2.0\n"
        }
    },
    {
        "name": "plasma-workspace",
        "version": "5.27.6",
        "description": "KDE Plasma Workspace suite",
        "license": "GPL-2.0-or-later",
        "dependencies": ["qt5-base", "dbus"],
        "files": {
            "usr/bin/startplasma-x11": (
                "#!/bin/sh\n"
                "echo 'startplasma-x11: Initializing KDE Plasma over X11...'\n"
            ),
            "usr/bin/startplasma-wayland": (
                "#!/bin/sh\n"
                "echo 'startplasma-wayland: Initializing KDE Plasma over Wayland...'\n"
            ),
            "usr/share/doc/plasma-workspace/copyright": "Mock Plasma Workspace license: GPL-2.0\n"
        }
    },
    {
        "name": "plasma",
        "version": "5.27.6",
        "description": "KDE Plasma Desktop Environment Meta-Package",
        "license": "GPL-2.0-or-later",
        "dependencies": ["qt5-base", "kwin", "plasma-workspace"],
        "files": {
            "usr/bin/startplasma": (
                "#!/bin/sh\n"
                "echo '==========================================='\n"
                "echo '   AuLinux Desktop - KDE Plasma Mock       '\n"
                "echo '==========================================='\n"
                "echo 'Starting KDE Plasma graphical user session...'\n"
                "echo 'Launching KWin window manager...'\n"
                "echo 'Loading Qt5 runtimes and workspace utilities...'\n"
            ),
            "usr/share/doc/plasma/copyright": "Mock KDE Plasma license: GPL-2.0\n"
        }
    }
]

def build_package(pkg_info):
    name = pkg_info["name"]
    version = pkg_info["version"]
    print(f"Building Desktop package: {name} ({version})...")

    # Path to stage this package
    pkg_src = os.path.join(TMP_DIR, name)
    if os.path.exists(pkg_src):
        shutil.rmtree(pkg_src)
    os.makedirs(pkg_src)

    # Create directories and files
    for rel_path, content in pkg_info["files"].items():
        file_path = os.path.join(pkg_src, rel_path)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "w") as f:
            f.write(content)
        
        # If the file is placed under usr/bin, make it executable
        if rel_path.startswith("usr/bin/"):
            os.chmod(file_path, 0o755)

    # Package into a .tar.gz archive
    archive_name = f"{name}-{version}.tar.gz"
    archive_path = os.path.join(PACKAGES_DIR, archive_name)

    # Execute tar to compress exactly the way other packaging scripts do
    subprocess.run(["tar", "-czf", archive_path, "."], cwd=pkg_src, check=True)

    # Calculate exact installed size in bytes (summing file sizes)
    total_size = 0
    for root, _, files in os.walk(pkg_src):
        for f in files:
            fp = os.path.join(root, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)

    # Cleanup staging directory
    shutil.rmtree(pkg_src)

    # Return constructed metadata
    return {
        "name": name,
        "version": version,
        "description": pkg_info["description"],
        "maintainer": "AuLinux Desktop Team",
        "architecture": platform.machine(),
        "installed_size": total_size,
        "dependencies": pkg_info["dependencies"],
        "optional_deps": [],
        "conflicts": [],
        "provides": [],
        "url": f"file:///var/lib/aupkg/packages/{archive_name}",
        "license": pkg_info["license"],
        "installed": False,
        "install_date": 0,
        "files": []
    }

def main():
    # Clean up staging directory if it exists, then recreate
    if os.path.exists(TMP_DIR):
        shutil.rmtree(TMP_DIR)
    os.makedirs(TMP_DIR)

    metadata_records = {}
    try:
        # Build all the GNOME and KDE Plasma packages
        for pkg_info in PACKAGES_INFO:
            record = build_package(pkg_info)
            metadata_records[pkg_info["name"]] = record
    finally:
        # Clean up temporary staging
        if os.path.exists(TMP_DIR):
            shutil.rmtree(TMP_DIR)

    # Load existing repo.db
    repo_db_path = os.path.join(REPO_DIR, "repo.db")
    db = {}
    if os.path.exists(repo_db_path):
        try:
            with open(repo_db_path, "r") as f:
                db = json.load(f)
            print(f"Loaded existing repo.db with {len(db)} entries.")
        except Exception as e:
            print(f"Warning: Failed to parse existing repo.db ({e}). Creating new repository database.")
            db = {}
    else:
        print("No existing repo.db found. Starting with a new database.")

    # Update metadata atomically
    for name, record in metadata_records.items():
        db[name] = record

    # Perform atomic write to prevent data corruption
    tmp_db_path = repo_db_path + ".tmp"
    try:
        with open(tmp_db_path, "w") as f:
            json.dump(db, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_db_path, repo_db_path)
        print(f"Atomic update complete. repo.db now contains {len(db)} packages.")
    except Exception as e:
        if os.path.exists(tmp_db_path):
            os.remove(tmp_db_path)
        print(f"Error: Atomic update failed! {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
