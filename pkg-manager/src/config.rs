use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RepoEntry {
    pub name: String,
    pub url: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Config {
    pub settings: HashMap<String, String>,
    pub repositories: Vec<RepoEntry>,
}

impl Default for Config {
    fn default() -> Self {
        let mut settings = HashMap::new();
        settings.insert("architecture".to_string(), std::env::consts::ARCH.to_string());
        settings.insert("parallel_downloads".to_string(), "5".to_string());
        settings.insert("check_space".to_string(), "true".to_string());
        settings.insert("verbose".to_string(), "false".to_string());

        let repositories = vec![
            RepoEntry {
                name: "core".to_string(),
                url: "https://repo.aulinux.org/core".to_string(),
                enabled: true,
            },
            RepoEntry {
                name: "extra".to_string(),
                url: "https://repo.aulinux.org/extra".to_string(),
                enabled: true,
            },
        ];

        Self {
            settings,
            repositories,
        }
    }
}

impl Config {
    const CONFIG_DIR: &'static str = "/etc/aulinux/aupkg";
    const CONFIG_FILE: &'static str = "aupkg.json";
    const CACHE_DIR: &'static str = "/var/cache/aupkg";
    const DB_DIR: &'static str = "/var/lib/aupkg";

    pub fn load() -> Self {
        let config_path = Path::new(Self::CONFIG_DIR).join(Self::CONFIG_FILE);
        if config_path.exists() {
            if let Ok(content) = fs::read_to_string(config_path) {
                if let Ok(config) = serde_json::from_str(&content) {
                    return config;
                }
            }
        }
        Self::default()
    }

    pub fn save(&self) -> std::io::Result<()> {
        fs::create_dir_all(Self::CONFIG_DIR)?;
        let config_path = Path::new(Self::CONFIG_DIR).join(Self::CONFIG_FILE);
        let content = serde_json::to_string_pretty(self)?;
        fs::write(config_path, content)?;
        Ok(())
    }

    pub fn get(&self, key: &str) -> Option<&String> {
        self.settings.get(key)
    }

    pub fn get_or(&self, key: &str, default: &str) -> String {
        self.settings.get(key).cloned().unwrap_or_else(|| default.to_string())
    }

    pub fn get_bool(&self, key: &str) -> bool {
        self.get(key).map(|v| v.to_lowercase() == "true").unwrap_or(false)
    }

    pub fn get_cache_dir() -> PathBuf {
        PathBuf::from(Self::CACHE_DIR)
    }

    pub fn get_db_dir() -> PathBuf {
        PathBuf::from(Self::DB_DIR)
    }

    pub fn get_repo_db_path() -> PathBuf {
        Self::get_db_dir().join("repo.db")
    }

    pub fn get_local_db_path() -> PathBuf {
        Self::get_db_dir().join("local.db")
    }
}
