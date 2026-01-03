/**
 * AULinux Package Manager (aupkg)
 * 
 * Main entry point for the package manager CLI.
 */
package org.aulinux.aupkg;

import java.util.Arrays;

import org.aulinux.aupkg.commands.InfoCommand;
import org.aulinux.aupkg.commands.InstallCommand;
import org.aulinux.aupkg.commands.ListCommand;
import org.aulinux.aupkg.commands.RemoveCommand;
import org.aulinux.aupkg.commands.SearchCommand;
import org.aulinux.aupkg.commands.UpdateCommand;
import org.aulinux.aupkg.commands.UpgradeCommand;

public class Main {
    public static final String VERSION = "1.0.0";
    public static final String NAME = "aupkg";

    public static void main(String[] args) {
        if (args.length == 0) {
            printUsage();
            System.exit(1);
        }

        String command = args[0];
        String[] commandArgs = Arrays.copyOfRange(args, 1, args.length);

        try {
            int exitCode = executeCommand(command, commandArgs);
            System.exit(exitCode);
        } catch (Exception e) {
            System.err.println("aupkg: error: " + e.getMessage());
            System.exit(1);
        }
    }

    private static int executeCommand(String command, String[] args) throws Exception {
        switch (command) {
            case "install":
            case "i":
                return new InstallCommand().execute(args);
            
            case "remove":
            case "r":
                return new RemoveCommand().execute(args);
            
            case "update":
            case "u":
                return new UpdateCommand().execute(args);
            
            case "upgrade":
                return new UpgradeCommand().execute(args);
            
            case "search":
            case "s":
                return new SearchCommand().execute(args);
            
            case "info":
                return new InfoCommand().execute(args);
            
            case "list":
            case "l":
                return new ListCommand().execute(args);
            
            case "help":
            case "-h":
            case "--help":
                printUsage();
                return 0;
            
            case "version":
            case "-v":
            case "--version":
                printVersion();
                return 0;
            
            default:
                System.err.println("aupkg: unknown command '" + command + "'");
                System.err.println("Run 'aupkg help' for usage.");
                return 1;
        }
    }

    private static void printVersion() {
        System.out.println("aupkg (AULinux Package Manager) " + VERSION);
        System.out.println("Copyright (c) 2026 AULinux Team");
    }

    private static void printUsage() {
        System.out.println("aupkg - AULinux Package Manager");
        System.out.println();
        System.out.println("Usage: aupkg <command> [options] [packages...]");
        System.out.println();
        System.out.println("Commands:");
        System.out.println("  install, i    Install packages");
        System.out.println("  remove, r     Remove packages");
        System.out.println("  update, u     Update package database");
        System.out.println("  upgrade       Upgrade installed packages");
        System.out.println("  search, s     Search for packages");
        System.out.println("  info          Show package information");
        System.out.println("  list, l       List installed packages");
        System.out.println("  help          Show this help message");
        System.out.println("  version       Show version information");
        System.out.println();
        System.out.println("Options:");
        System.out.println("  -y, --yes     Assume yes to all prompts");
        System.out.println("  -q, --quiet   Quiet mode");
        System.out.println("  -v, --verbose Verbose output");
        System.out.println();
        System.out.println("Examples:");
        System.out.println("  aupkg install vim git");
        System.out.println("  aupkg search editor");
        System.out.println("  aupkg update && aupkg upgrade");
    }
}
