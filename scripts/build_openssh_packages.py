#!/usr/bin/env python3
"""
build_openssh_packages.py
Automates building mock package for openssh,
compressing it into .tar.gz, saving it inside AULinux's rootfs packages repository,
and atomically merging its rich package metadata into AULinux's repo.db.
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
TMP_DIR = os.path.join(PROJECT_ROOT, "pkg_tmp_openssh")

# Check and create target directories in rootfs
os.makedirs(REPO_DIR, exist_ok=True)
os.makedirs(PACKAGES_DIR, exist_ok=True)

def setup_openssh(pkg_src):
    usr_bin_dir = os.path.join(pkg_src, "usr", "bin")
    usr_sbin_dir = os.path.join(pkg_src, "usr", "sbin")
    os.makedirs(usr_bin_dir, exist_ok=True)
    os.makedirs(usr_sbin_dir, exist_ok=True)
    
    # Write ssh client script
    ssh_path = os.path.join(usr_bin_dir, "ssh")
    ssh_content = """#!/bin/sh
echo "OpenSSH_9.3p1 Mock Client"
echo "Usage: ssh [options] [user@]host [command]"
"""
    with open(ssh_path, "w") as f:
        f.write(ssh_content)
    os.chmod(ssh_path, 0o755)
    
    # Write sshd daemon script
    sshd_path = os.path.join(usr_sbin_dir, "sshd")
    sshd_content = """#!/bin/sh
echo "sshd: OpenSSH_9.3p1 Mock Daemon starting"
echo "Server listening on port 22."
"""
    with open(sshd_path, "w") as f:
        f.write(sshd_content)
    os.chmod(sshd_path, 0o755)

PACKAGES_INFO = [
    {
        "name": "openssh",
        "version": "9.3p1",
        "description": "Mock OpenSSH utilities",
        "license": "BSD",
        "maintainer": "AuLinux Networking Team",
        "dependencies": [],
        "setup_func": setup_openssh
    }
]

def build_package(pkg_info):
    name = pkg_info["name"]
    version = pkg_info["version"]
    print(f"Building OpenSSH package: {name} ({version})...")

    # Path to stage this package
    pkg_src = os.path.join(TMP_DIR, name)
    if os.path.exists(pkg_src):
        shutil.rmtree(pkg_src)
    os.makedirs(pkg_src)

    # Call setup function to create layout
    pkg_info["setup_func"](pkg_src)

    # Package into a .tar.gz archive
    archive_name = f"{name}-{version}.tar.gz"
    archive_path = os.path.join(PACKAGES_DIR, archive_name)

    # Execute tar to compress
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
        "maintainer": pkg_info["maintainer"],
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
        # Build all configured packages
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
