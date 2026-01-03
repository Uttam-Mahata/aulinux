/**
 * Remove command - removes installed packages.
 */
package org.aulinux.aupkg.commands;

import java.util.ArrayList;
import java.util.List;

import org.aulinux.aupkg.core.PackageDatabase;
import org.aulinux.aupkg.model.Package;

public class RemoveCommand implements Command {
    private boolean assumeYes = false;
    private boolean purge = false;

    @Override
    public int execute(String[] args) throws Exception {
        List<String> packages = new ArrayList<>();

        // Parse arguments
        for (String arg : args) {
            if (arg.equals("-y") || arg.equals("--yes")) {
                assumeYes = true;
            } else if (arg.equals("--purge")) {
                purge = true;
            } else if (!arg.startsWith("-")) {
                packages.add(arg);
            }
        }

        if (packages.isEmpty()) {
            System.err.println("aupkg remove: no packages specified");
            return 1;
        }

        PackageDatabase db = new PackageDatabase();
        db.loadInstalled();

        // Find packages to remove
        List<Package> toRemove = new ArrayList<>();
        for (String name : packages) {
            Package pkg = db.getInstalled(name);
            if (pkg == null) {
                System.err.println("aupkg: package '" + name + "' is not installed");
                return 1;
            }
            toRemove.add(pkg);
        }

        // Show summary
        System.out.println("\nPackages to remove:");
        for (Package pkg : toRemove) {
            System.out.printf("  %s-%s\n", pkg.getName(), pkg.getVersion());
        }

        // Confirm
        if (!assumeYes) {
            System.out.print("\nProceed with removal? [y/N] ");
            int ch = System.in.read();
            if (ch != 'y' && ch != 'Y') {
                System.out.println("Removal cancelled.");
                return 0;
            }
        }

        // Remove packages
        System.out.println();
        for (Package pkg : toRemove) {
            System.out.printf("Removing %s...\n", pkg.getName());
            
            // In a real implementation, this would:
            // 1. Run pre-remove scripts
            // 2. Remove installed files
            // 3. Run post-remove scripts
            // 4. Optionally remove config files (purge)
            
            db.removeInstalled(pkg.getName());
            System.out.printf("  Removed %s\n", pkg.getName());
        }

        db.saveInstalled();
        System.out.println("\nRemoval complete.");
        return 0;
    }
}
