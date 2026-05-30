#!/usr/bin/env python3
"""
build_wayland_packages.py
Automates building mock packages for the Wayland graphics stack,
compressing them into .tar.gz, saving them inside AULinux's rootfs packages repository,
and atomically merging their rich package metadata and dependencies into AULinux's repo.db.
"""

import os
import sys
import json
import shutil
import subprocess

# Define the file paths relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ROOTFS_DIR = os.path.join(PROJECT_ROOT, "rootfs")
REPO_DIR = os.path.join(ROOTFS_DIR, "var", "lib", "aupkg")
PACKAGES_DIR = os.path.join(REPO_DIR, "packages")
TMP_DIR = os.path.join(PROJECT_ROOT, "pkg_tmp_wayland")

# Check and create target directories in rootfs
os.makedirs(REPO_DIR, exist_ok=True)
os.makedirs(PACKAGES_DIR, exist_ok=True)

# Definition of the Wayland graphics stack packages to configure
PACKAGES_INFO = [
    {
        "name": "libwayland",
        "version": "1.22.0",
        "description": "Wayland core library and protocol client",
        "license": "MIT",
        "dependencies": [],
        "files": {
            "usr/lib/libwayland-client.so.0": "/* Mock Wayland client shared library */\n",
            "usr/share/doc/libwayland/copyright": "Mock libwayland license: MIT\n"
        }
    },
    {
        "name": "wayland-protocols",
        "version": "1.32",
        "description": "Wayland protocol specifications",
        "license": "MIT",
        "dependencies": [],
        "files": {
            "usr/share/wayland-protocols/wayland.xml": (
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                "<protocol name=\"wayland\">\n"
                "  <!-- Mock wayland protocol description -->\n"
                "</protocol>\n"
            ),
            "usr/share/doc/wayland-protocols/copyright": "Mock wayland-protocols license: MIT\n"
        }
    },
    {
        "name": "weston",
        "version": "12.0.1",
        "description": "Reference Wayland compositor",
        "license": "MIT",
        "dependencies": ["libwayland", "libinput"],
        "files": {
            "usr/bin/weston": (
                "#!/bin/sh\n"
                "echo \"Weston v12.0.1 (AULinux Mock Graphics Stack)\"\n"
                "echo \"Running Weston Wayland Compositor...\"\n"
            ),
            "usr/share/doc/weston/copyright": "Mock weston license: MIT\n"
        }
    }
]


def build_package(pkg_info):
    name = pkg_info["name"]
    version = pkg_info["version"]
    print(f"Building Wayland stack package: {name} ({version})...")

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

    # Execute tar to compress exactly the way populate_graphics_repo.sh does
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
        "maintainer": "AuLinux Graphics Team",
        "architecture": "x86_64",
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
        # Build all the Wayland stack packages
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
