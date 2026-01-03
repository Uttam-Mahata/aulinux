/**
 * Search command - searches for packages.
 */
package org.aulinux.aupkg.commands;

import java.util.List;

import org.aulinux.aupkg.core.PackageDatabase;
import org.aulinux.aupkg.model.Package;

public class SearchCommand implements Command {
    @Override
    public int execute(String[] args) throws Exception {
        if (args.length == 0) {
            System.err.println("aupkg search: no search term specified");
            return 1;
        }

        String keyword = args[0];

        PackageDatabase db = new PackageDatabase();
        db.loadInstalled();
        db.loadAvailable();

        List<Package> results = db.search(keyword);

        if (results.isEmpty()) {
            System.out.println("No packages found matching '" + keyword + "'");
            return 0;
        }

        System.out.println("Search results for '" + keyword + "':\n");
        for (Package pkg : results) {
            String status = pkg.isInstalled() ? "[installed]" : "";
            System.out.printf("  %-20s %-12s %s\n", 
                pkg.getName(), pkg.getVersion(), status);
            if (pkg.getDescription() != null) {
                System.out.printf("    %s\n", pkg.getDescription());
            }
        }

        System.out.printf("\n%d package(s) found.\n", results.size());
        return 0;
    }
}
