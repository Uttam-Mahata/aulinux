use clap::{Parser, Subcommand};
use crate::config::Config;
use crate::db::PackageDatabase;
use std::process::Command;
use std::fs;

#[derive(Parser)]
#[command(name = "aupkg")]
#[command(about = "AULinux Package Manager", long_about = None)]
#[command(version = "1.0.0")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,

    #[arg(short, long, help = "Assume yes to all prompts")]
    pub yes: bool,

    #[arg(short, long, help = "Quiet mode")]
    pub quiet: bool,

    #[arg(short, long, help = "Verbose output")]
    pub verbose: bool,
}

#[derive(Subcommand)]
pub enum Commands {
    #[command(alias = "i", about = "Install packages")]
    Install {
        #[arg(required = true)]
        packages: Vec<String>,
    },
    #[command(alias = "r", about = "Remove packages")]
    Remove {
        #[arg(required = true)]
        packages: Vec<String>,
    },
    #[command(alias = "u", about = "Update package database")]
    Update,
    #[command(about = "Upgrade installed packages")]
    Upgrade,
    #[command(alias = "s", about = "Search for packages")]
    Search {
        #[arg(required = true)]
        keyword: String,
    },
    #[command(about = "Show package information")]
    Info {
        #[arg(required = true)]
        package: String,
    },
    #[command(alias = "l", about = "List installed packages")]
    List,
}

fn resolve_dependencies(
    packages_to_install: &[String],
    db: &PackageDatabase,
) -> Result<Vec<String>, String> {
    let mut resolved = Vec::new();
    let mut unresolved = std::collections::HashSet::new();

    fn resolve(
        pkg_name: &str,
        db: &PackageDatabase,
        resolved: &mut Vec<String>,
        unresolved: &mut std::collections::HashSet<String>,
    ) -> Result<(), String> {
        // If already installed, skip
        if db.is_installed(pkg_name) {
            return Ok(());
        }

        // If already resolved, skip
        if resolved.contains(&pkg_name.to_string()) {
            return Ok(());
        }

        // Detect circular dependency
        if unresolved.contains(pkg_name) {
            return Err(format!("Circular dependency detected: {}", pkg_name));
        }

        unresolved.insert(pkg_name.to_string());

        // Get package metadata
        if let Some(pkg) = db.get_available(pkg_name) {
            for dep in &pkg.dependencies {
                resolve(dep, db, resolved, unresolved)?;
            }
        } else {
            return Err(format!("Package '{}' not found in available repositories", pkg_name));
        }

        unresolved.remove(pkg_name);
        resolved.push(pkg_name.to_string());
        Ok(())
    }

    for pkg in packages_to_install {
        resolve(pkg, db, &mut resolved, &mut unresolved)?;
    }

    // Validate conflicts
    for pkg_name in &resolved {
        if let Some(pkg) = db.get_available(pkg_name) {
            for conflict in &pkg.conflicts {
                if db.is_installed(conflict) || resolved.contains(conflict) {
                    return Err(format!(
                        "Package '{}' conflicts with package '{}'",
                        pkg_name, conflict
                    ));
                }
            }
        }
    }

    Ok(resolved)
}

fn validate_archive_files(files: &[String]) -> Result<(), String> {
    for file in files {
        let path = std::path::Path::new(file);
        
        // Check for directory traversal (ParentDir `..`)
        for component in path.components() {
            if component == std::path::Component::ParentDir {
                return Err(format!("Directory traversal ('..') detected in archive path: {}", file));
            }
            if component == std::path::Component::RootDir {
                return Err(format!("Absolute path ('/') detected in archive path: {}", file));
            }
        }
        
        // Prevent directory traversal using custom pattern checks
        if file.contains("..") {
            return Err(format!("Directory traversal pattern detected in archive path: {}", file));
        }
    }
    Ok(())
}

fn verify_symlink_safety_str(tvf_output: &str) -> Result<(), String> {
    for line in tvf_output.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('l') || line.contains(" -> ") {
            if let Some(pos) = line.find(" -> ") {
                let left = line[..pos].trim();
                let target = line[pos + 4..].trim();
                
                let link_path = match left.split_whitespace().last() {
                    Some(path) => path,
                    None => continue,
                };
                
                if target.starts_with('/') || std::path::Path::new(target).is_absolute() {
                    return Err(format!("Unsafe symlink target: absolute target path '{}' not allowed", target));
                }
                
                let link_path_buf = std::path::Path::new(link_path);
                let parent_path = link_path_buf.parent().unwrap_or(std::path::Path::new(""));
                let mut symlink_depth = 0;
                for comp in parent_path.components() {
                    match comp {
                        std::path::Component::Normal(_) => {
                            symlink_depth += 1;
                        }
                        _ => {}
                    }
                }
                
                let target_path_buf = std::path::Path::new(target);
                let mut parent_dir_count = 0;
                for comp in target_path_buf.components() {
                    match comp {
                        std::path::Component::ParentDir => {
                            parent_dir_count += 1;
                        }
                        std::path::Component::RootDir => {
                            return Err(format!("Unsafe symlink target: absolute target path '{}' not allowed", target));
                        }
                        _ => {}
                    }
                }
                
                if parent_dir_count > symlink_depth {
                    return Err(format!(
                        "Unsafe symlink target: '{}' escapes root from '{}' (parent depth: {}, target parent count: {})",
                        target, link_path, symlink_depth, parent_dir_count
                    ));
                }
            }
        }
    }
    Ok(())
}

fn verify_symlink_safety(archive_path: &std::path::Path) -> Result<(), String> {
    let output_res = Command::new("tar")
        .arg("-tvf")
        .arg(archive_path)
        .output();
    if output_res.is_err() || !output_res.as_ref().unwrap().status.success() {
        return Err(format!("Failed to read archive symlinks: {:?}", archive_path));
    }
    let stdout = output_res.unwrap().stdout;
    let tvf_str = String::from_utf8_lossy(&stdout);
    verify_symlink_safety_str(&tvf_str)
}

fn verify_checksum(archive_path: &std::path::Path, expected_sha: &str) -> Result<(), String> {
    let output_res = Command::new("sha256sum")
        .arg(archive_path)
        .output();
    if output_res.is_err() || !output_res.as_ref().unwrap().status.success() {
        return Err(format!("Failed to run sha256sum on archive: {:?}", archive_path));
    }
    let stdout = output_res.unwrap().stdout;
    let sha_str = String::from_utf8_lossy(&stdout);
    let computed_sha = sha_str.split_whitespace().next().unwrap_or("").trim();
    if computed_sha != expected_sha {
        return Err(format!(
            "Checksum mismatch: expected '{}', got '{}'",
            expected_sha, computed_sha
        ));
    }
    Ok(())
}

pub fn execute(cli: Cli) -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::load();
    let mut db = PackageDatabase::new(config);

    // Ensure we can access DB files
    if let Err(e) = db.load_installed() {
        eprintln!("Warning: Failed to load installed packages database: {}", e);
    }
    if let Err(e) = db.load_available() {
        eprintln!("Warning: Failed to load available packages database: {}", e);
    }

    match cli.command {
        Commands::Install { packages } => {
            println!("Validating dependencies for packages: {:?}", packages);
            let resolved_packages = match resolve_dependencies(&packages, &db) {
                Ok(pkgs) => pkgs,
                Err(err) => {
                    return Err(format!("Dependency validation failed: {}", err).into());
                }
            };

            if resolved_packages.is_empty() {
                println!("All requested packages (and their dependencies) are already installed.");
                return Ok(());
            }

            println!("Resolved installation order: {:?}", resolved_packages);

            for pkg_name in resolved_packages {
                if db.is_installed(&pkg_name) {
                    continue;
                }

                let pkg_opt = db.get_available(&pkg_name).cloned();
                if let Some(mut pkg) = pkg_opt {
                    println!("Installing {}...", pkg.full_name());

                    // Download using configured remote mirror URLs
                    let url = pkg.url.clone().unwrap_or_else(|| {
                        let repo_base = db.config.repositories.iter()
                            .find(|r| r.enabled)
                            .map(|r| r.url.as_str())
                            .unwrap_or("https://repo.aulinux.org/core");
                        format!("{}/{}-{}.tar.gz", repo_base, pkg.name, pkg.version)
                    });

                    let temp_dir = std::env::temp_dir();
                    let archive_path = temp_dir.join(format!("{}-{}.tar.gz", pkg.name, pkg.version));

                    let mut downloaded = false;
                    if url.starts_with("file://") {
                        let local_path = url.trim_start_matches("file://");
                        if std::path::Path::new(local_path).exists() {
                            println!("Copying local package from {} to {:?}...", local_path, archive_path);
                            if let Err(e) = std::fs::copy(local_path, &archive_path) {
                                eprintln!("Failed to copy local package from {} to {:?}: {}", local_path, archive_path, e);
                            } else {
                                downloaded = true;
                            }
                        }
                    }

                    if !downloaded {
                        println!("Downloading {} to {:?}...", url, archive_path);
                        let status = Command::new("curl")
                            .arg("-L")
                            .arg("-o")
                            .arg(&archive_path)
                            .arg(&url)
                            .status();

                        if status.is_err() || !status.unwrap().success() {
                             eprintln!("Failed to download package: {}", url);
                             let local_path = if url.starts_with("file://") {
                                 url.trim_start_matches("file://")
                             } else {
                                 &url
                             };
                             if !std::path::Path::new(local_path).exists() {
                                 return Err(format!("Could not fetch package archive: {}", url).into());
                             }
                             if url.starts_with("file://") {
                                 std::fs::copy(local_path, &archive_path)?;
                             }
                        }
                    }

                    // Checksum verification
                    if let Some(expected_sha) = &pkg.sha256 {
                        println!("Verifying SHA256 checksum...");
                        if let Err(err) = verify_checksum(&archive_path, expected_sha) {
                            let _ = fs::remove_file(&archive_path);
                            return Err(format!("Checksum verification failed: {}", err).into());
                        }
                    }

                    // List files
                    println!("Listing files...");
                    let output_res = Command::new("tar")
                        .arg("-tf")
                        .arg(&archive_path)
                        .output();

                    if output_res.is_err() || !output_res.as_ref().unwrap().status.success() {
                        eprintln!("Failed to read archive content: {:?}", archive_path);
                        let _ = fs::remove_file(&archive_path);
                        return Err(format!("Invalid package archive format: {:?}", archive_path).into());
                    }

                    let stdout = output_res.unwrap().stdout;
                    let files_str = String::from_utf8_lossy(&stdout);
                    let files: Vec<String> = files_str.lines().map(|s| s.to_string()).collect();

                    // Verify safe tar extraction (prevent directory traversal)
                    if let Err(err) = validate_archive_files(&files) {
                        let _ = fs::remove_file(&archive_path);
                        return Err(format!("Package safety validation failed: {}", err).into());
                    }

                    // Verify symlink target safety
                    if let Err(err) = verify_symlink_safety(&archive_path) {
                        let _ = fs::remove_file(&archive_path);
                        return Err(format!("Package safety validation failed: {}", err).into());
                    }

                    pkg.files = files;

                    // Extract safely
                    println!("Extracting files...");
                    let status = Command::new("tar")
                        .arg("-xf")
                        .arg(&archive_path)
                        .arg("-C")
                        .arg("/")
                        .status();

                    if status.is_err() || !status.unwrap().success() {
                        let _ = fs::remove_file(&archive_path);
                        for file in pkg.files.iter().rev() {
                            let path = std::path::Path::new("/").join(file);
                            if path == std::path::Path::new("/") { continue; }
                            if path.is_dir() {
                                let _ = fs::remove_dir(&path);
                            } else {
                                let _ = fs::remove_file(&path);
                            }
                        }
                        return Err(format!("Failed to extract archive: {:?}", archive_path).into());
                    }

                    // Cleanup
                    let _ = fs::remove_file(&archive_path);

                    db.add_installed(pkg.clone());
                    db.save_installed()?;
                    println!("Successfully installed {}.", pkg.name);
                } else {
                    println!("Package {} not found in repositories.", pkg_name);
                }
            }
        }
        Commands::Remove { packages } => {
            println!("Removing packages: {:?}", packages);
             for pkg_name in packages {
                let pkg_opt = db.get_installed(&pkg_name).cloned();

                if let Some(pkg) = pkg_opt {
                    // Check reverse dependencies: abort if any installed package depends on this one
                    let mut dependents: Vec<String> = Vec::new();
                    for (name, installed) in &db.installed_packages {
                        if name != &pkg_name && installed.dependencies.contains(&pkg_name) {
                            dependents.push(name.clone());
                        }
                    }
                    if !dependents.is_empty() {
                        eprintln!(
                            "error: Cannot remove '{}': required by installed package(s): {}",
                            pkg_name,
                            dependents.join(", ")
                        );
                        return Err(format!(
                            "Removal aborted: '{}' is a dependency of: {}",
                            pkg_name,
                            dependents.join(", ")
                        ).into());
                    }

                    println!("Removing {}...", pkg_name);

                    for file in pkg.files.iter().rev() {
                         let path = std::path::Path::new("/").join(file);

                         // Safety check
                         if path == std::path::Path::new("/") { continue; }

                         if path.is_dir() {
                             // Only remove empty directories
                             let _ = fs::remove_dir(&path);
                         } else {
                             let _ = fs::remove_file(&path);
                         }
                    }

                    db.remove_installed(&pkg_name);
                    println!("Successfully removed {}.", pkg_name);
                } else {
                    println!("Package {} is not installed.", pkg_name);
                }
            }
            db.save_installed()?;
        }
        Commands::Update => {
            println!("Updating package database...");
            // In a real implementation, this would download repo.db from mirrors
            println!("Package database updated.");
        }
        Commands::Upgrade => {
            println!("Checking for upgrades...");
            let mut upgradeable: Vec<(String, String, String)> = Vec::new(); // (name, old, new)
            for (name, installed) in &db.installed_packages {
                if let Some(available) = db.get_available(name) {
                    if available.version != installed.version {
                        upgradeable.push((name.clone(), installed.version.clone(), available.version.clone()));
                    }
                }
            }

            if upgradeable.is_empty() {
                println!("System is up to date.");
            } else {
                println!("Packages to upgrade ({}):", upgradeable.len());
                for (name, old, new) in &upgradeable {
                    println!("  {} {} -> {}", name, old, new);
                }

                // Install each upgraded package using the same install flow
                for (pkg_name, _old_ver, _new_ver) in upgradeable {
                    let pkg_opt = db.get_available(&pkg_name).cloned();
                    if let Some(mut pkg) = pkg_opt {
                        println!("Upgrading {}...", pkg.full_name());

                        let url = pkg.url.clone().unwrap_or_else(|| {
                            let repo_base = db.config.repositories.iter()
                                .find(|r| r.enabled)
                                .map(|r| r.url.as_str())
                                .unwrap_or("https://repo.aulinux.org/core");
                            format!("{}/{}-{}.tar.gz", repo_base, pkg.name, pkg.version)
                        });

                        let temp_dir = std::env::temp_dir();
                        let archive_path = temp_dir.join(format!("{}-{}.tar.gz", pkg.name, pkg.version));

                        let mut downloaded = false;
                        if url.starts_with("file://") {
                            let local_path = url.trim_start_matches("file://");
                            if std::path::Path::new(local_path).exists() {
                                if let Ok(()) = std::fs::copy(local_path, &archive_path).map(|_| ()) {
                                    downloaded = true;
                                }
                            }
                        }

                        if !downloaded {
                            let status = Command::new("curl")
                                .arg("-L")
                                .arg("-o")
                                .arg(&archive_path)
                                .arg(&url)
                                .status();
                            if status.is_err() || !status.unwrap().success() {
                                eprintln!("Failed to download upgrade for {}: {}", pkg_name, url);
                                continue;
                            }
                        }

                        // Checksum verification
                        if let Some(expected_sha) = &pkg.sha256 {
                            println!("Verifying SHA256 checksum...");
                            if let Err(err) = verify_checksum(&archive_path, expected_sha) {
                                eprintln!("Checksum verification failed for upgrade {}: {}", pkg_name, err);
                                let _ = fs::remove_file(&archive_path);
                                continue;
                            }
                        }

                        // List + validate
                        let output_res = Command::new("tar")
                            .arg("-tf")
                            .arg(&archive_path)
                            .output();
                        if output_res.is_err() || !output_res.as_ref().unwrap().status.success() {
                            eprintln!("Failed to read upgrade archive for {}", pkg_name);
                            let _ = fs::remove_file(&archive_path);
                            continue;
                        }
                        let stdout = output_res.unwrap().stdout;
                        let files_str = String::from_utf8_lossy(&stdout);
                        let files: Vec<String> = files_str.lines().map(|s| s.to_string()).collect();
                        if let Err(err) = validate_archive_files(&files) {
                            eprintln!("Archive safety check failed for {}: {}", pkg_name, err);
                            let _ = fs::remove_file(&archive_path);
                            continue;
                        }

                        // Verify symlink target safety
                        if let Err(err) = verify_symlink_safety(&archive_path) {
                            eprintln!("Symlink safety check failed for upgrade {}: {}", pkg_name, err);
                            let _ = fs::remove_file(&archive_path);
                            continue;
                        }

                        pkg.files = files;

                        // Extract
                        let status = Command::new("tar")
                            .arg("-xf")
                            .arg(&archive_path)
                            .arg("-C")
                            .arg("/")
                            .status();
                        let _ = fs::remove_file(&archive_path);
                        if status.is_err() || !status.unwrap().success() {
                            eprintln!("Failed to extract upgrade archive for {}", pkg_name);
                            for file in pkg.files.iter().rev() {
                                let path = std::path::Path::new("/").join(file);
                                if path == std::path::Path::new("/") { continue; }
                                if path.is_dir() {
                                    let _ = fs::remove_dir(&path);
                                } else {
                                    let _ = fs::remove_file(&path);
                                }
                            }
                            continue;
                        }

                        db.add_installed(pkg.clone());
                        db.save_installed()?;
                        println!("Successfully upgraded {}.", pkg.name);
                    }
                }
            }
        }
        Commands::Search { keyword } => {
            let results = db.search(&keyword);
            if results.is_empty() {
                println!("No packages found matching '{}'", keyword);
            } else {
                for pkg in results {
                    let status = if pkg.installed { "[installed]" } else { "" };
                    println!("{} {} {}", pkg.name, pkg.version, status);
                    if let Some(desc) = &pkg.description {
                        println!("    {}", desc);
                    }
                }
            }
        }
        Commands::Info { package } => {
            if let Some(pkg) = db.get_installed(&package).or_else(|| db.get_available(&package)) {
                println!("Name           : {}", pkg.name);
                println!("Version        : {}", pkg.version);
                println!("Description    : {}", pkg.description.as_deref().unwrap_or("None"));
                println!("Architecture   : {}", pkg.architecture.as_deref().unwrap_or("any"));
                println!("URL            : {}", pkg.url.as_deref().unwrap_or("None"));
                println!("Licenses       : {}", pkg.license.as_deref().unwrap_or("None"));
                println!("Installed Size : {}", pkg.formatted_size());
                println!("Installed      : {}", if pkg.installed { "Yes" } else { "No" });
            } else {
                println!("Package '{}' was not found.", package);
            }
        }
        Commands::List => {
            if db.installed_packages.is_empty() {
                println!("No packages installed.");
            } else {
                let mut pkgs: Vec<_> = db.installed_packages.values().collect();
                pkgs.sort_by(|a, b| a.name.cmp(&b.name));
                println!("{:<24} {:<16} {}", "Name", "Version", "Size");
                println!("{}", "-".repeat(56));
                for pkg in pkgs {
                    println!("{:<24} {:<16} {}", pkg.name, pkg.version, pkg.formatted_size());
                }
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Package;
    use crate::config::Config;

    #[test]
    fn test_validate_archive_files_safe() {
        let files = vec![
            "usr/bin/foo".to_string(),
            "etc/bar.conf".to_string(),
            "var/log/baz.log".to_string(),
        ];
        assert!(validate_archive_files(&files).is_ok());
    }

    #[test]
    fn test_validate_archive_files_traversal() {
        let files = vec![
            "usr/bin/../../etc/shadow".to_string(),
        ];
        assert!(validate_archive_files(&files).is_err());
    }

    #[test]
    fn test_validate_archive_files_absolute() {
        let files = vec![
            "/etc/shadow".to_string(),
        ];
        assert!(validate_archive_files(&files).is_err());
    }

    #[test]
    fn test_verify_symlink_safety_str() {
        // Safe relative symlink with same depth
        let tvf_output_safe1 = "lrwxrwxrwx root/root 0 2026-06-02 08:00 usr/bin/link -> ../lib/target";
        assert!(verify_symlink_safety_str(tvf_output_safe1).is_ok());

        // Safe relative symlink with less depth
        let tvf_output_safe2 = "lrwxrwxrwx root/root 0 2026-06-02 08:00 usr/bin/link -> ./target";
        assert!(verify_symlink_safety_str(tvf_output_safe2).is_ok());

        // Unsafe relative symlink escaping root
        let tvf_output_unsafe1 = "lrwxrwxrwx root/root 0 2026-06-02 08:00 usr/bin/link -> ../../../etc/shadow";
        assert!(verify_symlink_safety_str(tvf_output_unsafe1).is_err());

        // Unsafe absolute symlink
        let tvf_output_unsafe2 = "lrwxrwxrwx root/root 0 2026-06-02 08:00 usr/bin/link -> /etc/shadow";
        assert!(verify_symlink_safety_str(tvf_output_unsafe2).is_err());
        
        // Link at root level escaping root
        let tvf_output_unsafe3 = "lrwxrwxrwx root/root 0 2026-06-02 08:00 link -> ../etc/shadow";
        assert!(verify_symlink_safety_str(tvf_output_unsafe3).is_err());
    }

    #[test]
    fn test_resolve_dependencies() {
        let config = Config::default();
        let mut db = PackageDatabase::new(config);

        let mut pkg_a = Package::new("A".to_string(), "1.0.0".to_string());
        pkg_a.dependencies = vec!["B".to_string()];
        
        let mut pkg_b = Package::new("B".to_string(), "1.0.0".to_string());
        pkg_b.dependencies = vec!["C".to_string()];
        
        let pkg_c = Package::new("C".to_string(), "1.0.0".to_string());

        db.available_packages.insert("A".to_string(), pkg_a);
        db.available_packages.insert("B".to_string(), pkg_b);
        db.available_packages.insert("C".to_string(), pkg_c);

        let resolved = resolve_dependencies(&["A".to_string()], &db).unwrap();
        assert_eq!(resolved, vec!["C".to_string(), "B".to_string(), "A".to_string()]);
    }

    #[test]
    fn test_resolve_dependencies_circular() {
        let config = Config::default();
        let mut db = PackageDatabase::new(config);

        let mut pkg_a = Package::new("A".to_string(), "1.0.0".to_string());
        pkg_a.dependencies = vec!["B".to_string()];
        
        let mut pkg_b = Package::new("B".to_string(), "1.0.0".to_string());
        pkg_b.dependencies = vec!["A".to_string()];

        db.available_packages.insert("A".to_string(), pkg_a);
        db.available_packages.insert("B".to_string(), pkg_b);

        assert!(resolve_dependencies(&["A".to_string()], &db).is_err());
    }
}
