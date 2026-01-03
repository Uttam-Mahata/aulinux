/**
 * Repository model representing a package repository.
 */
package org.aulinux.aupkg.model;

import java.util.ArrayList;
import java.util.List;

public class Repository {
    private String name;
    private String url;
    private boolean enabled;
    private long lastUpdate;
    private List<Package> packages;

    public Repository() {
        this.packages = new ArrayList<>();
        this.enabled = true;
    }

    public Repository(String name, String url) {
        this();
        this.name = name;
        this.url = url;
    }

    // Getters and setters
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getUrl() { return url; }
    public void setUrl(String url) { this.url = url; }

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public long getLastUpdate() { return lastUpdate; }
    public void setLastUpdate(long lastUpdate) { this.lastUpdate = lastUpdate; }

    public List<Package> getPackages() { return packages; }
    public void setPackages(List<Package> packages) { this.packages = packages; }

    /**
     * Find a package by name
     */
    public Package findPackage(String name) {
        for (Package pkg : packages) {
            if (pkg.getName().equals(name)) {
                return pkg;
            }
        }
        return null;
    }

    /**
     * Search packages by keyword
     */
    public List<Package> searchPackages(String keyword) {
        List<Package> results = new ArrayList<>();
        String lowerKeyword = keyword.toLowerCase();
        
        for (Package pkg : packages) {
            if (pkg.getName().toLowerCase().contains(lowerKeyword) ||
                (pkg.getDescription() != null && 
                 pkg.getDescription().toLowerCase().contains(lowerKeyword))) {
                results.add(pkg);
            }
        }
        
        return results;
    }

    @Override
    public String toString() {
        return name + " (" + url + ") - " + packages.size() + " packages";
    }
}
