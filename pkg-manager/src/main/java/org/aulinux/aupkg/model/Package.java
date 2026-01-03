/**
 * Package model representing a software package.
 */
package org.aulinux.aupkg.model;

import java.util.ArrayList;
import java.util.List;

public class Package {
    private String name;
    private String version;
    private String description;
    private String maintainer;
    private String architecture;
    private long installedSize;
    private List<String> dependencies;
    private List<String> optionalDeps;
    private List<String> conflicts;
    private List<String> provides;
    private String url;
    private String license;
    private boolean installed;
    private long installDate;

    public Package() {
        this.dependencies = new ArrayList<>();
        this.optionalDeps = new ArrayList<>();
        this.conflicts = new ArrayList<>();
        this.provides = new ArrayList<>();
    }

    public Package(String name, String version) {
        this();
        this.name = name;
        this.version = version;
    }

    // Getters and setters
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getVersion() { return version; }
    public void setVersion(String version) { this.version = version; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getMaintainer() { return maintainer; }
    public void setMaintainer(String maintainer) { this.maintainer = maintainer; }

    public String getArchitecture() { return architecture; }
    public void setArchitecture(String architecture) { this.architecture = architecture; }

    public long getInstalledSize() { return installedSize; }
    public void setInstalledSize(long installedSize) { this.installedSize = installedSize; }

    public List<String> getDependencies() { return dependencies; }
    public void setDependencies(List<String> dependencies) { this.dependencies = dependencies; }

    public List<String> getOptionalDeps() { return optionalDeps; }
    public void setOptionalDeps(List<String> optionalDeps) { this.optionalDeps = optionalDeps; }

    public List<String> getConflicts() { return conflicts; }
    public void setConflicts(List<String> conflicts) { this.conflicts = conflicts; }

    public List<String> getProvides() { return provides; }
    public void setProvides(List<String> provides) { this.provides = provides; }

    public String getUrl() { return url; }
    public void setUrl(String url) { this.url = url; }

    public String getLicense() { return license; }
    public void setLicense(String license) { this.license = license; }

    public boolean isInstalled() { return installed; }
    public void setInstalled(boolean installed) { this.installed = installed; }

    public long getInstallDate() { return installDate; }
    public void setInstallDate(long installDate) { this.installDate = installDate; }

    /**
     * Get full package identifier (name-version)
     */
    public String getFullName() {
        return name + "-" + version;
    }

    /**
     * Format installed size for display
     */
    public String getFormattedSize() {
        if (installedSize < 1024) {
            return installedSize + " B";
        } else if (installedSize < 1024 * 1024) {
            return String.format("%.1f KiB", installedSize / 1024.0);
        } else {
            return String.format("%.1f MiB", installedSize / (1024.0 * 1024.0));
        }
    }

    @Override
    public String toString() {
        return name + " " + version + (installed ? " [installed]" : "");
    }
}
