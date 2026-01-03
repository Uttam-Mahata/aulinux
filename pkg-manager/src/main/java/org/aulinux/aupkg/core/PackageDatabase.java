/**
 * Package database management.
 */
package org.aulinux.aupkg.core;

import java.io.IOException;
import java.lang.reflect.Type;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.aulinux.aupkg.model.Package;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.reflect.TypeToken;

public class PackageDatabase {
    private Map<String, Package> installedPackages;
    private Map<String, Package> availablePackages;
    private Gson gson;
    private Config config;

    public PackageDatabase() {
        this.installedPackages = new HashMap<>();
        this.availablePackages = new HashMap<>();
        this.gson = new GsonBuilder().setPrettyPrinting().create();
        this.config = Config.getInstance();
    }

    /**
     * Load installed packages database
     */
    public void loadInstalled() throws IOException {
        Path dbPath = Paths.get(config.getLocalDbPath());
        if (!Files.exists(dbPath)) {
            return;
        }

        String json = Files.readString(dbPath);
        Type type = new TypeToken<Map<String, Package>>(){}.getType();
        Map<String, Package> loaded = gson.fromJson(json, type);
        if (loaded != null) {
            installedPackages = loaded;
            for (Package pkg : installedPackages.values()) {
                pkg.setInstalled(true);
            }
        }
    }

    /**
     * Save installed packages database
     */
    public void saveInstalled() throws IOException {
        Path dbDir = Paths.get(config.getDbDir());
        Files.createDirectories(dbDir);
        
        Path dbPath = Paths.get(config.getLocalDbPath());
        String json = gson.toJson(installedPackages);
        Files.writeString(dbPath, json);
    }

    /**
     * Load available packages from repository cache
     */
    public void loadAvailable() throws IOException {
        Path dbPath = Paths.get(config.getRepoDbPath());
        if (!Files.exists(dbPath)) {
            return;
        }

        String json = Files.readString(dbPath);
        Type type = new TypeToken<Map<String, Package>>(){}.getType();
        Map<String, Package> loaded = gson.fromJson(json, type);
        if (loaded != null) {
            availablePackages = loaded;
        }
    }

    /**
     * Check if a package is installed
     */
    public boolean isInstalled(String name) {
        return installedPackages.containsKey(name);
    }

    /**
     * Get installed package
     */
    public Package getInstalled(String name) {
        return installedPackages.get(name);
    }

    /**
     * Get available package
     */
    public Package getAvailable(String name) {
        return availablePackages.get(name);
    }

    /**
     * Get all installed packages
     */
    public Collection<Package> getAllInstalled() {
        return installedPackages.values();
    }

    /**
     * Get all available packages
     */
    public Collection<Package> getAllAvailable() {
        return availablePackages.values();
    }

    /**
     * Add package to installed
     */
    public void addInstalled(Package pkg) {
        pkg.setInstalled(true);
        pkg.setInstallDate(System.currentTimeMillis());
        installedPackages.put(pkg.getName(), pkg);
    }

    /**
     * Remove package from installed
     */
    public void removeInstalled(String name) {
        installedPackages.remove(name);
    }

    /**
     * Search packages
     */
    public List<Package> search(String keyword) {
        List<Package> results = new ArrayList<>();
        String lowerKeyword = keyword.toLowerCase();

        for (Package pkg : availablePackages.values()) {
            if (pkg.getName().toLowerCase().contains(lowerKeyword) ||
                (pkg.getDescription() != null && 
                 pkg.getDescription().toLowerCase().contains(lowerKeyword))) {
                // Mark as installed if applicable
                if (installedPackages.containsKey(pkg.getName())) {
                    pkg.setInstalled(true);
                }
                results.add(pkg);
            }
        }

        return results;
    }

    /**
     * Find packages that need upgrading
     */
    public List<Package> findUpgradable() {
        List<Package> upgradable = new ArrayList<>();

        for (Package installed : installedPackages.values()) {
            Package available = availablePackages.get(installed.getName());
            if (available != null && 
                compareVersions(available.getVersion(), installed.getVersion()) > 0) {
                upgradable.add(available);
            }
        }

        return upgradable;
    }

    /**
     * Simple version comparison
     */
    private int compareVersions(String v1, String v2) {
        String[] parts1 = v1.split("\\.");
        String[] parts2 = v2.split("\\.");
        
        int maxLen = Math.max(parts1.length, parts2.length);
        for (int i = 0; i < maxLen; i++) {
            int n1 = i < parts1.length ? parseVersionPart(parts1[i]) : 0;
            int n2 = i < parts2.length ? parseVersionPart(parts2[i]) : 0;
            if (n1 != n2) {
                return n1 - n2;
            }
        }
        return 0;
    }

    private int parseVersionPart(String part) {
        try {
            // Extract numeric prefix
            StringBuilder sb = new StringBuilder();
            for (char c : part.toCharArray()) {
                if (Character.isDigit(c)) {
                    sb.append(c);
                } else {
                    break;
                }
            }
            return sb.length() > 0 ? Integer.parseInt(sb.toString()) : 0;
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
