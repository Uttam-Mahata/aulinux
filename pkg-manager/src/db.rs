use std::collections::HashMap;
use std::fs;
use std::path::Path;
use crate::model::Package;
use crate::config::Config;

pub struct PackageDatabase {
    pub installed_packages: HashMap<String, Package>,
    pub available_packages: HashMap<String, Package>,
    pub config: Config,
}

impl PackageDatabase {
    pub fn new(config: Config) -> Self {
        Self {
            installed_packages: HashMap::new(),
            available_packages: HashMap::new(),
            config,
        }
    }

    fn atomic_write<P: AsRef<Path>>(path: P, content: &str) -> std::io::Result<()> {
        let path = path.as_ref();
        let dir = path.parent().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::NotFound, "No parent directory found")
        })?;
        
        let tmp_path = dir.join(format!(
            "{}.tmp",
            path.file_name().ok_or_else(|| {
                std::io::Error::new(std::io::ErrorKind::InvalidInput, "Invalid file name")
            })?.to_string_lossy()
        ));
        
        fs::write(&tmp_path, content)?;
        
        // Explicitly sync file content to disk
        let file = fs::File::open(&tmp_path)?;
        file.sync_all()?;
        
        // Atomic replace
        fs::rename(tmp_path, path)?;
        Ok(())
    }

    pub fn load_installed(&mut self) -> std::io::Result<()> {
        let db_path = Config::get_local_db_path();
        if db_path.exists() {
            let content = fs::read_to_string(db_path)?;
            self.installed_packages = serde_json::from_str(&content)?;
            for pkg in self.installed_packages.values_mut() {
                pkg.installed = true;
            }
        }
        Ok(())
    }

    pub fn save_installed(&self) -> std::io::Result<()> {
        let db_dir = Config::get_db_dir();
        fs::create_dir_all(db_dir)?;
        let db_path = Config::get_local_db_path();
        let content = serde_json::to_string_pretty(&self.installed_packages)?;
        Self::atomic_write(db_path, &content)?;
        Ok(())
    }

    pub fn load_available(&mut self) -> std::io::Result<()> {
        let db_path = Config::get_repo_db_path();
        if db_path.exists() {
            let content = fs::read_to_string(db_path)?;
            self.available_packages = serde_json::from_str(&content)?;
        }
        Ok(())
    }

    // For testing/bootstrap, allow saving available packages
    #[allow(dead_code)]
    pub fn save_available(&self) -> std::io::Result<()> {
        let db_dir = Config::get_db_dir();
        fs::create_dir_all(db_dir)?;
        let db_path = Config::get_repo_db_path();
        let content = serde_json::to_string_pretty(&self.available_packages)?;
        Self::atomic_write(db_path, &content)?;
        Ok(())
    }

    pub fn is_installed(&self, name: &str) -> bool {
        self.installed_packages.contains_key(name)
    }

    pub fn get_installed(&self, name: &str) -> Option<&Package> {
        self.installed_packages.get(name)
    }

    pub fn get_available(&self, name: &str) -> Option<&Package> {
        self.available_packages.get(name)
    }

    pub fn add_installed(&mut self, mut pkg: Package) {
        pkg.installed = true;
        pkg.install_date = chrono::Utc::now().timestamp_millis();
        self.installed_packages.insert(pkg.name.clone(), pkg);
    }

    pub fn remove_installed(&mut self, name: &str) {
        self.installed_packages.remove(name);
    }

    pub fn search(&self, keyword: &str) -> Vec<Package> {
        let keyword_lower = keyword.to_lowercase();
        let mut results = Vec::new();

        for pkg in self.available_packages.values() {
            let match_name = pkg.name.to_lowercase().contains(&keyword_lower);
            let match_desc = pkg.description.as_ref().map(|d| d.to_lowercase().contains(&keyword_lower)).unwrap_or(false);

            if match_name || match_desc {
                let mut p = pkg.clone();
                if self.is_installed(&p.name) {
                    p.installed = true;
                }
                results.push(p);
            }
        }
        results
    }
}
