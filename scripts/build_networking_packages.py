#!/usr/bin/env python3
"""
build_networking_packages.py
Automates building mock packages for busybox and dropbear,
compressing them into .tar.gz, saving them inside AULinux's rootfs packages repository,
and atomically merging their rich package metadata into AULinux's repo.db.
"""

import os
import sys
import json
import shutil
import subprocess
import platform as _platform

_gnu_triple = (subprocess.check_output(["gcc", "-dumpmachine"], text=True).strip()
               if subprocess.run(["which", "gcc"], capture_output=True).returncode == 0
               else {"x86_64": "x86_64-linux-gnu", "aarch64": "aarch64-linux-gnu",
                     "armv7l": "arm-linux-gnueabihf"}.get(_platform.machine(), "x86_64-linux-gnu"))

# Define the file paths relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ROOTFS_DIR = os.path.join(PROJECT_ROOT, "rootfs")
REPO_DIR = os.path.join(ROOTFS_DIR, "var", "lib", "aupkg")
PACKAGES_DIR = os.path.join(REPO_DIR, "packages")
TMP_DIR = os.path.join(PROJECT_ROOT, "pkg_tmp_networking")

# Check and create target directories in rootfs
os.makedirs(REPO_DIR, exist_ok=True)
os.makedirs(PACKAGES_DIR, exist_ok=True)

def setup_busybox(pkg_src):
    bin_dir = os.path.join(pkg_src, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    
    # Write busybox script
    busybox_path = os.path.join(bin_dir, "busybox")
    busybox_content = """#!/bin/sh
echo "BusyBox v1.36.1 (AULinux Mock Package)"
echo ""
echo "Currently defined functions:"
echo "	ifconfig, netstat, ping, route, wget"
"""
    with open(busybox_path, "w") as f:
        f.write(busybox_content)
    os.chmod(busybox_path, 0o755)

    # Write individual scripts for each command to make them run flawlessly line-by-line
    
    # ifconfig
    ifconfig_path = os.path.join(bin_dir, "ifconfig")
    ifconfig_content = """#!/bin/sh
echo "eth0      Link encap:Ethernet  HWaddr 52:54:00:12:34:56  "
echo "          inet addr:10.0.2.15  Bcast:10.0.2.255  Mask:255.255.255.0"
echo "          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1"
echo "          RX packets:42 errors:0 dropped:0 overruns:0 frame:0"
echo "          TX packets:24 errors:0 dropped:0 overruns:0 carrier:0"
echo "          collisions:0 txqueuelen:1000"
echo "          RX bytes:4200 (4.1 KiB)  TX bytes:2400 (2.3 KiB)"
echo ""
echo "lo        Link encap:Local Loopback  "
echo "          inet addr:127.0.0.1  Mask:255.0.0.0"
echo "          UP LOOPBACK RUNNING  MTU:65536  Metric:1"
echo "          RX packets:0 errors:0 dropped:0 overruns:0 frame:0"
echo "          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0"
echo "          collisions:0 txqueuelen:1000"
echo "          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)"
"""
    with open(ifconfig_path, "w") as f:
        f.write(ifconfig_content)
    os.chmod(ifconfig_path, 0o755)

    # ping
    ping_path = os.path.join(bin_dir, "ping")
    ping_content = """#!/bin/sh
echo "PING 127.0.0.1 (127.0.0.1): 56 data bytes"
echo "64 bytes from 127.0.0.1: seq=0 ttl=64 time=0.042 ms"
echo "64 bytes from 127.0.0.1: seq=1 ttl=64 time=0.038 ms"
echo ""
echo "--- 127.0.0.1 ping statistics ---"
echo "2 packets transmitted, 2 packets received, 0% packet loss"
echo "round-trip min/avg/max = 0.038/0.040/0.042 ms"
"""
    with open(ping_path, "w") as f:
        f.write(ping_content)
    os.chmod(ping_path, 0o755)

    # wget
    wget_path = os.path.join(bin_dir, "wget")
    wget_content = """#!/bin/sh
echo "Connecting to 127.0.0.1 (127.0.0.1:80)"
echo "writing to 'index.html'"
echo "index.html           100% |*******************************|  1024   0:00:00 ETA"
echo "'index.html' saved [1024/1024]"
"""
    with open(wget_path, "w") as f:
        f.write(wget_content)
    os.chmod(wget_path, 0o755)

    # netstat
    netstat_path = os.path.join(bin_dir, "netstat")
    netstat_content = """#!/bin/sh
echo "Active Internet connections (only servers)"
echo "Proto Recv-Q Send-Q Local Address           Foreign Address         State      "
echo "tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN     "
echo "tcp        0      0 127.0.0.1:80            0.0.0.0:*               LISTEN     "
echo "Active UNIX domain sockets (only servers)"
echo "Proto RefCnt Flags       Type       State         I-Node Path"
"""
    with open(netstat_path, "w") as f:
        f.write(netstat_content)
    os.chmod(netstat_path, 0o755)

    # route
    route_path = os.path.join(bin_dir, "route")
    route_content = """#!/bin/sh
echo "Kernel IP routing table"
echo "Destination     Gateway         Genmask         Flags Metric Ref    Use Iface"
echo "default         10.0.2.2        0.0.0.0         UG    0      0        0 eth0"
echo "10.0.2.0        *               255.255.255.0   U     0      0        0 eth0"
"""
    with open(route_path, "w") as f:
        f.write(route_content)
    os.chmod(route_path, 0o755)

def setup_dropbear(pkg_src):
    usr_bin_dir = os.path.join(pkg_src, "usr", "bin")
    usr_sbin_dir = os.path.join(pkg_src, "usr", "sbin")
    os.makedirs(usr_bin_dir, exist_ok=True)
    os.makedirs(usr_sbin_dir, exist_ok=True)
    
    # Write dbclient client script
    dbclient_path = os.path.join(usr_bin_dir, "dbclient")
    dbclient_content = """#!/bin/sh
echo "dbclient: Mock Dropbear SSH client v2024.84"
echo "Usage: dbclient [options] [user@]host [command]"
"""
    with open(dbclient_path, "w") as f:
        f.write(dbclient_content)
    os.chmod(dbclient_path, 0o755)
    
    # Write ssh client script
    ssh_path = os.path.join(usr_bin_dir, "ssh")
    ssh_content = """#!/bin/sh
echo "dbclient: Mock Dropbear SSH client v2024.84"
echo "Usage: dbclient [options] [user@]host [command]"
"""
    with open(ssh_path, "w") as f:
        f.write(ssh_content)
    os.chmod(ssh_path, 0o755)
    
    # Write dropbear server script
    dropbear_path = os.path.join(usr_sbin_dir, "dropbear")
    dropbear_content = """#!/bin/sh
echo "dropbear: Dropbear SSH server v2024.84 starting"
echo "[1234] May 30 08:36:13 mock-dropbear: listening on ':22'"
"""
    with open(dropbear_path, "w") as f:
        f.write(dropbear_content)
    os.chmod(dropbear_path, 0o755)
    
    # Write sshd script
    sshd_path = os.path.join(usr_sbin_dir, "sshd")
    sshd_content = """#!/bin/sh
echo "dropbear: Dropbear SSH server v2024.84 starting"
echo "[1234] May 30 08:36:13 mock-dropbear: listening on ':22'"
"""
    with open(sshd_path, "w") as f:
        f.write(sshd_content)
    os.chmod(sshd_path, 0o755)

def setup_dhcp_client(pkg_src):
    sbin_dir = os.path.join(pkg_src, "sbin")
    lib_dir = os.path.join(pkg_src, "lib")
    os.makedirs(sbin_dir, exist_ok=True)
    os.makedirs(lib_dir, exist_ok=True)
    
    # Locate host dhcpcd/dhclient
    dhcp_client_path = None
    for path in ["/usr/sbin/dhcpcd", "/sbin/dhcpcd", "/usr/sbin/dhclient", "/sbin/dhclient"]:
        if os.path.exists(path):
            dhcp_client_path = path
            break
            
    if dhcp_client_path:
        shutil.copy2(dhcp_client_path, os.path.join(sbin_dir, "dhcpcd"))
        # Copy dependencies
        for lib in [f"/usr/lib/{_gnu_triple}/libcrypto.so.3",
                    f"/usr/lib/{_gnu_triple}/libz.so.1",
                    f"/usr/lib/{_gnu_triple}/libzstd.so.1"]:
            if os.path.exists(lib):
                shutil.copy2(lib, lib_dir)
        # Also copy extra libraries for dhclient if that is what we found
        for lib in [f"/lib/{_gnu_triple}/libdns-export.so", f"/lib/{_gnu_triple}/libisc-export.so"]:
            import glob
            for f in glob.glob(lib + "*"):
                shutil.copy2(f, lib_dir)
    else:
        # Fallback to mock script if not found on host
        dhcp_path = os.path.join(sbin_dir, "dhcpcd")
        with open(dhcp_path, "w") as f:
            f.write("#!/bin/sh\necho 'Mock dhcpcd (Host DHCP client not found)'\n")
        os.chmod(dhcp_path, 0o755)

PACKAGES_INFO = [
    {
        "name": "busybox",
        "version": "1.36.1",
        "description": "BusyBox multicall binary providing simplified versions of many common UNIX utilities",
        "license": "GPL-2.0-only",
        "maintainer": "AuLinux Networking Team",
        "dependencies": [],
        "setup_func": setup_busybox
    },
    {
        "name": "dropbear",
        "version": "2024.84",
        "description": "Lightweight SSH server and client",
        "license": "MIT",
        "maintainer": "AuLinux Networking Team",
        "dependencies": [],
        "setup_func": setup_dropbear
    },
    {
        "name": "dhcp-client",
        "version": "10.3.0",
        "description": "Real dhcpcd DHCP client with dynamic dependencies",
        "license": "BSD-2-Clause",
        "maintainer": "AuLinux Networking Team",
        "dependencies": [],
        "setup_func": setup_dhcp_client
    }
]

def build_package(pkg_info):
    name = pkg_info["name"]
    version = pkg_info["version"]
    print(f"Building Networking package: {name} ({version})...")

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
        # Build all the networking packages
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

    # Invoke build_openssh_packages.py to integrate OpenSSH packages
    openssh_script = os.path.join(SCRIPT_DIR, "build_openssh_packages.py")
    if os.path.exists(openssh_script):
        print("Running build_openssh_packages.py to integrate OpenSSH packages...")
        try:
            subprocess.run([sys.executable, openssh_script], check=True)
        except Exception as e:
            print(f"Error: Failed to execute build_openssh_packages.py: {e}")
            sys.exit(1)

if __name__ == "__main__":
    main()
