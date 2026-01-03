/**
 * Info command - shows package information.
 */
package org.aulinux.aupkg.commands;

import java.text.SimpleDateFormat;
import java.util.Date;

import org.aulinux.aupkg.core.PackageDatabase;
import org.aulinux.aupkg.model.Package;

public class InfoCommand implements Command {
    @Override
    public int execute(String[] args) throws Exception {
        if (args.length == 0) {
            System.err.println("aupkg info: no package specified");
            return 1;
        }

        String name = args[0];

        PackageDatabase db = new PackageDatabase();
        db.loadInstalled();
        db.loadAvailable();

        // Try installed first, then available
        Package pkg = db.getInstalled(name);
        if (pkg == null) {
            pkg = db.getAvailable(name);
        }

        if (pkg == null) {
            System.err.println("aupkg: package '" + name + "' not found");
            return 1;
        }

        // Display package info
        System.out.println();
        System.out.printf("Name           : %s\n", pkg.getName());
        System.out.printf("Version        : %s\n", pkg.getVersion());
        
        if (pkg.getDescription() != null) {
            System.out.printf("Description    : %s\n", pkg.getDescription());
        }
        if (pkg.getArchitecture() != null) {
            System.out.printf("Architecture   : %s\n", pkg.getArchitecture());
        }
        if (pkg.getUrl() != null) {
            System.out.printf("URL            : %s\n", pkg.getUrl());
        }
        if (pkg.getLicense() != null) {
            System.out.printf("License        : %s\n", pkg.getLicense());
        }
        if (pkg.getMaintainer() != null) {
            System.out.printf("Maintainer     : %s\n", pkg.getMaintainer());
        }
        
        System.out.printf("Installed Size : %s\n", pkg.getFormattedSize());
        
        if (!pkg.getDependencies().isEmpty()) {
            System.out.printf("Dependencies   : %s\n", 
                String.join(", ", pkg.getDependencies()));
        }
        if (!pkg.getOptionalDeps().isEmpty()) {
            System.out.printf("Optional Deps  : %s\n", 
                String.join(", ", pkg.getOptionalDeps()));
        }
        
        System.out.printf("Installed      : %s\n", pkg.isInstalled() ? "Yes" : "No");
        
        if (pkg.isInstalled() && pkg.getInstallDate() > 0) {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
            System.out.printf("Install Date   : %s\n", 
                sdf.format(new Date(pkg.getInstallDate())));
        }

        System.out.println();
        return 0;
    }
}
