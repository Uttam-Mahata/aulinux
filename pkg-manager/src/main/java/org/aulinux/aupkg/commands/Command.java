/**
 * Base interface for aupkg commands.
 */
package org.aulinux.aupkg.commands;

public interface Command {
    /**
     * Execute the command with given arguments.
     * @param args command arguments
     * @return exit code (0 for success)
     */
    int execute(String[] args) throws Exception;
}
