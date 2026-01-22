use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Package {
    pub name: String,
    pub version: String,
    pub description: Option<String>,
    pub maintainer: Option<String>,
    pub architecture: Option<String>,
    #[serde(default)]
    pub installed_size: u64,
    #[serde(default)]
    pub dependencies: Vec<String>,
    #[serde(default)]
    pub optional_deps: Vec<String>,
    #[serde(default)]
    pub conflicts: Vec<String>,
    #[serde(default)]
    pub provides: Vec<String>,
    pub url: Option<String>,
    pub license: Option<String>,
    #[serde(default)]
    pub installed: bool,
    #[serde(default)]
    pub install_date: i64,
}

impl Package {
    pub fn new(name: String, version: String) -> Self {
        Self {
            name,
            version,
            description: None,
            maintainer: None,
            architecture: None,
            installed_size: 0,
            dependencies: vec![],
            optional_deps: vec![],
            conflicts: vec![],
            provides: vec![],
            url: None,
            license: None,
            installed: false,
            install_date: 0,
        }
    }

    pub fn full_name(&self) -> String {
        format!("{}-{}", self.name, self.version)
    }

    pub fn formatted_size(&self) -> String {
        if self.installed_size < 1024 {
            format!("{} B", self.installed_size)
        } else if self.installed_size < 1024 * 1024 {
            format!("{:.1} KiB", self.installed_size as f64 / 1024.0)
        } else {
            format!("{:.1} MiB", self.installed_size as f64 / (1024.0 * 1024.0))
        }
    }
}
