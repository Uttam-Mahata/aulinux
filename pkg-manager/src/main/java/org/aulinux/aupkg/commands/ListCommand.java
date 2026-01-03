/**
 * List command - lists installed packages.
 */
package org.aulinux.aupkg.commands;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;

import org.aulinux.aupkg.core.PackageDatabase;
import org.aulinux.aupkg.model.Package;

public class ListCommand implements Command {
    @Override
    public int execute(String[] args) throws Exception {
        boolean showAll = false;
        boolean explicit = false;

        // Parse arguments
        for (String arg : args) {
            if (arg.equals("-a") || arg.equals("--all")) {
                showAll = true;
            } else if (arg.equals("-e") || arg.equals("--explicit")) {
                explicit = true;
            }
        }

        PackageDatabase db = new PackageDatabase();
        db.loadInstalled();

        Collection<Package> packages = db.getAllInstalled();

        if (packages.isEmpty()) {
            System.out.println("No packages installed.");
            return 0;
        }

        // Sort by name
        List<Package> sorted = new ArrayList<>(packages);
        sorted.sort(Comparator.comparing(Package::getName));

        System.out.println("Installed packages:\n");
        for (Package pkg : sorted) {
            System.out.printf("  %-30s %s\n", pkg.getName(), pkg.getVersion());
        }

        System.out.printf("\n%d package(s) installed.\n", packages.size());
        return 0;
    }
}
