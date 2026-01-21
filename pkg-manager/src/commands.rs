use clap::{Parser, Subcommand};
use crate::config::Config;
use crate::db::PackageDatabase;

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
            println!("Installing packages: {:?}", packages);
            for pkg_name in packages {
                if db.is_installed(&pkg_name) {
                    println!("Package {} is already installed.", pkg_name);
                    continue;
                }

                let pkg_opt = db.get_available(&pkg_name).cloned();
                if let Some(pkg) = pkg_opt {
                    println!("Installing {}...", pkg.full_name());
                    // In a real implementation, we would download and extract here
                    db.add_installed(pkg.clone());
                    println!("Successfully installed {}.", pkg.name);
                } else {
                    println!("Package {} not found in repositories.", pkg_name);
                }
            }
            db.save_installed()?;
        }
        Commands::Remove { packages } => {
            println!("Removing packages: {:?}", packages);
             for pkg_name in packages {
                if !db.is_installed(&pkg_name) {
                    println!("Package {} is not installed.", pkg_name);
                    continue;
                }

                println!("Removing {}...", pkg_name);
                // In a real implementation, we would remove files here
                db.remove_installed(&pkg_name);
                println!("Successfully removed {}.", pkg_name);
            }
            db.save_installed()?;
        }
        Commands::Update => {
            println!("Updating package database...");
            // In a real implementation, this would download repo.db from mirrors
            println!("Package database updated.");
        }
        Commands::Upgrade => {
            println!("Upgrading installed packages...");
            // Logic to check versions and upgrade
            println!("System is up to date.");
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
            for pkg in db.installed_packages.values() {
                println!("{} {}", pkg.name, pkg.version);
            }
        }
    }

    Ok(())
}
