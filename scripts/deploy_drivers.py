#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
import re

def get_kernel_version():
    res = subprocess.run(["uname", "-r"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print("Error getting kernel version")
        sys.exit(1)
    return res.stdout.strip()

def normalize_name(name):
    # Strip extension (e.g., .ko, .ko.zst, .ko.xz)
    base = name.split(".ko")[0]
    # Replace _ with - to normalize
    return base.replace("_", "-")

def main():
    kernel_ver = get_kernel_version()
    print(f"Detected running kernel version: {kernel_ver}")

    host_modules_dir = f"/lib/modules/{kernel_ver}"
    if not os.path.exists(host_modules_dir):
        print(f"Host modules directory {host_modules_dir} not found!")
        sys.exit(1)

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    rootfs_dir = os.path.join(project_root, "rootfs")
    dest_modules_dir = os.path.join(rootfs_dir, "lib", "modules", kernel_ver)

    print(f"Destination modules directory: {dest_modules_dir}")

    # Step 1: Parse host modules.dep
    dep_file = os.path.join(host_modules_dir, "modules.dep")
    if not os.path.exists(dep_file):
        print(f"Host modules.dep not found at {dep_file}!")
        sys.exit(1)

    # We map normalized module name to its relative path on host
    # and also parse the dependencies
    mod_to_relpath = {}
    dependencies = {}

    with open(dep_file, "r") as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split(":")
            if len(parts) < 2:
                continue
            rel_path = parts[0].strip()
            deps_str = parts[1].strip()

            filename = os.path.basename(rel_path)
            norm_name = normalize_name(filename)

            mod_to_relpath[norm_name] = rel_path
            
            deps_list = []
            if deps_str:
                for dep in deps_str.split():
                    dep_filename = os.path.basename(dep)
                    deps_list.append(normalize_name(dep_filename))
            dependencies[norm_name] = deps_list

    # Print how many modules we parsed
    print(f"Parsed {len(mod_to_relpath)} modules from host modules.dep")

    # Step 2: Define target modules we want
    target_names = [
        # Audio
        "snd",
        "snd-pcm",
        "snd-timer",
        "snd-hwdep",
        "snd-hda-intel",
        "snd-hda-codec",
        "snd-intel8x0",
        "snd-pcsp",
        "soundcore",
        # Video/Graphics
        "virtio-gpu",
        "virtio_gpu",
        "drm",
        "drm-kms-helper",
        "drm_kms_helper",
        "i915",
        "amdgpu",
        "nouveau"
    ]

    # Let's also search for all other codecs and audio controllers, or any video drivers
    # that might match patterns like snd-*, hdmi, virtio-gpu, etc.
    additional_patterns = [
        r"^snd-.*",
        r"^soundcore.*",
        r"^drm.*",
        r"^i915.*",
        r"^amdgpu.*",
        r"^nouveau.*",
        r"^virtio-gpu.*",
        r"^virtio_gpu.*"
    ]

    matched_targets = set()
    for norm_name in mod_to_relpath.keys():
        # Check direct target names
        norm_target_names = [normalize_name(t) for t in target_names]
        if norm_name in norm_target_names:
            matched_targets.add(norm_name)
            continue
        
        # Check patterns
        for pattern in additional_patterns:
            if re.match(pattern, norm_name):
                matched_targets.add(norm_name)
                break

    print(f"Initially matched {len(matched_targets)} modules matching target names or patterns.")

    # Step 3: Recursively resolve dependencies to find the complete set of modules to copy
    to_copy = set()
    def resolve_deps(mod):
        if mod not in mod_to_relpath:
            return
        if mod in to_copy:
            return
        to_copy.add(mod)
        for dep in dependencies.get(mod, []):
            resolve_deps(dep)

    for mod in matched_targets:
        resolve_deps(mod)

    print(f"Resolved to a total of {len(to_copy)} modules (including all recursive dependencies).")

    # Step 4: Copy modules to rootfs and decompress if necessary
    os.makedirs(dest_modules_dir, exist_ok=True)

    copied_count = 0
    decompressed_count = 0

    for mod in sorted(to_copy):
        rel_path = mod_to_relpath[mod]
        src_path = os.path.join(host_modules_dir, rel_path)
        
        # Determine destination path in rootfs.
        # We replace the suffix with .ko if we decompress it.
        is_compressed = False
        decomp_cmd = None
        
        if rel_path.endswith(".zst"):
            is_compressed = True
            dest_rel_path = rel_path[:-4] # strip .zst
            decomp_cmd = ["zstd", "-d", "-f"]
        elif rel_path.endswith(".xz"):
            is_compressed = True
            dest_rel_path = rel_path[:-3] # strip .xz
            decomp_cmd = ["xz", "-d", "-f"]
        elif rel_path.endswith(".gz"):
            is_compressed = True
            dest_rel_path = rel_path[:-3] # strip .gz
            decomp_cmd = ["gzip", "-d", "-f"]
        else:
            dest_rel_path = rel_path

        dest_path = os.path.join(dest_modules_dir, dest_rel_path)
        dest_dir = os.path.dirname(dest_path)
        os.makedirs(dest_dir, exist_ok=True)

        if is_compressed:
            # Copy compressed file to dest_path + original extension first
            temp_dest = dest_path + os.path.splitext(rel_path)[1]
            shutil.copy2(src_path, temp_dest)
            
            # Decompress in-place
            res = subprocess.run(decomp_cmd + [temp_dest], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if res.returncode == 0:
                decompressed_count += 1
            else:
                print(f"Warning: failed to decompress {temp_dest}: {res.stderr.decode()}")
                # If decompression fails, just leave it as is
                if os.path.exists(temp_dest) and not os.path.exists(dest_path):
                    shutil.move(temp_dest, dest_path)
        else:
            shutil.copy2(src_path, dest_path)
        
        copied_count += 1

    print(f"Successfully copied {copied_count} modules into rootfs.")
    print(f"Decompressed {decompressed_count} compressed modules (.zst/.xz/.gz) to raw .ko format.")

    # Step 5: Run depmod in the rootfs directory
    print("Running depmod on rootfs...")
    # depmod -b <basedir> <version>
    depmod_res = subprocess.run(
        ["depmod", "-b", rootfs_dir, kernel_ver],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    if depmod_res.returncode == 0:
        print("depmod completed successfully!")
    else:
        print(f"Error running depmod: {depmod_res.stderr}")
        sys.exit(1)

    # Let's verify the files generated by depmod
    expected_files = ["modules.dep", "modules.alias", "modules.symbols"]
    for ef in expected_files:
        p = os.path.join(dest_modules_dir, ef)
        if os.path.exists(p):
            print(f"Verified: depmod generated {ef} successfully ({os.path.getsize(p)} bytes)")
        else:
            print(f"Warning: depmod map {ef} not found at {p}")

if __name__ == "__main__":
    main()
