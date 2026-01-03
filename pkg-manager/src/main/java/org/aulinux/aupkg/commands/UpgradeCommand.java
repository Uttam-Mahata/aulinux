/**
 * Upgrade command - upgrades installed packages.
 */
package org.aulinux.aupkg.commands;

import java.util.List;

import org.aulinux.aupkg.core.PackageDatabase;
import org.aulinux.aupkg.model.Package;

public class UpgradeCommand implements Command {
    private boolean assumeYes = false;

    @Override
    public int execute(String[] args) throws Exception {
        // Parse arguments
        for (String arg : args) {
            if (arg.equals("-y") || arg.equals("--yes")) {
                assumeYes = true;
            }
        }

        PackageDatabase db = new PackageDatabase();
        db.loadInstalled();
        db.loadAvailable();

        List<Package> upgradable = db.findUpgradable();

        if (upgradable.isEmpty()) {
            System.out.println("All packages are up to date.");
            return 0;
        }

        // Show summary
        System.out.println("\nPackages to upgrade:");
        for (Package pkg : upgradable) {
            Package installed = db.getInstalled(pkg.getName());
            System.out.printf("  %s: %s -> %s\n", 
                pkg.getName(), installed.getVersion(), pkg.getVersion());
        }

        // Confirm
        if (!assumeYes) {
            System.out.print("\nProceed with upgrade? [y/N] ");
            int ch = System.in.read();
            if (ch != 'y' && ch != 'Y') {
                System.out.println("Upgrade cancelled.");
                return 0;
            }
        }

        // Upgrade packages
        System.out.println();
        for (Package pkg : upgradable) {
            System.out.printf("Upgrading %s to %s...\n", pkg.getName(), pkg.getVersion());
            db.addInstalled(pkg);
            System.out.printf("  Upgraded %s\n", pkg.getName());
        }

        db.saveInstalled();
        System.out.println("\nUpgrade complete.");
        return 0;
    }
}
