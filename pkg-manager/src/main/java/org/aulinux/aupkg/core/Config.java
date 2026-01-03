/**
 * Configuration management for aupkg.
 */
package org.aulinux.aupkg.core;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

public class Config {
    private static final String CONFIG_DIR = "/etc/aulinux/aupkg";
    private static final String CONFIG_FILE = "aupkg.conf";
    private static final String REPOS_FILE = "repos.conf";
    private static final String CACHE_DIR = "/var/cache/aupkg";
    private static final String DB_DIR = "/var/lib/aupkg";

    private static Config instance;
    private Map<String, String> settings;
    private List<RepoEntry> repositories;
    private Gson gson;

    public static class RepoEntry {
        public String name;
        public String url;
        public boolean enabled = true;
    }

    private Config() {
        settings = new HashMap<>();
        repositories = new ArrayList<>();
        gson = new GsonBuilder().setPrettyPrinting().create();
        loadDefaults();
    }

    public static Config getInstance() {
        if (instance == null) {
            instance = new Config();
            instance.load();
        }
        return instance;
    }

    private void loadDefaults() {
        settings.put("architecture", System.getProperty("os.arch"));
        settings.put("parallel_downloads", "5");
        settings.put("check_space", "true");
        settings.put("verbose", "false");
        
        // Default repository
        RepoEntry core = new RepoEntry();
        core.name = "core";
        core.url = "https://repo.aulinux.org/core";
        repositories.add(core);
        
        RepoEntry extra = new RepoEntry();
        extra.name = "extra";
        extra.url = "https://repo.aulinux.org/extra";
        repositories.add(extra);
    }

    public void load() {
        try {
            Path configPath = Paths.get(CONFIG_DIR, CONFIG_FILE);
            if (Files.exists(configPath)) {
                Properties props = new Properties();
                props.load(Files.newBufferedReader(configPath));
                for (String key : props.stringPropertyNames()) {
                    settings.put(key, props.getProperty(key));
                }
            }
        } catch (IOException e) {
            System.err.println("Warning: Could not load config: " + e.getMessage());
        }
    }

    public void save() {
        try {
            Files.createDirectories(Paths.get(CONFIG_DIR));
            Path configPath = Paths.get(CONFIG_DIR, CONFIG_FILE);
            
            Properties props = new Properties();
            props.putAll(settings);
            props.store(Files.newBufferedWriter(configPath), "aupkg configuration");
        } catch (IOException e) {
            System.err.println("Warning: Could not save config: " + e.getMessage());
        }
    }

    public String get(String key) {
        return settings.get(key);
    }

    public String get(String key, String defaultValue) {
        return settings.getOrDefault(key, defaultValue);
    }

    public void set(String key, String value) {
        settings.put(key, value);
    }

    public boolean getBoolean(String key) {
        return "true".equalsIgnoreCase(settings.get(key));
    }

    public int getInt(String key, int defaultValue) {
        try {
            return Integer.parseInt(settings.get(key));
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public List<RepoEntry> getRepositories() {
        return repositories;
    }

    public String getCacheDir() {
        return CACHE_DIR;
    }

    public String getDbDir() {
        return DB_DIR;
    }

    public String getPackageCacheDir() {
        return CACHE_DIR + "/packages";
    }

    public String getRepoDbPath() {
        return DB_DIR + "/repo.db";
    }

    public String getLocalDbPath() {
        return DB_DIR + "/local.db";
    }
}
